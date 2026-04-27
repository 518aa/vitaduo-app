//
//  MatchResultsView.swift
//  DateDrop3
//
//  匹配结果页 - 显示3个匹配对象
//

import SwiftUI

struct MatchResultsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var router: AppRouter
    @AppStorage("app_language") private var appLanguage = "en"
    @StateObject private var matchViewModel = MatchViewModel()
    @StateObject private var chatViewModel = ChatViewModel()

    @State private var showPaywall = false
    @State private var showMatchPrompt = false
    @State private var showNoMatchAlert = false

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                headerView

                ScrollView {
                    VStack(spacing: AppTheme.spacingM) {
                        matchActions
                        if matchViewModel.isLoading && matchViewModel.matches.isEmpty {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.textPrimary))
                        }
                        latestMatchSection
                        if let errorMessage = matchViewModel.errorMessage, !errorMessage.isEmpty, errorMessage != noMatchMessage {
                            Text(errorMessage)
                                .font(AppTheme.bodyPrimary)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppTheme.spacingL)
                        }
                    }
                    .padding(.vertical, AppTheme.spacingS)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(authViewModel)
            }
        }
        .onAppear {
            matchViewModel.loadMatchesCount()
            loadMatches()
        }
        .onChange(of: matchViewModel.didGenerateMatch) { didGenerate in
            if didGenerate {
                showMatchPrompt = true
                matchViewModel.didGenerateMatch = false
            }
        }
        .onChange(of: matchViewModel.errorMessage) { message in
            if message == noMatchMessage {
                showNoMatchAlert = true
                matchViewModel.errorMessage = nil
            }
        }
        .alert(appLanguage == "zh" ? "发现一位同频伙伴" : "A connection is ready", isPresented: $showMatchPrompt) {
            Button(appLanguage == "zh" ? "知道了" : "OK", role: .cancel) {}
        } message: {
            Text(appLanguage == "zh"
                 ? "点击开始对话，如果双方的评价都在四星以上，系统会解锁详细资料，否则您的个人资料将始终处于保密状态。"
                 : "Tap Start Chat to begin. If both ratings are four stars or higher, the system unlocks real profiles; otherwise, your profile remains private.")
        }
        .alert(appLanguage == "zh" ? "暂未发现同频伙伴" : "No connection yet", isPresented: $showNoMatchAlert) {
            Button(appLanguage == "zh" ? "知道了" : "OK", role: .cancel) {}
        } message: {
            Text(noMatchMessageDisplay)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: AppTheme.spacingM) {
            Text(appLanguage == "zh" ? "发现同频伙伴" : "Discover")
                .font(AppTheme.displayMedium)
                .foregroundColor(AppTheme.textPrimary)

            Text(appLanguage == "zh"
                 ? "基于价值观问卷的相似和互补性，通过科学算法为每个用户推荐同频的伙伴。点击开始发现，我们将为您在全球范围内推荐与你价值观一致的人。"
                 : "We connect you with like-minded people based on values similarity and complementarity (cosine similarity). Tap Discover to find someone who shares your worldview.")
                .font(AppTheme.bodyPrimary)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingL)

            HStack(spacing: 6) {
                Text(appLanguage == "zh" ? "剩余次数:" : "Remaining:")
                Button(action: { showPaywall = true }) {
                    Text("\(matchViewModel.matchesLeft)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, AppTheme.spacingXS)
                        .background(AppTheme.accent.opacity(0.15))
                        .cornerRadius(10)
                }
            }
            .font(AppTheme.bodyPrimary)
            .foregroundColor(AppTheme.textSecondary)
        }
        .padding(AppTheme.spacingM)
    }

    // MARK: - Discover Button

    private var matchActions: some View {
        VStack(spacing: AppTheme.spacingM) {
            Button(action: handleMatchTap) {
                ZStack {
                    if matchViewModel.matchesLeft > 0 {
                        RoundedRectangle(cornerRadius: AppTheme.radiusXL)
                            .fill(AppTheme.heroGradient)
                    } else {
                        RoundedRectangle(cornerRadius: AppTheme.radiusXL)
                            .fill(AppTheme.bgElevated)
                    }
                    if matchViewModel.isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.textPrimary))
                    } else {
                        Text(appLanguage == "zh" ? "开始发现" : "Discover")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.radiusXL))
            .padding(.horizontal, AppTheme.spacingL)
            .disabled(matchViewModel.matchesLeft <= 0 || matchViewModel.isGenerating)
        }
    }

    // MARK: - Latest Match Card

    private var latestMatchSection: some View {
        VStack(spacing: AppTheme.spacingM) {
            if let match = matchViewModel.latestMatch {
                GlassCard(cornerRadius: AppTheme.radiusL, padding: AppTheme.spacingM) {
                    ZStack {
                        // Gradient overlay on card
                        RoundedRectangle(cornerRadius: AppTheme.radiusL)
                            .fill(AppTheme.heroGradient)
                            .opacity(0.08)

                        VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                            // Status pill
                            HStack {
                                PillTag(
                                    text: appLanguage == "zh" ? "热聊中" : "Hot Chat",
                                    color: AppTheme.warning
                                )
                                Spacer()
                                if match.is_unlocked {
                                    PillTag(
                                        text: appLanguage == "zh" ? "已解锁" : "Unlocked",
                                        color: AppTheme.success
                                    )
                                }
                            }

                            // Name + code
                            HStack(spacing: AppTheme.spacingS) {
                                Text(matchDisplayName(for: match, currentUserId: authViewModel.currentUser?.id))
                                    .font(AppTheme.titleCard)
                                    .foregroundColor(AppTheme.textPrimary)
                                if shouldShowMatchCode(for: match, currentUserId: authViewModel.currentUser?.id) {
                                    Text(matchDisplayCode(for: match, currentUserId: authViewModel.currentUser?.id))
                                        .font(AppTheme.captionPill)
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }

                            // AI intro
                            if let intro = match.ai_intro, !intro.isEmpty {
                                Text(intro)
                                    .font(AppTheme.bodyPrimary)
                                    .foregroundColor(AppTheme.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }

                            // Similarity (同频度) with mono font + gradient fill
                            HStack {
                                Text(appLanguage == "zh" ? "同频度" : "Similarity")
                                    .font(AppTheme.bodyPrimary)
                                    .foregroundColor(AppTheme.textSecondary)
                                Spacer()
                                Text("\(Int(match.similarity_score))%")
                                    .font(AppTheme.monoNumber)
                                    .foregroundStyle(AppTheme.heroGradient)
                            }
                            .padding(.vertical, AppTheme.spacingXS)

                            // Status text
                            HStack {
                                PillTag(
                                    text: getStatusText(match.status),
                                    color: AppTheme.accentLight
                                )
                                Spacer()
                            }

                            // Start Chat button
                            Button(action: { startChat(match: match) }) {
                                HStack(spacing: AppTheme.spacingS) {
                                    Image(systemName: "message.fill")
                                        .foregroundColor(AppTheme.textPrimary)
                                    Text(appLanguage == "zh" ? "开始聊天" : "Start Chat")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(AppTheme.textPrimary)
                                    Spacer()
                                }
                                .padding(AppTheme.spacingM)
                                .background(AppTheme.heroGradient)
                                .cornerRadius(AppTheme.radiusM)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.spacingL)
            } else {
                Text(appLanguage == "zh" ? "点击开始发现同频伙伴" : "Tap Discover to find like-minded people")
                    .font(AppTheme.bodyPrimary)
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.top, AppTheme.spacingS)
            }
        }
    }

    // MARK: - Business Logic

    private func loadMatches() {
        matchViewModel.loadMyMatches(force: false)
    }

    private func generateMatches() {
        matchViewModel.generateMatches()
    }

    private func handleMatchTap() {
        if matchViewModel.matchesLeft > 0 {
            generateMatches()
        } else {
            showPaywall = true
        }
    }

    private func startChat(match: Match) {
        matchViewModel.startChat(matchId: match.id)
        router.push(.chat(match))
    }

    private func matchDisplayName(for match: Match, currentUserId: Int?) -> String {
        let nickname = match.partner_nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !nickname.isEmpty {
            return nickname
        }
        return match.getPartnerDisplayCode(currentUserId: currentUserId)
    }

    private func matchDisplayCode(for match: Match, currentUserId: Int?) -> String {
        match.getPartnerDisplayCode(currentUserId: currentUserId)
    }

    private func shouldShowMatchCode(for match: Match, currentUserId: Int?) -> Bool {
        matchDisplayName(for: match, currentUserId: currentUserId) != matchDisplayCode(for: match, currentUserId: currentUserId)
    }

    private func getStatusText(_ status: String) -> String {
        switch status {
        case "pending": return appLanguage == "zh" ? "等待开始" : "Pending"
        case "chatting": return appLanguage == "zh" ? "聊天中" : "Chatting"
        case "completed": return appLanguage == "zh" ? "已完成" : "Completed"
        case "failed": return appLanguage == "zh" ? "发现失败" : "Failed"
        default: return ""
        }
    }

    private var noMatchMessage: String {
        "根据算法，暂未发现同频的伙伴，请稍后再试。"
    }

    private var noMatchMessageDisplay: LocalizedStringKey {
        appLanguage == "zh" ? LocalizedStringKey(noMatchMessage) : "No suitable match found for now. Please try again later."
    }
}

#Preview {
    NavigationView {
        MatchResultsView()
            .environmentObject(AuthViewModel())
            .environmentObject(AppRouter())
    }
}
