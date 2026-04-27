//
//  ContentView.swift
//  DateDrop3
//
//  Created by mac on 2026/2/17.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var router = AppRouter()
    @State private var selectedTab: AppTab = .matches
    @AppStorage("app_language") private var appLanguage = "en"

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                if !authViewModel.isQuestionnaireCompleted {
                    NavigationStack {
                        QuestionnaireView()
                            .environmentObject(router)
                    }
                } else {
                    NavigationStack(path: $router.path) {
                        TabView(selection: $selectedTab) {
                            ValuesTabContainer()
                                .environmentObject(router)
                                .tabItem {
                                    Label(appLanguage == "zh" ? "价值观" : "Values", systemImage: "hexagon.fill")
                                }
                                .tag(AppTab.values)

                            MatchResultsView()
                                .environmentObject(router)
                                .tabItem {
                                    Label(appLanguage == "zh" ? "发现" : "Discover", systemImage: "binoculars.fill")
                                }
                                .tag(AppTab.matches)

                            ChatsRootView(selectedTab: $selectedTab)
                                .environmentObject(router)
                                .tabItem {
                                    Label(appLanguage == "zh" ? "对话" : "Chats", systemImage: "bubble.left.and.bubble.right.fill")
                                }
                                .tag(AppTab.chats)

                            ProfileRootView(selectedTab: $selectedTab)
                                .environmentObject(router)
                                .tabItem {
                                    Label(appLanguage == "zh" ? "我的" : "Me", systemImage: "person.crop.circle")
                                }
                                .tag(AppTab.profile)
                        }
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .chat(let match):
                                ChatView(match: match)
                                    .environmentObject(authViewModel)
                                    .environmentObject(router)
                            case .rating(let match):
                                RatingView(match: match)
                                    .environmentObject(authViewModel)
                                    .environmentObject(router)
                            }
                        }
                    }
                }
            } else {
                IntroView()
                    .environmentObject(router)
            }
        }
        .onAppear {
            trackCurrentScreen()
        }
        .onChange(of: authViewModel.isAuthenticated) { _ in
            trackCurrentScreen()
        }
        .onChange(of: authViewModel.isQuestionnaireCompleted) { _ in
            trackCurrentScreen()
        }
        .onChange(of: selectedTab) { _ in
            trackCurrentScreen()
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            TelemetryManager.shared.markTTI()
        })
    }

    private func trackCurrentScreen() {
        let screen = currentScreenName()
        TelemetryManager.shared.markFCP(screen: screen)
        TelemetryManager.shared.markLCP(screen: screen)
        TelemetryManager.shared.track(event: "screen_view", properties: ["screen": screen])
    }

    private func currentScreenName() -> String {
        if !authViewModel.isAuthenticated {
            return "intro"
        }
        if !authViewModel.isQuestionnaireCompleted {
            return "questionnaire"
        }
        switch selectedTab {
        case .values:
            return "values"
        case .matches:
            return "discover"
        case .chats:
            return "chats"
        case .profile:
            return "profile"
        }
    }
}

enum AppRoute: Hashable {
    case chat(Match)
    case rating(Match)
}

enum AppTab: Hashable {
    case values
    case matches
    case chats
    case profile
}

final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}

