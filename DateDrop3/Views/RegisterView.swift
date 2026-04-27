//
//  RegisterView.swift
//  DateDrop3
//
//  现代卡片式注册 — 玻璃态表单
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("app_language") private var appLanguage = "en"

    @State private var nickname = ""
    @State private var age = ""
    @State private var genderIndex = 0
    @State private var schoolCareer = ""
    @State private var city = ""
    @State private var contact = ""

    @State private var showQuestionnaire = false
    @State private var showError = false
    @State private var appeared = false

    private let genderValues = ["male", "female", "other"]

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            // Ambient gradient
            Circle()
                .fill(AppTheme.accent.opacity(0.06))
                .frame(width: 350, height: 350)
                .blur(radius: 80)
                .offset(x: 100, y: -200)

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.spacingL) {
                    Spacer().frame(height: 20)

                    // Header
                    VStack(spacing: 8) {
                        Text(appLanguage == "zh" ? "创建你的身份" : "Create Your Identity")
                            .font(AppTheme.displayMedium)
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(appLanguage == "zh"
                             ? "让我们开始了解你"
                             : "Let's get to know you")
                            .font(AppTheme.bodyPrimary)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                    // Form card
                    GlassCard(padding: AppTheme.spacingL) {
                        VStack(spacing: AppTheme.spacingL) {
                            formField(
                                label: appLanguage == "zh" ? "昵称" : "Nickname",
                                placeholder: appLanguage == "zh" ? "你希望被叫什么？" : "What should we call you?",
                                text: $nickname,
                                required: true
                            )

                            formField(
                                label: appLanguage == "zh" ? "年龄" : "Age",
                                placeholder: appLanguage == "zh" ? "输入年龄" : "Enter your age",
                                text: $age,
                                required: true,
                                keyboardType: .numberPad
                            )

                            // Gender picker
                            VStack(alignment: .leading, spacing: 8) {
                                requiredLabel(appLanguage == "zh" ? "性别" : "Gender")
                                HStack(spacing: 8) {
                                    ForEach(0..<genders.count, id: \.self) { i in
                                        let isSelected = genderIndex == i
                                        Text(genders[i])
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(isSelected ? .white : AppTheme.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 42)
                                            .background(isSelected ? AppTheme.accent : AppTheme.bgElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .onTapGesture { withAnimation(.spring(response: 0.3)) { genderIndex = i } }
                                    }
                                }
                            }

                            Divider().overlay(Color.white.opacity(0.08))

                            Text(appLanguage == "zh" ? "以下信息选填" : "Optional fields below")
                                .font(AppTheme.captionPill)
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            formField(
                                label: appLanguage == "zh" ? "学校/职业" : "School / Job",
                                placeholder: appLanguage == "zh" ? "输入学校或职业" : "Enter school or job",
                                text: $schoolCareer
                            )

                            formField(
                                label: appLanguage == "zh" ? "所在城市" : "City",
                                placeholder: appLanguage == "zh" ? "你住在哪个城市？" : "Which city do you live in?",
                                text: $city
                            )

                            formField(
                                label: appLanguage == "zh" ? "联系方式" : "Contact",
                                placeholder: appLanguage == "zh" ? "手机号或邮箱" : "Phone or email",
                                text: $contact,
                                keyboardType: .emailAddress
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingM)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)

                    // Submit
                    AccentButton(title: appLanguage == "zh" ? "下一步" : "Continue") {
                        register()
                    }
                    .padding(.horizontal, AppTheme.spacingM)
                    .opacity(isFormValid ? 1 : 0.4)
                    .disabled(!isFormValid || authViewModel.isLoading)
                    .overlay {
                        if authViewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                    }

                    Spacer().frame(height: 40)
                }
            }
        }
        .navigationBarHidden(true)
        .alert(appLanguage == "zh" ? "注册失败" : "Registration Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = authViewModel.errorMessage { Text(error) }
        }
        .onChange(of: authViewModel.isAuthenticated) { _, value in
            if value { showQuestionnaire = true }
        }
        .onChange(of: authViewModel.errorMessage) { _, value in
            if value != nil { showError = true }
        }
        .navigationDestination(isPresented: $showQuestionnaire) {
            QuestionnaireView().environmentObject(authViewModel)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6).delay(0.1)) { appeared = true }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func formField(label: String, placeholder: String, text: Binding<String>, required: Bool = false, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if required {
                requiredLabel(label)
            } else {
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            TextField(placeholder, text: text)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .keyboardType(keyboardType)
                .autocapitalization(keyboardType == .emailAddress ? .none : .sentences)
                .padding(14)
                .background(AppTheme.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusS))
        }
    }

    @ViewBuilder
    private func requiredLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
            Image(systemName: "asterisk")
                .font(.system(size: 7))
                .foregroundStyle(Color.red.opacity(0.7))
        }
    }

    private var isFormValid: Bool {
        !nickname.isEmpty && !age.isEmpty && (Int(age) ?? 0) >= 18
    }

    private func register() {
        guard let ageInt = Int(age) else { return }
        authViewModel.register(
            nickname: nickname, age: ageInt, gender: genderValues[genderIndex],
            schoolCareer: schoolCareer.isEmpty ? nil : schoolCareer,
            city: city.isEmpty ? nil : city,
            contact: contact.isEmpty ? nil : contact
        )
    }

    private var genders: [String] {
        appLanguage == "zh" ? ["男", "女", "其他"] : ["Male", "Female", "Other"]
    }
}

#Preview {
    NavigationView { RegisterView().environmentObject(AuthViewModel()) }
}
