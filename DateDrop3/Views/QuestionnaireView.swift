//
//  QuestionnaireView.swift
//  DateDrop3
//
//  问卷页 - 66道价值观题目 (Modern Design)
//

import SwiftUI

struct QuestionnaireView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = QuestionnaireViewModel()
    @AppStorage("app_language") private var appLanguage = "en"

    @State private var currentIndex = 0
    @State private var showMatchResults = false
    @State private var showPaywall = false
    @State private var showSubmitError = false

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Thin progress bar at top
                thinProgressBar

                // Content area
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                        .scaleEffect(1.2)
                    Spacer()
                } else if let err = viewModel.loadErrorMessage {
                    modernErrorView(message: err)
                } else if viewModel.questions.isEmpty {
                    modernEmptyView
                } else {
                    swipeableQuestionArea
                }
            }
        }
        .navigationDestination(isPresented: $showMatchResults) {
            MatchResultsView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(authViewModel)
        }
        .onAppear {
            loadQuestions()
        }
        .onChange(of: appLanguage) { _ in
            loadQuestions()
        }
        .onChange(of: viewModel.questions.count) { _ in
            if currentIndex >= viewModel.questions.count {
                currentIndex = max(viewModel.questions.count - 1, 0)
            }
        }
        .onChange(of: viewModel.submitSuccess) { success in
            if success {
                authViewModel.updateQuestionnaireCompleted(true)
                authViewModel.fetchCurrentUser()
                // Navigation will be handled by ContentView or local destination
                // But since we updated authViewModel, ContentView might rebuild.
                // Let's rely on ContentView rebuild for cleaner flow.
            }
        }
        .onChange(of: viewModel.submitErrorMessage) { message in
            showSubmitError = message != nil
        }
        .alert(appLanguage == "zh" ? "提交失败" : "Submit Failed", isPresented: $showSubmitError) {
            Button(appLanguage == "zh" ? "确定" : "OK", role: .cancel) {
                viewModel.submitErrorMessage = nil
            }
        } message: {
            if let message = viewModel.submitErrorMessage {
                Text(message)
            }
        }
        .overlay {
            if viewModel.isSubmitting {
                submittingOverlay
            }
        }
    }

    // MARK: - Thin Progress Bar

    private var thinProgressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text(appLanguage == "zh"
                     ? "第 \(min(currentIndex + 1, totalQuestions)) 题 / 共 \(totalQuestions) 题"
                     : "Question \(min(currentIndex + 1, totalQuestions)) / \(totalQuestions)")
                    .font(AppTheme.captionPill)
                    .foregroundColor(AppTheme.textSecondary)

                Spacer()

                let progress = viewModel.getProgress()
                Text("\(progress.answered) / \(progress.total)")
                    .font(AppTheme.captionPill)
                    .foregroundColor(AppTheme.textPrimary)
            }
            .padding(.horizontal, AppTheme.spacingM)
            .padding(.top, AppTheme.spacingM)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppTheme.bgElevated)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppTheme.accent)
                        .frame(width: max(geo.size.width * progressRatio, 0), height: 3)
                        .animation(.easeInOut(duration: 0.3), value: currentIndex)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, AppTheme.spacingM)
        }
    }

    // MARK: - Swipeable Question Area

    private var swipeableQuestionArea: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(viewModel.questions.enumerated()), id: \.element.id) { index, question in
                FullScreenQuestionCard(
                    question: question,
                    sectionName: viewModel.getSectionName(question.section ?? ""),
                    selectedAnswer: viewModel.getAnswer(questionId: question.id),
                    appLanguage: appLanguage,
                    onAnswer: { answer in
                        handleAnswer(questionId: question.id, answer: answer)
                    },
                    onPrevious: { previousQuestion() },
                    canGoBack: currentIndex > 0
                )
                .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }

    // MARK: - Error View

    private func modernErrorView(message: String) -> some View {
        VStack(spacing: AppTheme.spacingM) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.accent.opacity(0.6))

            Text(appLanguage == "zh" ? "加载题目失败" : "Failed to load questions")
                .font(AppTheme.titleCard)
                .foregroundColor(AppTheme.textPrimary)

            Text(message)
                .font(AppTheme.bodyPrimary)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingL)

            AccentButton(
                title: appLanguage == "zh" ? "重试" : "Retry",
                action: loadQuestions
            )
            .frame(maxWidth: 200)
            .padding(.top, AppTheme.spacingS)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var modernEmptyView: some View {
        VStack(spacing: AppTheme.spacingM) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.accent.opacity(0.6))

            Text(appLanguage == "zh" ? "暂无题目" : "No questions available")
                .font(AppTheme.titleCard)
                .foregroundColor(AppTheme.textPrimary)

            AccentButton(
                title: appLanguage == "zh" ? "重新加载" : "Reload",
                action: loadQuestions
            )
            .frame(maxWidth: 180)

            Spacer()
        }
    }

    // MARK: - Submitting Overlay

    private var submittingOverlay: some View {
        ZStack {
            AppTheme.bgPrimary.opacity(0.75)
                .ignoresSafeArea()
                .transition(.opacity)

            GlassCard(cornerRadius: AppTheme.radiusL, padding: AppTheme.spacingXL) {
                VStack(spacing: AppTheme.spacingM) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                        .scaleEffect(1.5)

                    Text(appLanguage == "zh" ? "正在提交..." : "Submitting...")
                        .font(AppTheme.bodyPrimary)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isSubmitting)
    }

    // MARK: - Computed Properties

    private var totalQuestions: Int {
        max(viewModel.questions.count, 66)
    }

    private var progressRatio: CGFloat {
        guard totalQuestions > 0 else { return 0 }
        return CGFloat(min(currentIndex + 1, totalQuestions)) / CGFloat(totalQuestions)
    }

    // MARK: - Actions

    private func previousQuestion() {
        if currentIndex > 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentIndex -= 1
            }
        }
    }

    private func handleAnswer(questionId: Int, answer: Int) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        viewModel.setAnswer(questionId: questionId, answer: answer)

        if currentIndex < viewModel.questions.count - 1 {
            withAnimation(.easeInOut(duration: 0.35)) {
                currentIndex += 1
            }
        } else {
            viewModel.submitAnswers()
        }
    }

    private func loadQuestions() {
        viewModel.loadQuestions(lang: appLanguage)
    }
}