struct ChatsRootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var router: AppRouter
    @Binding var selectedTab: AppTab
    @StateObject private var matchViewModel = MatchViewModel()
    @AppStorage("app_language") private var appLanguage = "en"

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(appLanguage == "zh" ? "对话" : "Chats")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { matchViewModel.loadMyMatches(force: true) }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(appLanguage == "zh" ? "刷新对话列表" : "Refresh chats")
                    .accessibilityHint(appLanguage == "zh" ? "重新加载对话列表" : "Reload chat list")
                }
                .padding()

                if matchViewModel.matches.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        if matchViewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text(appLanguage == "zh" ? "暂无对话记录" : "No chats yet")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                        Button(action: { selectedTab = .matches }) {
                            Text(appLanguage == "zh" ? "去发现页" : "Go to Discover")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(height: 44)
                                .frame(maxWidth: 180)
                                .background(AppTheme.accent)
                                .cornerRadius(22)
                        }
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(matchViewModel.matches) { match in
                                ZStack(alignment: .topTrailing) {
                                    Button(action: { startChat(match) }) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            HStack(spacing: 8) {
                                                Text(matchDisplayName(for: match, currentUserId: authViewModel.currentUser?.id))
                                                    .font(.system(size: 20, weight: .bold))
                                                    .foregroundColor(.white)
                                                if shouldShowMatchCode(for: match, currentUserId: authViewModel.currentUser?.id) {
                                                    Text(matchDisplayCode(for: match, currentUserId: authViewModel.currentUser?.id))
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundColor(.gray)
                                                }
                                            }

                                            HStack {
                                                Text(appLanguage == "zh" ? "匹配度" : "Match")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.gray)
                                                Spacer()
                                                Text("\(Int(match.similarity_score))%")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundColor(.green)
                                            }

                                            HStack {
                                                Text(getStatusText(match.status))
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.gray)
                                                Spacer()
                                                if match.is_unlocked {
                                                    Text(appLanguage == "zh" ? "已解锁" : "Unlocked")
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.green)
                                                }
                                            }
                                        }
                                        .padding()
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if shouldShowBadge(match) {
                                        Text(badgeText(match))
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Color.red)
                                            .clipShape(Circle())
                                            .padding(8)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .onAppear {
            matchViewModel.loadMyMatches(force: false)
        }
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

    private func startChat(_ match: Match) {
        matchViewModel.startChat(matchId: match.id)
        router.push(.chat(match))
    }

    private func shouldShowBadge(_ match: Match) -> Bool {
        guard let unreadCount = match.unread_count else {
            return false
        }
        return unreadCount > 0
    }

    private func badgeText(_ match: Match) -> String {
        let count = match.unread_count ?? 0
        if count > 99 {
            return "99+"
        }
        return "\(count)"
    }

    private func getStatusText(_ status: String) -> String {
        switch status {
        case "pending": return appLanguage == "zh" ? "等待开始" : "Pending"
        case "chatting": return appLanguage == "zh" ? "聊天中" : "Chatting"
        case "completed": return appLanguage == "zh" ? "已完成" : "Completed"
        case "failed": return appLanguage == "zh" ? "匹配失败" : "Failed"
        default: return ""
        }
    }
}

