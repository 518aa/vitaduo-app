//
//  MatchViewModel.swift
//  DateDrop3
//
//  匹配视图模型
//

import Foundation
import Combine

class MatchViewModel: ObservableObject {
    @Published var matches: [Match] = []
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var matchesLeft: Int = 0
    @Published var generateSuccess = false
    @Published var latestMatch: Match?
    @Published var didGenerateMatch = false

    private var cancellables = Set<AnyCancellable>()
    private let networkManager = NetworkManager.shared
    private let matchesCacheKey = "cached_matches"
    private let matchesCacheTTL: TimeInterval = 60 * 2
    private let matchesCountCacheKey = "cached_matches_count"
    private let matchesCountCacheTTL: TimeInterval = 60 * 2
    private let matchIntroCacheKey = "cached_match_intros"
    private let matchIntroCacheTTL: TimeInterval = 60 * 60 * 24 * 7

    private struct MatchesCache: Codable {
        let matches: [Match]
        let updatedAt: TimeInterval
    }

    private struct MatchesCountCache: Codable {
        let matchesLeft: Int
        let updatedAt: TimeInterval
    }

    private struct MatchIntroCache: Codable {
        var intros: [Int: CachedIntro]
        let updatedAt: TimeInterval
    }

    private struct CachedIntro: Codable {
        let intro: String
        let updatedAt: TimeInterval
    }

    // MARK: - 加载匹配列表