// MARK: - Full-Screen Question Card

struct FullScreenQuestionCard: View {
    let question: Question
    let sectionName: String
    let selectedAnswer: Int?
    let appLanguage: String
    let onAnswer: (Int) -> Void
    let onPrevious: () -> Void
    let canGoBack: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Section pill + sensitive tag
            VStack(spacing: AppTheme.spacingS) {
                if !sectionName.isEmpty {
                    PillTag(text: sectionName, color: AppTheme.accent)
                }

                if question.isSensitive {
                    PillTag(
                        text: appLanguage == "zh" ? "敏感问题" : "Sensitive",
                        color: AppTheme.warning
                    )
                }
            }
            .padding(.bottom, AppTheme.spacingM)

            // Question text in glass card
            GlassCard(cornerRadius: AppTheme.radiusL, padding: AppTheme.spacingL) {
                Text(question.text)
                    .font(AppTheme.titleCard)
                    .foregroundColor(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppTheme.spacingM)

            Spacer()
                .frame(height: AppTheme.spacingXL)

            // Answer scale
            if question.isLikert {
                likertScaleRow
            } else {
                choice5ScaleRow
            }

            Spacer()
                .frame(height: AppTheme.spacingL)

            // Back button
            if canGoBack {
                Button(action: onPrevious) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text(appLanguage == "zh" ? "上一题" : "Previous")
                            .font(AppTheme.captionPill)
                    }
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(AppTheme.bgElevated)
                    )
                }
                .padding(.bottom, AppTheme.spacingS)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 7-Point Likert Scale (rounded buttons in a row)

    private var likertScaleRow: some View {
        VStack(spacing: AppTheme.spacingS) {
            // Endpoint labels
            HStack {
                Text(appLanguage == "zh" ? "强烈反对" : "Strongly Disagree")
                    .font(AppTheme.captionPill)
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text(appLanguage == "zh" ? "强烈同意" : "Strongly Agree")
                    .font(AppTheme.captionPill)
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.horizontal, AppTheme.spacingXS)

            // 7 circular rounded buttons
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { option in
                    let isSelected = selectedAnswer == option
                    Button {
                        onAnswer(option)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isSelected ? AppTheme.accent : AppTheme.bgElevated)
                                .frame(width: 42, height: 42)

                            if isSelected {
                                Circle()
                                    .strokeBorder(AppTheme.accentLight, lineWidth: 2.5)
                                    .frame(width: 42, height: 42)
                            }

                            Text("\(option)")
                                .font(AppTheme.monoNumber)
                                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
        .padding(.horizontal, AppTheme.spacingM)
    }

    // MARK: - 5-Point Choice Scale (rounded buttons in a row)

    private var choice5ScaleRow: some View {
        VStack(spacing: AppTheme.spacingM) {
            HStack(spacing: 6) {
                ForEach(Array(choiceLabels.enumerated()), id: \.offset) { index, label in
                    let option = index + 1
                    let isSelected = selectedAnswer == option
                    Button {
                        onAnswer(option)
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                RoundedRectangle(cornerRadius: AppTheme.radiusS)
                                    .fill(isSelected ? AppTheme.accent : AppTheme.bgElevated)
                                    .frame(height: 44)

                                if isSelected {
                                    RoundedRectangle(cornerRadius: AppTheme.radiusS)
                                        .strokeBorder(AppTheme.accentLight, lineWidth: 2.5)
                                        .frame(height: 44)
                                }

                                Text("\(option)")
                                    .font(AppTheme.monoNumber)
                                    .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                            }

                            Text(label)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
        .padding(.horizontal, AppTheme.spacingM)
    }

    private var choiceLabels: [String] {
        if appLanguage == "zh" {
            return ["坚决不要", "可能不要", "不确定", "可能要", "一定要"]
        }
        return ["Def No", "Prob No", "Unsure", "Prob Yes", "Def Yes"]
    }
}

// MARK: - Scale Button Style (press animation)

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    NavigationView {
        QuestionnaireView()
            .environmentObject(AuthViewModel())
    }
}