struct ProfileRootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var selectedTab: AppTab
    @State private var matchCode: String?
    @State private var isLoading = false
    @State private var isProfileLoading = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showEditProfile = false
    @State private var showPrivacy = false
    @State private var showAbout = false
    @State private var showPaywall = false
    @State private var showResetQuestionnaireAlert = false
    @State private var showDeleteImpactAlert = false
    @State private var showDeleteConfirmAlert = false
    @State private var isDeletingAccount = false
    @State private var showAdvancedSettings = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @AppStorage("app_language") private var appLanguage = "en"
    private let matchCodeCacheTTL: TimeInterval = 60 * 60 * 24

    private struct MatchCodeCache: Codable {
        let code: String
        let updatedAt: TimeInterval
    }

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text(appLanguage == "zh" ? "我的" : "Me")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    Button(action: { showEditProfile = true }) {
                        profileCard
                    }
                    .buttonStyle(PlainButtonStyle())

                    settingsSection

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .top) {
            if showToast {
                toastView(message: toastMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showToast)
        .onAppear {
            refreshProfile()
        }
        .onChange(of: authViewModel.currentUser) { _ in
            isProfileLoading = false
            loadMatchCode()
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(isPresented: $showEditProfile, user: authViewModel.currentUser)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showPrivacy) {
            InfoModal(title: appLanguage == "zh" ? "隐私与免责条款" : "Privacy & Disclaimer", content: privacyContent)
        }
        .sheet(isPresented: $showAbout) {
            InfoModal(title: appLanguage == "zh" ? "关于 VitaDuo" : "About VitaDuo", content: aboutContent)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showAdvancedSettings) {
            AdvancedSettingsSheet(
                appLanguage: appLanguage,
                onToast: { message in
                    toastMessage = message
                    showToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        showToast = false
                    }
                }
            )
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(profileTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(appLanguage == "zh" ? "点击编辑" : "Edit")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(10)
            }

            if let user = authViewModel.currentUser {
                HStack(spacing: 12) {
                    profileTag(appLanguage == "zh" ? "\(user.age)岁" : "\(user.age) yrs")
                    profileTag(genderText(user.gender))
                    profileTag(user.city)
                }

                if let school = user.school_career, !school.isEmpty {
                    profileInfoRow(title: appLanguage == "zh" ? "学校/职业" : "School/Job", value: school)
                }

                if let contact = user.contact, !contact.isEmpty {
                    profileInfoRow(title: appLanguage == "zh" ? "联系方式" : "Contact", value: contact)
                }

                HStack {
                    Text(appLanguage == "zh" ? "剩余匹配次数" : "Matches Left")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Spacer()
                    HStack(spacing: 8) {
                        Text("\(user.matches_left)")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Button(action: { showPaywall = true }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 16))
                        }
                    }
                }

                HStack {
                    Text(appLanguage == "zh" ? "匹配码" : "Match Code")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(matchCode ?? "--")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            } else {
                Text(isProfileLoading ? (appLanguage == "zh" ? "资料加载中..." : "Loading profile...") : (appLanguage == "zh" ? "点击登录后完善资料" : "Log in to complete your profile"))
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private var settingsSection: some View {
        VStack(spacing: 12) {
            languageSettingRow
            Button(action: { showResetQuestionnaireAlert = true }) {
                settingsRow(title: appLanguage == "zh" ? "重新填写问卷" : "Retake Questionnaire")
            }
            Button(action: { showPrivacy = true }) {
                settingsRow(title: appLanguage == "zh" ? "隐私与免责条款" : "Privacy & Disclaimer")
            }
            Button(action: { showAbout = true }) {
                settingsRow(title: appLanguage == "zh" ? "关于App" : "About App")
            }
            Button(action: { showAdvancedSettings = true }) {
                settingsRow(title: appLanguage == "zh" ? "高级设置" : "Advanced Settings")
            }
            Button(action: { showDeleteImpactAlert = true }) {
                deleteAccountRow
            }
            .disabled(isDeletingAccount)
        }
        .padding(.horizontal)
        .alert(appLanguage == "zh" ? "重新填写问卷" : "Retake Questionnaire", isPresented: $showResetQuestionnaireAlert) {
            Button(appLanguage == "zh" ? "取消" : "Cancel", role: .cancel) {}
            Button(appLanguage == "zh" ? "确认" : "Confirm", role: .destructive) {
                QuestionnaireViewModel.clearAnswerStatusCache()
                authViewModel.updateQuestionnaireCompleted(false)
            }
        } message: {
            Text(appLanguage == "zh" ? "重新填写会覆盖现有答案，是否继续？" : "Retaking will overwrite existing answers. Continue?")
        }
        .alert(appLanguage == "zh" ? "注销账号前请了解影响" : "Before You Delete Your Account", isPresented: $showDeleteImpactAlert) {
            Button(appLanguage == "zh" ? "取消" : "Cancel", role: .cancel) {}
            Button(appLanguage == "zh" ? "继续注销" : "Continue", role: .destructive) {
                showDeleteConfirmAlert = true
            }
        } message: {
            Text(appLanguage == "zh"
                 ? "注销后将永久删除您的资料、问卷答案、匹配记录与聊天记录，并清空剩余匹配次数与购买记录，且无法恢复。是否继续？"
                 : "Deleting your account will permanently remove your profile, questionnaire answers, matches, chats, remaining match credits, and purchase history. This cannot be undone. Continue?")
        }
        .alert(appLanguage == "zh" ? "请再次确认注销" : "Confirm Account Deletion", isPresented: $showDeleteConfirmAlert) {
            Button(appLanguage == "zh" ? "取消" : "Cancel", role: .cancel) {}
            Button(appLanguage == "zh" ? "确认注销" : "Delete", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text(appLanguage == "zh" ? "此操作不可撤销，将立即删除账号。" : "This action cannot be undone and will delete your account now.")
        }
    }

    private var languageSettingRow: some View {
        HStack {
            Text(appLanguage == "zh" ? "语言" : "Language")
                .font(.system(size: 16))
                .foregroundColor(.white)
            Spacer()
            Picker("", selection: $appLanguage) {
                Text("中文").tag("zh")
                Text("EN").tag("en")
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 140)
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(14)
    }

    private func settingsRow(title: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(14)
    }

    private var deleteAccountRow: some View {
        HStack {
            if isDeletingAccount {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
            Text(appLanguage == "zh" ? "注销账号" : "Delete Account")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "trash")
                .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.red.opacity(0.18))
        .cornerRadius(14)
    }

    private func toastView(message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)
            .padding(.top, 12)
    }

    private func refreshProfile() {
        errorMessage = nil
        isProfileLoading = true
        authViewModel.fetchCurrentUser()
        loadMatchCode()
    }

    private func deleteAccount() {
        errorMessage = nil
        isDeletingAccount = true
        authViewModel.deleteAccount { result in
            isDeletingAccount = false
            if case let .failure(error) = result {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMatchCode() {
        let canUseCache = authViewModel.currentUser != nil
        if canUseCache, let cache = loadMatchCodeCache() {
            matchCode = cache.code
            isLoading = false
            if isMatchCodeCacheFresh(cache) {
                return
            }
        } else {
            isLoading = true
        }
        NetworkManager.shared.getMatchCode()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isLoading = false
                    if case let .failure(error) = completion {
                        errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { response in
                    matchCode = response.code
                    saveMatchCodeCache(response.code)
                }
            )
            .store(in: &cancellables)
    }

    private func genderText(_ gender: String) -> String {
        switch gender {
        case "male": return appLanguage == "zh" ? "男" : "Male"
        case "female": return appLanguage == "zh" ? "女" : "Female"
        case "other": return appLanguage == "zh" ? "其他" : "Other"
        default: return gender
        }
    }

    private var profileTitle: LocalizedStringKey {
        if let user = authViewModel.currentUser {
            return LocalizedStringKey(user.nickname)
        }
        if authViewModel.isAuthenticated {
            return isProfileLoading ? (appLanguage == "zh" ? "加载中..." : "Loading...") : (appLanguage == "zh" ? "登录信息异常" : "Login error")
        }
        return appLanguage == "zh" ? "未登录" : "Not logged in"
    }

    private func profileTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.12))
            .cornerRadius(10)
    }

    private func profileInfoRow(title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.white)
        }
    }

    private var privacyContent: String {
        if appLanguage == "zh" {
            return """
            我们仅收集您主动填写或使用服务过程中产生的必要信息（如昵称、年龄、性别、城市、联系方式、问卷与聊天记录），用于匹配与服务改进。我们不会向第三方出售您的个人信息。为保障平台安全与合规，可能在必要范围内进行风控与内容审核。

            本应用提供的匹配与互动信息仅供参考，结果不构成任何保证。用户在线上或线下的互动需自行判断与承担责任。我们将持续改进安全机制，但不对用户之间的行为或线下后果承担责任。

            您须遵守所在国家或地区的法律法规以及相关平台规则，不得发布或传播违法违规内容。若需更正或删除个人信息，可通过联系方式联系我们。
            """
        }
        return """
        We only collect the information you provide or generate while using the service (such as nickname, age, gender, city, contact details, questionnaire answers, and chat records) to provide matching and improve the service. We do not sell your personal information to third parties. For safety and compliance, we may perform necessary risk control and content review.

        Match and interaction information is for reference only and does not constitute any guarantee. You are responsible for your own judgment and actions in online or offline interactions. We continuously improve safety mechanisms but are not responsible for user behavior or offline outcomes.

        You must comply with applicable laws and platform rules. If you need to correct or delete personal information, please contact us.
        """
    }

    private var aboutContent: String {
        if appLanguage == "zh" {
            return """
            VitaDuo 通过问卷与算法为用户提供更高质量的匹配体验，帮助彼此了解与建立连接。

            联系方式：ab@tpr.wales
            """
        }
        return """
        VitaDuo matches people through questionnaires and algorithms, helping you connect with someone on the same wavelength.

        Contact: ab@tpr.wales
        """
    }

    private func saveMatchCodeCache(_ code: String) {
        guard authViewModel.currentUser != nil else { return }
        let cache = MatchCodeCache(code: code, updatedAt: Date().timeIntervalSince1970)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: matchCodeCacheKey)
        }
    }

    private func loadMatchCodeCache() -> MatchCodeCache? {
        guard let data = UserDefaults.standard.data(forKey: matchCodeCacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MatchCodeCache.self, from: data)
    }

    private func isMatchCodeCacheFresh(_ cache: MatchCodeCache) -> Bool {
        Date().timeIntervalSince1970 - cache.updatedAt < matchCodeCacheTTL
    }

    private var matchCodeCacheKey: String {
        let baseURL = NetworkManager.shared.baseURL
        let sanitized = baseURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "_")
        let userId = authViewModel.currentUser?.id ?? 0
        return "cached_match_code_\(userId)_\(sanitized)"
    }
}

