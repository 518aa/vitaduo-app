//
//  ChatView.swift
//  DateDrop3
//
//  聊天页 — Added: report user, block user, delete own message (Apple Guideline 1.2)
//

import SwiftUI
import Combine

struct ChatView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var router: AppRouter
    @StateObject private var chatViewModel = ChatViewModel()
    @AppStorage("app_language") private var appLanguage = "en"

    let match: Match

    @State private var messageText = ""
    @State private var isEmojiPickerPresented = false
    @FocusState private var isInputFocused: Bool

    // Moderation state
    @State private var showReportSheet = false
    @State private var showBlockAlert = false
    @State private var showBlockedConfirmation = false
    @State private var reportReason = ""
    @State private var showReportSuccess = false
    @State private var messageToDelete: ChatMessage? = nil
    @State private var showDeleteConfirm = false

    private let emojiItems = [
        "😀","😂","😍","🥰","😘","😎","🤔","😭",
        "👍","👏","🔥","❤️","✨","🎉","💯","🥳",
        "😅","😇","😉","😊","😜","🤗","😴","😤",
        "🙌","🙏","💪","🤝","💖","💡","🍀","🌟"
    ]

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                chatHeader
                messagesList

                if isEmojiPickerPresented {
                    emojiPickerPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                inputBar
            }
        }
        .onAppear {
            let userId = authViewModel.currentUser?.id
            chatViewModel.loadMessages(matchId: match.id, userId: userId)
            chatViewModel.joinMatch(matchId: match.id, userId: userId)
        }
        .onChange(of: isInputFocused) { focused in
            if focused { isEmojiPickerPresented = false }
        }
        .onDisappear {
            chatViewModel.leaveMatch(matchId: match.id)
        }
        // Report sheet
        .sheet(isPresented: $showReportSheet) {
            reportSheet
        }
        // Block confirmation
        .alert(
            appLanguage == "zh" ? "屏蔽用户" : "Block User",
            isPresented: $showBlockAlert
        ) {
            Button(appLanguage == "zh" ? "确认屏蔽" : "Block", role: .destructive) {
                blockUser()
            }
            Button(appLanguage == "zh" ? "取消" : "Cancel", role: .cancel) {}
        } message: {
            Text(appLanguage == "zh"
                 ? "屏蔽后，该用户将无法再联系您。此操作无法撤销。"
                 : "This user will no longer be able to contact you. This cannot be undone.")
        }
        // Block success
        .alert(
            appLanguage == "zh" ? "已屏蔽" : "User Blocked",
            isPresented: $showBlockedConfirmation
        ) {
            Button(appLanguage == "zh" ? "确定" : "OK", role: .cancel) {
                router.pop()
            }
        } message: {
            Text(appLanguage == "zh"
                 ? "该用户已被屏蔽。"
                 : "The user has been blocked successfully.")
        }
        // Delete message confirmation
        .alert(
            appLanguage == "zh" ? "删除消息" : "Delete Message",
            isPresented: $showDeleteConfirm
        ) {
            Button(appLanguage == "zh" ? "删除" : "Delete", role: .destructive) {
                if let msg = messageToDelete {
                    chatViewModel.deleteMessage(messageId: msg.id, matchId: match.id)
                }
                messageToDelete = nil
            }
            Button(appLanguage == "zh" ? "取消" : "Cancel", role: .cancel) {
                messageToDelete = nil
            }
        } message: {
            Text(appLanguage == "zh"
                 ? "确定要删除这条消息吗？此操作无法撤销。"
                 : "Are you sure you want to delete this message? This cannot be undone.")
        }
        // Report success toast
        .alert(
            appLanguage == "zh" ? "举报已提交" : "Report Submitted",
            isPresented: $showReportSuccess
        ) {
            Button(appLanguage == "zh" ? "确定" : "OK", role: .cancel) {}
        } message: {
            Text(appLanguage == "zh"
                 ? "感谢您的举报，我们将在24小时内处理。"
                 : "Thank you for your report. We will review it within 24 hours.")
        }
    }

    // MARK: - Chat Header (with safety menu)

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(chatTitleName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if shouldShowChatCode {
                        Text(chatTitleCode)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                if match.is_unlocked {
                    Text(appLanguage == "zh" ? "已解锁详细资料" : "Profile unlocked")
                        .font(.system(size: 14)).foregroundColor(.green)
                } else {
                    Text(appLanguage == "zh" ? "匿名聊天" : "Anonymous chat")
                        .font(.system(size: 14)).foregroundColor(.gray)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                // Rate button
                if chatViewModel.canCompleteChat {
                    Button(action: { router.push(.rating(match)) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").font(.system(size: 14)).foregroundColor(.white)
                            Text(appLanguage == "zh" ? "评价" : "Rate")
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(chatViewModel.messages.count) / 20").font(.system(size: 14)).foregroundColor(.gray)
                        Text(appLanguage == "zh" ? "开始评分" : "Rate at 20").font(.system(size: 14)).foregroundColor(.gray)
                    }
                }

                // Safety menu (report / block)
                Menu {
                    Button(role: .none, action: { showReportSheet = true }) {
                        Label(
                            appLanguage == "zh" ? "举报不当内容" : "Report Objectionable Content",
                            systemImage: "flag"
                        )
                    }
                    Button(role: .destructive, action: { showBlockAlert = true }) {
                        Label(
                            appLanguage == "zh" ? "屏蔽此用户" : "Block This User",
                            systemImage: "person.slash"
                        )
                    }
                    Divider()
                    Button(role: .none, action: { openSupportEmail() }) {
                        Label(
                            appLanguage == "zh" ? "联系客服" : "Contact Support",
                            systemImage: "envelope"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
    }

    // MARK: - Report Sheet

    private var reportSheet: some View {
        NavigationView {
            ZStack {
                AppTheme.bgPrimary.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text(appLanguage == "zh"
                         ? "请说明举报原因（可选）："
                         : "Describe the issue (optional):")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .padding(.top, 20)

                    let reportReasons = appLanguage == "zh"
                        ? ["仇恨言论或骚扰", "裸露或色情内容", "欺诈或冒充", "垃圾信息", "人身安全威胁", "其他"]
                        : ["Hate speech or harassment", "Nudity or pornography", "Fraud or impersonation", "Spam", "Threat to safety", "Other"]

                    ForEach(reportReasons, id: \.self) { reason in
                        Button(action: {
                            reportReason = reason
                        }) {
                            HStack {
                                Text(reason)
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                Spacer()
                                if reportReason == reason {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(reportReason == reason ? 0.12 : 0.05))
                            .cornerRadius(12)
                        }
                    }

                    Spacer()

                    Text(appLanguage == "zh"
                         ? "我们将在24小时内审核您的举报。如需紧急帮助，请发送邮件至 support@vitaduo.app"
                         : "We will review your report within 24 hours. For urgent issues, email support@vitaduo.app")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .padding(.bottom, 8)

                    Button(action: submitReport) {
                        Text(appLanguage == "zh" ? "提交举报" : "Submit Report")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white)
                            .cornerRadius(26)
                    }
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle(appLanguage == "zh" ? "举报用户" : "Report User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(appLanguage == "zh" ? "取消" : "Cancel") {
                        showReportSheet = false
                        reportReason = ""
                    }
                    .foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: - Messages List

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatViewModel.messages) { message in
                        let isOwn = message.sender_id == authViewModel.currentUser?.id
                        MessageBubble(
                            message: message,
                            isFromCurrentUser: isOwn,
                            appLanguage: appLanguage,
                            translatedText: chatViewModel.translatedMessages[message.id],
                            isTranslating: chatViewModel.translatingMessageIds.contains(message.id),
                            onTranslate: {
                                chatViewModel.translateMessage(
                                    messageId: message.id,
                                    text: message.content,
                                    targetLanguage: appLanguage
                                )
                            },
                            onReport: isOwn ? nil : {
                                reportReason = ""
                                showReportSheet = true
                            },
                            onDelete: isOwn ? {
                                messageToDelete = message
                                showDeleteConfirm = true
                            } : nil
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onTapGesture {
                isEmojiPickerPresented = false
                isInputFocused = false
            }
            .onChange(of: chatViewModel.messages.count) { _ in
                if let lastMessage = chatViewModel.messages.last {
                    withAnimation { proxy.scrollTo(lastMessage.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            Button(action: toggleEmojiPicker) {
                Image(systemName: isEmojiPickerPresented ? "keyboard" : "face.smiling")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(10)
            }
            TextField(appLanguage == "zh" ? "输入消息..." : "Type a message...", text: $messageText)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(20)
                .focused($isInputFocused)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(messageText.isEmpty ? .gray : AppTheme.accent)
            }
            .disabled(messageText.isEmpty)
        }
        .padding()
    }

    // MARK: - Emoji Picker

    private var emojiPickerPanel: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 8)
        return VStack(spacing: 0) {
            HStack {
                Text(appLanguage == "zh" ? "表情" : "Emojis")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.gray)
                Spacer()
                Button(action: { isEmojiPickerPresented = false }) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(emojiItems, id: \.self) { emoji in
                        Button(action: { messageText += emoji }) {
                            Text(emoji).font(.system(size: 22))
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .frame(maxHeight: 240)
        .background(Color.black.opacity(0.2))
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        chatViewModel.sendMessage(matchId: match.id, message: messageText, userId: authViewModel.currentUser?.id)
        messageText = ""
        isInputFocused = false
        isEmojiPickerPresented = false
    }

    private func toggleEmojiPicker() {
        withAnimation(.easeOut(duration: 0.18)) { isEmojiPickerPresented.toggle() }
        if isEmojiPickerPresented { isInputFocused = false }
    }

    private func submitReport() {
        let partnerId = match.user1_id == authViewModel.currentUser?.id ? match.user2_id : match.user1_id
        chatViewModel.reportUser(
            reportedUserId: partnerId,
            matchId: match.id,
            reason: reportReason.isEmpty ? "No reason specified" : reportReason
        )
        showReportSheet = false
        reportReason = ""
        showReportSuccess = true
    }

    private func blockUser() {
        let partnerId = match.user1_id == authViewModel.currentUser?.id ? match.user2_id : match.user1_id
        chatViewModel.blockUser(blockedUserId: partnerId)
        showBlockedConfirmation = true
    }

    private func openSupportEmail() {
        if let url = URL(string: "mailto:support@vitaduo.app") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Helpers

    private var chatTitleName: String {
        let nickname = match.partner_nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !nickname.isEmpty { return nickname }
        return match.getPartnerDisplayCode(currentUserId: authViewModel.currentUser?.id)
    }

    private var chatTitleCode: String {
        match.getPartnerDisplayCode(currentUserId: authViewModel.currentUser?.id)
    }

    private var shouldShowChatCode: Bool { chatTitleName != chatTitleCode }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let isFromCurrentUser: Bool
    let appLanguage: String
    let translatedText: String?
    let isTranslating: Bool
    let onTranslate: () -> Void
    var onReport: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(.system(size: 16))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.9), AppTheme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundColor(.black)
                        .cornerRadius(20)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .trailing)
                        .contextMenu {
                            if let onDelete {
                                Button(role: .destructive, action: onDelete) {
                                    Label(
                                        appLanguage == "zh" ? "删除" : "Delete",
                                        systemImage: "trash"
                                    )
                                }
                            }
                        }

                    if let translatedText, !translatedText.isEmpty {
                        Text(translatedText).font(.system(size: 14)).foregroundColor(.gray)
                            .padding(.trailing, 4)
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: .trailing)
                    }
                    HStack(spacing: 4) {
                        Text(formatTime(message.created_at))
                    }
                    .font(.system(size: 11)).foregroundColor(.gray.opacity(0.7))
                }
            } else {
                // Partner avatar icon
                Circle()
                    .fill(AppTheme.accent.opacity(0.2))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accent)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .font(.system(size: 16)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.white.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .cornerRadius(20)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.65, alignment: .leading)
                        .contextMenu {
                            Button(action: onTranslate) {
                                Label(appLanguage == "zh" ? "翻译" : "Translate", systemImage: "character.bubble")
                            }
                            if let onReport {
                                Divider()
                                Button(role: .destructive, action: onReport) {
                                    Label(
                                        appLanguage == "zh" ? "举报此消息" : "Report This Message",
                                        systemImage: "flag"
                                    )
                                }
                            }
                        }

                    if isTranslating {
                        HStack(spacing: 4) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                .scaleEffect(0.6)
                            Text(appLanguage == "zh" ? "翻译中..." : "Translating...")
                                .font(.system(size: 13)).foregroundColor(.gray)
                        }
                    } else if let translatedText, !translatedText.isEmpty {
                        Text(translatedText).font(.system(size: 14)).foregroundColor(.gray.opacity(0.7))
                            .padding(.leading, 4)
                    }
                    Text(formatTime(message.created_at))
                        .font(.system(size: 11)).foregroundColor(.gray.opacity(0.7))
                        .padding(.leading, 4)
                }
                Spacer(minLength: 48)
            }
        }
    }

    private func formatTime(_ dateString: String?) -> String {
        guard let dateString, let date = ISO8601DateFormatter().date(from: dateString) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationView {
        ChatView(match: Match(
            id: 1, user1_id: 1, user2_id: 2,
            similarity_score: 0.92, status: "chatting",
            is_unlocked: false, chat_message_count: 15,
            created_at: nil, last_message_at: nil,
            last_message_sender_id: nil, unread_count: nil,
            ai_intro: nil, partner_nickname: "Alex"
        ))
        .environmentObject(AuthViewModel())
        .environmentObject(AppRouter())
    }
}
