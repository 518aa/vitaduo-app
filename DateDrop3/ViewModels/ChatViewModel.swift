//
//  ChatViewModel.swift
//  DateDrop3
//
//  聊天视图模型
//

import Foundation
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var canCompleteChat = false
    @Published var translatedMessages: [Int: String] = [:]
    @Published var translatingMessageIds: Set<Int> = []
    
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var currentMatchId: Int?
    private var currentUserId: Int?
    private var pendingLocalMessageIds: Set<Int> = []
    private let messagesCacheKeyPrefix = "cached_chat_messages_"
    private let messagesCacheTTL: TimeInterval = 20
    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "app_language") ?? "en"
    }

    private struct MessagesCache: Codable {
        let messages: [ChatMessage]
        let updatedAt: TimeInterval
    }
    
    deinit {
        stopPolling()
    }
    
    // MARK: - 消息加载
    
    func loadMessages(matchId: Int, userId: Int? = nil, silent: Bool = false) {
        currentMatchId = matchId
        if let userId = userId {
            currentUserId = userId
        }

        if let cache = loadMessagesCache(matchId: matchId) {
            messages = cache.messages
            checkCanComplete()
        }
        if !silent {
            isLoading = messages.isEmpty
        }
        
        NetworkManager.shared.getChatMessages(matchId: matchId, userId: currentUserId)
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                if !silent {
                    self?.isLoading = false
                }
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            },
            receiveValue: { [weak self] response in
                guard let self = self else { return }
                let merged = self.mergeMessages(existing: self.messages, incoming: response.messages)
                if self.shouldUpdateMessages(current: self.messages, incoming: merged) {
                    self.messages = merged
                    self.checkCanComplete()
                    self.saveMessagesCache(matchId: matchId, messages: merged)
                }
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: - 房间管理
    
    func joinMatch(matchId: Int, userId: Int?) {
        currentMatchId = matchId
        currentUserId = userId
        startPolling()
    }
    
    func leaveMatch(matchId: Int) {
        currentMatchId = nil
        stopPolling()
    }
    
    private func startPolling() {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let matchId = self.currentMatchId else { return }
            self.loadMessages(matchId: matchId, userId: self.currentUserId, silent: true)
        }
    }
    
    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - 发送消息
    
    func sendMessage(matchId: Int, message: String, userId: Int?) {
        guard !message.isEmpty else { return }

        if let userId = userId {
            currentUserId = userId
        }

        let localId = generateLocalMessageId()
        let senderId = userId ?? currentUserId ?? 0
        let localMessage = ChatMessage(
            id: localId,
            match_id: matchId,
            sender_id: senderId,
            content: message,
            message_type: "text",
            is_read: true,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        pendingLocalMessageIds.insert(localId)
        messages.append(localMessage)
        checkCanComplete()
        if let matchId = currentMatchId {
            saveMessagesCache(matchId: matchId, messages: messages)
        }

        NetworkManager.shared.sendMessage(matchId: matchId, message: message, userId: userId)
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                if case let .failure(error) = completion {
                    if let index = self?.messages.firstIndex(where: { $0.id == localId }) {
                        self?.messages.remove(at: index)
                        self?.pendingLocalMessageIds.remove(localId)
                        if let matchId = self?.currentMatchId {
                            self?.saveMessagesCache(matchId: matchId, messages: self?.messages ?? [])
                        }
                    }
                    if self?.appLanguage == "zh" {
                        self?.errorMessage = "发送失败: \(error.localizedDescription)"
                    } else {
                        self?.errorMessage = "Send failed: \(error.localizedDescription)"
                    }
                }
            },
            receiveValue: { [weak self] response in
                // Replace local message with server response
                if let msg = response.data {
                    if let index = self?.messages.firstIndex(where: { $0.id == localId }) {
                        self?.messages[index] = msg
                        self?.pendingLocalMessageIds.remove(localId)
                    } else if self?.messages.contains(where: { $0.id == msg.id }) == false {
                        self?.messages.append(msg)
                    }
                    self?.checkCanComplete()
                    if let matchId = self?.currentMatchId {
                        self?.saveMessagesCache(matchId: matchId, messages: self?.messages ?? [])
                    }
                }
                // Immediately re-fetch to capture AI auto-replies
                if let self = self, let matchId = self.currentMatchId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.loadMessages(matchId: matchId, userId: self.currentUserId, silent: true)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                        self.loadMessages(matchId: matchId, userId: self.currentUserId, silent: true)
                    }
                }
            }
        )
        .store(in: &cancellables)
    }

    func translateMessage(messageId: Int, text: String, targetLanguage: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if translatedMessages[messageId] != nil {
            return
        }
        translatingMessageIds.insert(messageId)
        NetworkManager.shared.translate(text: trimmed, targetLanguage: targetLanguage)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.translatingMessageIds.remove(messageId)
                    if case let .failure(error) = completion {
                        if self?.appLanguage == "zh" {
                            self?.errorMessage = "翻译失败: \(error.localizedDescription)"
                        } else {
                            self?.errorMessage = "Translation failed: \(error.localizedDescription)"
                        }
                    }
                },
                receiveValue: { [weak self] response in
                    self?.translatedMessages[messageId] = response.translated_text
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 辅助方法
    
    private func checkCanComplete() {
        // 假设双方互发消息总数达到20条可以完成聊天
        canCompleteChat = messages.count >= 20
    }

    private func saveMessagesCache(matchId: Int, messages: [ChatMessage]) {
        let cache = MessagesCache(messages: messages, updatedAt: Date().timeIntervalSince1970)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: messagesCacheKeyPrefix + String(matchId))
        }
    }

    private func loadMessagesCache(matchId: Int) -> MessagesCache? {
        guard let data = UserDefaults.standard.data(forKey: messagesCacheKeyPrefix + String(matchId)) else {
            return nil
        }
        return try? JSONDecoder().decode(MessagesCache.self, from: data)
    }

    private func isMessagesCacheFresh(_ cache: MessagesCache) -> Bool {
        Date().timeIntervalSince1970 - cache.updatedAt < messagesCacheTTL
    }

    private func mergeMessages(existing: [ChatMessage], incoming: [ChatMessage]) -> [ChatMessage] {
        if incoming.isEmpty {
            return existing
        }
        let incomingIds = Set(incoming.map { $0.id })
        let pending = existing.filter { pendingLocalMessageIds.contains($0.id) && !incomingIds.contains($0.id) }
        if pending.isEmpty {
            return incoming
        }
        return incoming + pending
    }

    private func shouldUpdateMessages(current: [ChatMessage], incoming: [ChatMessage]) -> Bool {
        if current.count != incoming.count {
            return true
        }
        for (index, message) in current.enumerated() {
            if message.id != incoming[index].id {
                return true
            }
        }
        return false
    }

    private func generateLocalMessageId() -> Int {
        var id = -Int(Date().timeIntervalSince1970 * 1000)
        while pendingLocalMessageIds.contains(id) || messages.contains(where: { $0.id == id }) {
            id -= 1
        }
        return id
    }

    // MARK: - Moderation (Apple Guideline 1.2)

    /// Report a user for objectionable content
    func reportUser(reportedUserId: Int, matchId: Int, reason: String) {
        NetworkManager.shared.reportUser(reportedUserId: reportedUserId, matchId: matchId, reason: reason)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
    }

    /// Block a user from contacting you
    func blockUser(blockedUserId: Int) {
        NetworkManager.shared.blockUser(blockedUserId: blockedUserId)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)
    }

    /// Delete own message from a conversation
    func deleteMessage(messageId: Int, matchId: Int) {
        messages.removeAll { $0.id == messageId }
        NetworkManager.shared.deleteMessage(messageId: messageId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        // Reload messages if deletion failed
                        self?.loadMessages(matchId: matchId, userId: nil)
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
}