struct AdvancedSettingsSheet: View {
    let appLanguage: String
    let onToast: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showManualMatch = false
    @State private var showAdvancedFilter = false

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Text(appLanguage == "zh" ? "高级设置" : "Advanced Settings")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white.opacity(0.7))
                            .padding(8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)

                VStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showManualMatch = true
                        }
                    }) {
                        advancedRow(title: appLanguage == "zh" ? "手动匹配" : "Manual Match")
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showAdvancedFilter = true
                        }
                    }) {
                        advancedRow(title: appLanguage == "zh" ? "高级匹配" : "Advanced Match")
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
        }
        .sheet(isPresented: $showManualMatch) {
            ManualMatchInputSheet(appLanguage: appLanguage) {
                onToast(appLanguage == "zh" ? "已将对方添加到聊天列表" : "Added to your chat list")
            }
        }
        .sheet(isPresented: $showAdvancedFilter) {
            AdvancedMatchFilterView(appLanguage: appLanguage)
        }
    }

    private func advancedRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(14)
    }
}

struct ManualMatchInputSheet: View {
    let appLanguage: String
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var matchCode = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()
            VStack(spacing: 16) {
                Text(appLanguage == "zh" ? "请输入对方的匹配码" : "Enter Match Code")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    TextField(appLanguage == "zh" ? "6位字母数字组合" : "6-character alphanumeric", text: $matchCode)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .onChange(of: matchCode) { newValue in
                            if newValue.count > 7 {
                                matchCode = String(newValue.prefix(7))
                            }
                        }
                    Text(appLanguage == "zh" ? "格式示例：A7F3C2 或 #A7F3C2" : "Example: A7F3C2 or #A7F3C2")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Text(appLanguage == "zh" ? "取消" : "Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(22)
                    }

                    Button(action: confirmManualMatch) {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        } else {
                            Text(appLanguage == "zh" ? "确认" : "Confirm")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white)
                    .cornerRadius(22)
                    .disabled(isSubmitting)
                }
                .padding(.horizontal)