    func loadMyMatches(force: Bool = false) {
        errorMessage = nil
        let cache = loadMatchesCache()
        if let cache {
            let merged = mergeIntrosIntoMatches(cache.matches)
            matches = merged
            latestMatch = merged.first
            isLoading = false
        } else {
            isLoading = true
        }

        if !force, let cache, isMatchesCacheFresh(cache) {
            isLoading = false
        }

        networkManager.getMyMatches()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case let .failure(error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }
                    let merged = self.mergeIntrosIntoMatches(response.matches)
                    let (updated, didChange) = self.mergeMatches(existing: self.matches, incoming: merged)
                    if didChange {
                        self.matches = updated
                        self.latestMatch = updated.first
                        self.saveMatchesCache(updated)
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 生成新匹配

    func generateMatches() {
        isGenerating = true
        errorMessage = nil
        generateSuccess = false
        didGenerateMatch = false

        networkManager.generateMatches()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isGenerating = false
                    if case let .failure(error) = completion {
                        self?.errorMessage = error.localizedDescription
                        self?.loadMatchesCount()
                    }
                },
                receiveValue: { [weak self] response in
                    if let first = response.matches.first {
                        if let intro = first.ai_intro, !intro.isEmpty {
                            self?.saveMatchIntro(matchId: first.id, intro: intro)
                        }
                        let merged = self?.mergeIntrosIntoMatches([first]) ?? [first]
                        self?.matches = merged
                        self?.latestMatch = merged.first
                        self?.didGenerateMatch = true
                    } else {
                        self?.matches = []
                        self?.latestMatch = nil
                    }
                    self?.matchesLeft = response.matches_left
                    self?.generateSuccess = true
                    if let matches = self?.matches {
                        self?.saveMatchesCache(matches)
                    }
                    self?.saveMatchesCountCache(response.matches_left)
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 加载剩余次数

    func loadMatchesCount() {
        if let cache = loadMatchesCountCache(), isMatchesCountCacheFresh(cache) {
            matchesLeft = cache.matchesLeft
            return
        }
        networkManager.getMatchesCount()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] response in
                    self?.matchesLeft = response["matches_left"] ?? 0
                    if let left = self?.matchesLeft {
                        self?.saveMatchesCountCache(left)
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 开始聊天

    func startChat(matchId: Int) {
        networkManager.startChat(matchId: matchId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] _ in
                    // 重新加载匹配列表以获取更新状态
                    self?.loadMyMatches(force: true)
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 购买匹配次数

    func purchaseMatches(matchesAdded: Int, amount: Double) {
        networkManager.purchaseMatches(matchesAdded: matchesAdded, amount: amount)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    self?.matchesLeft = response.matches_left
                    self?.saveMatchesCountCache(response.matches_left)
                }
            )
            .store(in: &cancellables)
    }

    private func saveMatchesCache(_ matches: [Match]) {
        let cache = MatchesCache(matches: matches, updatedAt: Date().timeIntervalSince1970)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: matchesCacheKey)
        }
    }

    private func loadMatchesCache() -> MatchesCache? {
        guard let data = UserDefaults.standard.data(forKey: matchesCacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MatchesCache.self, from: data)
    }

    private func isMatchesCacheFresh(_ cache: MatchesCache) -> Bool {
        Date().timeIntervalSince1970 - cache.updatedAt < matchesCacheTTL
    }

    private func saveMatchesCountCache(_ matchesLeft: Int) {
        let cache = MatchesCountCache(matchesLeft: matchesLeft, updatedAt: Date().timeIntervalSince1970)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: matchesCountCacheKey)
        }
    }

    private func loadMatchesCountCache() -> MatchesCountCache? {
        guard let data = UserDefaults.standard.data(forKey: matchesCountCacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MatchesCountCache.self, from: data)
    }

    private func isMatchesCountCacheFresh(_ cache: MatchesCountCache) -> Bool {
        Date().timeIntervalSince1970 - cache.updatedAt < matchesCountCacheTTL
    }

    private func saveMatchIntro(matchId: Int, intro: String) {
        let trimmed = intro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = loadMatchIntroCache() ?? MatchIntroCache(intros: [:], updatedAt: Date().timeIntervalSince1970)
        current.intros[matchId] = CachedIntro(intro: trimmed, updatedAt: Date().timeIntervalSince1970)
        let cache = MatchIntroCache(intros: current.intros, updatedAt: Date().timeIntervalSince1970)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: matchIntroCacheKey)
        }
    }

    private func loadMatchIntroCache() -> MatchIntroCache? {
        guard let data = UserDefaults.standard.data(forKey: matchIntroCacheKey) else {
            return nil
        }
        if let decoded = try? JSONDecoder().decode(MatchIntroCache.self, from: data) {
            return decoded
        }
        UserDefaults.standard.removeObject(forKey: matchIntroCacheKey)
        return nil
    }

    private func mergeIntrosIntoMatches(_ matches: [Match]) -> [Match] {
        guard let cache = loadMatchIntroCache() else {
            return matches
        }
        let now = Date().timeIntervalSince1970
        var updatedIntros = cache.intros
        var didUpdate = false
        let merged = matches.map { match in
            if let intro = match.ai_intro, !intro.isEmpty {
                return match
            }
            if let cached = cache.intros[match.id],
               now - cached.updatedAt < matchIntroCacheTTL {
                return matchWithIntro(match, intro: cached.intro)
            }
            if let cached = cache.intros[match.id], now - cached.updatedAt >= matchIntroCacheTTL {
                updatedIntros.removeValue(forKey: match.id)
                didUpdate = true
            }
            return match
        }
        if didUpdate {
            let refreshed = MatchIntroCache(intros: updatedIntros, updatedAt: now)
            if let encoded = try? JSONEncoder().encode(refreshed) {
                UserDefaults.standard.set(encoded, forKey: matchIntroCacheKey)
            }
        }
        return merged
    }

    private func mergeMatches(existing: [Match], incoming: [Match]) -> ([Match], Bool) {
        if incoming.isEmpty {
            return (existing, false)
        }
        if existing == incoming {
            return (existing, false)
        }
        return (incoming, true)
    }

    private func matchWithIntro(_ match: Match, intro: String) -> Match {
        Match(
            id: match.id,
            user1_id: match.user1_id,
            user2_id: match.user2_id,
            similarity_score: match.similarity_score,
            status: match.status,
            is_unlocked: match.is_unlocked,
            chat_message_count: match.chat_message_count,
            created_at: match.created_at,
            last_message_at: match.last_message_at,
            last_message_sender_id: match.last_message_sender_id,
            unread_count: match.unread_count,
            ai_intro: intro,
            partner_nickname: match.partner_nickname
        )
    }
}
