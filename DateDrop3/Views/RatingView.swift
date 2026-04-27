//
//  RatingView.swift
//  DateDrop3
//
//  评分页 - 为对方评分
//

import SwiftUI
import Combine

struct RatingView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var router: AppRouter
    @AppStorage("app_language") private var appLanguage = "en"

    let match: Match

    @State private var selectedScore: Int?
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var showUnlock = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var canUnlock = false

    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 30) {
                HStack {
                    Button(action: { router.pop() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text(appLanguage == "zh" ? "返回" : "Back")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)

                // 标题
                Text(appLanguage == "zh" ? "为对方评分" : "Rate Your Match")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text(appLanguage == "zh" ? "根据聊天体验,为对方打分 (1-5星)" : "Rate based on your chat (1–5 stars)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                // 星级评分
                starRating

                // 评分说明
                if let score = selectedScore {
                    Text(getScoreDescription(score))
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }

                Spacer()

                // 提交按钮
                Button(action: submitRating) {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Text(appLanguage == "zh" ? "提交评分" : "Submit Rating")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(selectedScore != nil ? Color.white : Color.gray.opacity(0.3))
                .cornerRadius(28)
                .padding(.horizontal, 24)
                .disabled(selectedScore == nil || isSubmitting)

                Spacer()
                    .frame(height: 40)
            }
            .alert(appLanguage == "zh" ? "评分失败" : "Rating Failed", isPresented: $showError) {
                Button(appLanguage == "zh" ? "确定" : "OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showUnlock) {
                UnlockSuccessView(match: match, canUnlock: canUnlock)
                    .environmentObject(authViewModel)
                    .environmentObject(router)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - 星级评分

    private var starRating: some View {
        HStack(spacing: 16) {
            ForEach(1...5, id: \.self) { score in
                Button(action: { selectedScore = score }) {
                    Image(systemName: selectedScore ?? 0 >= score ? "star.fill" : "star")
                        .font(.system(size: 48))
                        .foregroundColor(selectedScore ?? 0 >= score ? .yellow : .gray)
                }
            }
        }
    }

    // MARK: - 评分说明

    private func getScoreDescription(_ score: Int) -> LocalizedStringKey {
        switch score {
        case 1: return appLanguage == "zh" ? "非常不满意" : "Very dissatisfied"
        case 2: return appLanguage == "zh" ? "不满意" : "Dissatisfied"
        case 3: return appLanguage == "zh" ? "一般" : "Neutral"
        case 4: return appLanguage == "zh" ? "满意" : "Satisfied"
        case 5: return appLanguage == "zh" ? "非常满意" : "Very satisfied"
        default: return ""
        }
    }

    // MARK: - 提交评分

    private func submitRating() {
        guard let score = selectedScore else { return }

        isSubmitting = true

        NetworkManager.shared.submitRating(matchId: match.id, score: score, userId: authViewModel.currentUser?.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isSubmitting = false
                    if case let .failure(error) = completion {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                },
                receiveValue: { _ in
                    checkUnlockStatus()
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 检查解锁状态

    private func checkUnlockStatus() {
        NetworkManager.shared.getUnlockStatus(matchId: match.id, userId: authViewModel.currentUser?.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { response in
                    canUnlock = response.can_unlock
                    showUnlock = true
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - 解锁成功视图

struct UnlockSuccessView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"

    let match: Match
    let canUnlock: Bool

    @State private var partnerProfile: User?
    @State private var isLoading = true
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()
                    .frame(height: 60)

                // 成功图标
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)

                Text(appLanguage == "zh" ? "恭喜邀约成功!" : "Invitation Successful!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text(appLanguage == "zh"
                     ? "如果对方对您的评分在4星以上，即可互相解锁真实资料和联系方式，祝你们的关系更进一步！"
                     : "If both of your ratings are 4 stars or higher, you'll unlock real profiles and contact info. Wishing you a great connection!")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if canUnlock && isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if canUnlock, let profile = partnerProfile {
                    VStack(spacing: 16) {
                        ProfileRow(label: appLanguage == "zh" ? "昵称" : "Nickname", value: profile.nickname)
                        ProfileRow(label: appLanguage == "zh" ? "年龄" : "Age", value: appLanguage == "zh" ? "\(profile.age)岁" : "\(profile.age)")
                        ProfileRow(label: appLanguage == "zh" ? "性别" : "Gender", value: getGenderText(profile.gender))
                        ProfileRow(label: appLanguage == "zh" ? "城市" : "City", value: profile.city)
                        if let school = profile.school_career {
                            ProfileRow(label: appLanguage == "zh" ? "学校/职业" : "School/Job", value: school)
                        }
                        ProfileRow(label: appLanguage == "zh" ? "联系方式" : "Contact", value: appLanguage == "zh" ? "未提供" : "Not provided")
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(16)
                }

                Spacer()

                // 关闭按钮
                Button(action: {
                    dismiss()
                    router.popToRoot()
                }) {
                    Text(appLanguage == "zh" ? "关闭" : "Close")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.white)
                .cornerRadius(28)
                .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 40)
            }
        }
        .onAppear {
            if canUnlock {
                loadPartnerProfile()
            } else {
                isLoading = false
            }
        }
    }

    // MARK: - 加载对方资料

    private func loadPartnerProfile() {
        NetworkManager.shared.getPartnerProfile(matchId: match.id, userId: authViewModel.currentUser?.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in
                    isLoading = false
                },
                receiveValue: { response in
                    partnerProfile = response.data
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - 辅助方法

    private func getGenderText(_ gender: String) -> String {
        switch gender {
        case "male": return appLanguage == "zh" ? "男" : "Male"
        case "female": return appLanguage == "zh" ? "女" : "Female"
        case "other": return appLanguage == "zh" ? "其他" : "Other"
        default: return gender
        }
    }
}

// MARK: - 资料行

struct ProfileRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.system(size: 16))
                .foregroundColor(.white)

            Spacer()
        }
    }
}

#Preview {
    NavigationView {
        RatingView(match: Match(
            id: 1,
            user1_id: 1,
            user2_id: 2,
            similarity_score: 0.92,
            status: "chatting",
            is_unlocked: false,
            chat_message_count: 20,
            created_at: nil,
            last_message_at: nil,
            last_message_sender_id: nil,
            unread_count: nil,
            ai_intro: nil,
            partner_nickname: "Alex"
        ))
        .environmentObject(AuthViewModel())
        .environmentObject(AppRouter())
    }
}