                Spacer()
            }
        }
    }

    private func confirmManualMatch() {
        errorMessage = nil
        let normalized = matchCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleaned = normalized.hasPrefix("#") ? String(normalized.dropFirst()) : normalized
        let isValid = cleaned.count == 6 && cleaned.allSatisfy { $0.isNumber || ($0 >= "A" && $0 <= "Z") }
        if !isValid {
            errorMessage = appLanguage == "zh" ? "匹配码格式不正确，请输入6位字母数字组合" : "Invalid match code. Please enter a 6-character code."
            return
        }
        isSubmitting = true
        NetworkManager.shared.manualMatchByCode(code: "#\(cleaned)")
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isSubmitting = false
                    if case let .failure(error) = completion {
                        errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { _ in
                    onSuccess()
                    dismiss()
                }
            )
            .store(in: &cancellables)
    }
}

struct AdvancedMatchFilterView: View {
    let appLanguage: String
    @Environment(\.dismiss) private var dismiss
    @State private var minAge: Double = 18
    @State private var maxAge: Double = 60
    @State private var selectedCountry: String = ""
    @State private var selectedOccupation: String = "IT/互联网"
    @State private var showUnavailableAlert = false

    private let countries = ["United States", "Canada", "United Kingdom", "Australia", "Singapore", "Japan", "South Korea", "Germany", "France", "India"]
    private let occupations = ["IT/互联网", "教育/培训", "金融/法律", "医疗/健康", "设计/传媒"]

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()
            VStack(spacing: 16) {
                Text(appLanguage == "zh" ? "高级匹配筛选" : "Advanced Match Filters")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appLanguage == "zh" ? "年龄范围" : "Age Range")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Text("\(Int(minAge)) - \(Int(maxAge))")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Slider(value: Binding(
                            get: { minAge },
                            set: { minAge = min($0, maxAge) }
                        ), in: 18...60, step: 1)
                        Slider(value: Binding(
                            get: { maxAge },
                            set: { maxAge = max($0, minAge) }
                        ), in: 18...60, step: 1)
                    }
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(appLanguage == "zh" ? "国家" : "Country")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Picker(selection: $selectedCountry, label: Text(appLanguage == "zh" ? "请选择国家" : "Select a country")) {
                            Text(appLanguage == "zh" ? "请选择国家" : "Select a country").tag("")
                            ForEach(countries, id: \.self) { country in
                                Text(country).tag(country)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(appLanguage == "zh" ? "相近职业" : "Similar Occupation")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                            ForEach(occupations, id: \.self) { item in
                                Button(action: { selectedOccupation = item }) {
                                    Text(item)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(selectedOccupation == item ? Color.white.opacity(0.3) : Color.white.opacity(0.12))
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(14)
                }
                .padding(.horizontal)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showUnavailableAlert = true
                    }
                }) {
                    Text(appLanguage == "zh" ? "确定" : "Confirm")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white)
                        .cornerRadius(24)
                        .padding(.horizontal)
                }
                .alert(appLanguage == "zh" ? "提示" : "Notice", isPresented: $showUnavailableAlert) {
                    Button(appLanguage == "zh" ? "我知道了" : "Got it", role: .cancel) {
                        dismiss()
                    }
                } message: {
                    Text(appLanguage == "zh" ? "此功能暂未开放，敬请关注" : "This feature is not available yet. Stay tuned.")
                }

                Spacer()
            }
        }
    }
}

