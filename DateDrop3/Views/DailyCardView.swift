//
//  DailyCardView.swift
//  DateDrop3
//
//  每日价值观思考卡片 — 每天推送一个价值观相关的思考题
//

import SwiftUI

struct DailyCardView: View {
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var card: [String: String] = [:]
    @State private var isLoading = false
    @State private var showReflection = false
    @State private var reflectionText = ""

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.spacingL) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                            .padding(.top, 60)
                    } else if !card.isEmpty {
                        // Date badge
                        if let dateStr = card["date"] {
                            Text(dateStr)
                                .font(AppTheme.captionPill)
                                .foregroundColor(AppTheme.textSecondary)
                                .padding(.top, AppTheme.spacingM)
                        }

                        // Card with breathing pulse behind it
                        ZStack {
                            // BreathingPulse animation behind the card
                            BreathingPulse(color: AppTheme.accent)
                                .frame(width: 260, height: 260)
                                .offset(y: -10)

                            // Main card
                            GlassCard(cornerRadius: AppTheme.radiusXL, padding: AppTheme.spacingL) {
                                VStack(spacing: AppTheme.spacingM) {
                                    // Large dimension icon at top
                                    let dim = card["dimension"] ?? "core_values"
                                    Image(systemName: AppTheme.sectionIcons[dim] ?? "sparkles")
                                        .font(.system(size: 36))
                                        .foregroundColor(AppTheme.accent)
                                        .frame(width: 72, height: 72)
                                        .background(AppTheme.accent.opacity(0.10), in: Circle())

                                    // Dimension label
                                    Text(appLanguage == "zh"
                                         ? (AppTheme.sectionLabelsZh[dim] ?? dim)
                                         : (AppTheme.sectionLabelsEn[dim] ?? dim))
                                        .font(AppTheme.captionPill)
                                        .foregroundColor(AppTheme.accentLight)
                                        .textCase(.uppercase)

                                    // Title
                                    Text(appLanguage == "zh" ? (card["title_zh"] ?? "") : (card["title_en"] ?? ""))
                                        .font(AppTheme.titleCard)
                                        .foregroundColor(AppTheme.textPrimary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, AppTheme.spacingS)

                                    // Question
                                    Text(appLanguage == "zh" ? (card["question_zh"] ?? "") : (card["question_en"] ?? ""))
                                        .font(AppTheme.bodyPrimary)
                                        .foregroundColor(AppTheme.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(6)
                                        .padding(.horizontal, AppTheme.spacingS)

                                    // AccentButton to toggle reflection
                                    AccentButton(
                                        title: appLanguage == "zh"
                                            ? (showReflection ? "收起" : "写下你的想法")
                                            : (showReflection ? "Hide" : "Write your thoughts"),
                                        action: {
                                            withAnimation(.spring(response: 0.4)) {
                                                showReflection.toggle()
                                            }
                                        }
                                    )
                                    .padding(.top, AppTheme.spacingXS)

                                    // Reflection text area
                                    if showReflection {
                                        VStack(spacing: AppTheme.spacingS) {
                                            TextEditor(text: $reflectionText)
                                                .scrollContentBackground(.hidden)
                                                .foregroundColor(AppTheme.textPrimary)
                                                .font(AppTheme.bodyPrimary)
                                                .frame(height: 120)
                                                .padding(AppTheme.spacingS)
                                                .background(AppTheme.bgElevated, in: RoundedRectangle(cornerRadius: AppTheme.radiusS))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: AppTheme.radiusS)
                                                        .stroke(AppTheme.accent.opacity(0.25), lineWidth: 1)
                                                )

                                            if !reflectionText.isEmpty {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 12))
                                                    Text(appLanguage == "zh"
                                                         ? "想法已保存到本地"
                                                         : "Thought saved locally")
                                                        .font(.system(size: 12, design: .rounded))
                                                }
                                                .foregroundColor(AppTheme.success)
                                                .transition(.opacity)
                                            }
                                        }
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }
                            .padding(.horizontal, AppTheme.spacingM)
                        }

                        // Tip
                        Text(appLanguage == "zh"
                             ? "每天一张新的价值观思考卡片 🌟"
                             : "A new values reflection card every day 🌟")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.bottom, AppTheme.spacingL)
                    } else {
                        VStack(spacing: AppTheme.spacingS) {
                            Image(systemName: "card.text")
                                .font(.system(size: 40))
                                .foregroundColor(AppTheme.textSecondary)
                            Text(appLanguage == "zh"
                                 ? "加载今日卡片..."
                                 : "Loading today's card...")
                                .foregroundColor(AppTheme.textSecondary)
                                .font(AppTheme.bodyPrimary)
                                .padding(.top, AppTheme.spacingM)
                        }
                    }
                }
            }
        }
        .onAppear { loadCard() }
    }

    // MARK: - Network

    private func loadCard() {
        isLoading = true
        NetworkManager.shared.fetchDailyCard { result in
            DispatchQueue.main.async {
                isLoading = false
                if case .success(let data) = result {
                    self.card = data
                }
            }
        }
    }
}

#Preview {
    DailyCardView()
}