struct EditProfileSheet: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Binding var isPresented: Bool
    @AppStorage("app_language") private var appLanguage = "en"

    @State private var nickname: String
    @State private var age: String
    @State private var genderIndex: Int
    @State private var schoolCareer: String
    @State private var city: String
    @State private var contact: String
    @State private var showError = false
    @State private var didSubmit = false

    private let genderValues = ["male", "female", "other"]

    init(isPresented: Binding<Bool>, user: User?) {
        _isPresented = isPresented
        _nickname = State(initialValue: user?.nickname ?? "")
        _age = State(initialValue: user.map { String($0.age) } ?? "")
        let genderValue = user?.gender ?? "male"
        let index = genderValues.firstIndex(of: genderValue) ?? 0
        _genderIndex = State(initialValue: index)
        _schoolCareer = State(initialValue: user?.school_career ?? "")
        _city = State(initialValue: user?.city ?? "")
        _contact = State(initialValue: user?.contact ?? "")
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        Text(appLanguage == "zh" ? "完善资料" : "Complete Profile")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 8)

                        VStack(spacing: 16) {
                            profileField(
                                title: appLanguage == "zh" ? "昵称" : "Nickname",
                                placeholder: appLanguage == "zh" ? "输入昵称" : "Enter nickname",
                                text: $nickname,
                                keyboard: .default
                            )
                            profileField(
                                title: appLanguage == "zh" ? "年龄" : "Age",
                                placeholder: appLanguage == "zh" ? "输入年龄" : "Enter age",
                                text: $age,
                                keyboard: .numberPad
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                Text(appLanguage == "zh" ? "性别" : "Gender")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                Picker("", selection: $genderIndex) {
                                    ForEach(0..<genders.count, id: \.self) { index in
                                        Text(genders[index]).tag(index)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }

                            profileField(
                                title: appLanguage == "zh" ? "学校/职业" : "School/Job",
                                placeholder: appLanguage == "zh" ? "输入学校或职业" : "Enter school or job",
                                text: $schoolCareer,
                                keyboard: .default
                            )
                            profileField(
                                title: appLanguage == "zh" ? "所在城市" : "City",
                                placeholder: appLanguage == "zh" ? "输入城市" : "Enter city",
                                text: $city,
                                keyboard: .default
                            )
                            profileField(
                                title: appLanguage == "zh" ? "联系方式 (手机号/邮箱)" : "Contact (Phone/Email)",
                                placeholder: appLanguage == "zh" ? "输入联系方式" : "Enter contact info",
                                text: $contact,
                                keyboard: .emailAddress
                            )
                        }
                        .padding(.horizontal, 24)

                        Button(action: saveProfile) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 26)
                                    .fill(Color.white)
                                if authViewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    Text(appLanguage == "zh" ? "保存" : "Save")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 26))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .disabled(!isFormValid || authViewModel.isLoading)
                        .opacity(isFormValid ? 1.0 : 0.5)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLanguage == "zh" ? "关闭" : "Close") { isPresented = false }
                        .foregroundColor(.white)
                }
            }
            .alert(appLanguage == "zh" ? "保存失败" : "Save Failed", isPresented: $showError) {
                Button(appLanguage == "zh" ? "确定" : "OK", role: .cancel) {}
            } message: {
                if let message = authViewModel.errorMessage {
                    Text(message)
                }
            }
            .onChange(of: authViewModel.errorMessage) { message in
                if didSubmit, message != nil {
                    showError = true
                }
            }
            .onChange(of: authViewModel.currentUser) { _ in
                if didSubmit && authViewModel.errorMessage == nil {
                    isPresented = false
                }
            }
        }
    }

    private func profileField(title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 14))
                .foregroundColor(.gray)
            TextField(LocalizedStringKey(placeholder), text: text)
                .keyboardType(keyboard)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
        }
    }

    private var isFormValid: Bool {
        !nickname.isEmpty &&
        !age.isEmpty &&
        (Int(age) ?? 0) >= 18 &&
        !city.isEmpty &&
        !contact.isEmpty
    }

    private func saveProfile() {
        guard let ageInt = Int(age) else { return }
        didSubmit = true
        authViewModel.updateProfile(
            nickname: nickname,
            age: ageInt,
            gender: genderValues[genderIndex],
            schoolCareer: schoolCareer.isEmpty ? nil : schoolCareer,
            city: city,
            contact: contact
        )
    }

    private var genders: [String] {
        appLanguage == "zh" ? ["男", "女", "其他"] : ["Male", "Female", "Other"]
    }

}

struct InfoModal: View {
    let title: LocalizedStringKey
    let content: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.bgPrimary.ignoresSafeArea()
                ScrollView {
                    Text(content)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .padding(24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appLanguage == "zh" ? "关闭" : "Close") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
