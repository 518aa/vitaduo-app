//
//  ValuesInsightsView.swift
//  DateDrop3
//
//  价值观洞察页 — 展示各维度的百分位排名和趋势分析
//

import SwiftUI

struct ValuesInsightsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var insights: [String: Any] = [:]
    @State private var isLoading = false

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.spacingL) {
                    // Header
                    VStack(spacing: AppTheme.spacingXS) {
                        Text(appLanguage == "zh" ? "价值观洞察" : "Values Insights")
                            .font(AppTheme.displayMedium)
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(.top, AppTheme.spacingM)

                        if let totalUsers = insights["total_users"] as? Int, totalUsers > 0 {
                            Text(appLanguage == "zh"
                                 ? "基于 \(totalUsers) 位用户的对比分析"
                                 : "Compared with \(totalUsers) users")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                            .padding(.top, 40)
                    } else if let percentiles = insights["percentiles"] as? [String: [String: Any]], !percentiles.isEmpty {
                        let sortedKeys = percentiles.keys.sorted()

                        // Overall ranking card at top with heroGradient
                        overallRankingCard(percentiles: percentiles)
                            .padding(.horizontal, AppTheme.spacingM)

                        // Dimension cards
                        ForEach(sortedKeys, id: \.self) { key in
                            if let data = percentiles[key],
                               let score = data["score"] as? Double,
                               let pct = data["percentile"] as? Int {
                                dimensionCard(
                                    key: key,
                                    score: score,
                                    percentile: pct
                                )
                                .padding(.horizontal, AppTheme.spacingM)
                            }
                        }

                        Spacer(minLength: AppTheme.spacingXL)
                    } else {
                        VStack(spacing: AppTheme.spacingS) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 40))
                                .foregroundColor(AppTheme.textSecondary)
                            Text(appLanguage == "zh"
                                 ? "完成问卷后查看你的价值观洞察"
                                 : "Complete the questionnaire to see insights")
                                .foregroundColor(AppTheme.textSecondary)
                                .font(AppTheme.bodyPrimary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppTheme.spacingL)
                                .padding(.top, AppTheme.spacingM)
                        }
                    }
                }
            }
        }
        .onAppear { loadInsights() }
    }

    // MARK: - Overall Ranking Card

    private func overallRankingCard(percentiles: [String: [String: Any]]) -> some View {
        let avgPct = percentiles.values.compactMap { $0["percentile"] as? Int }.reduce(0, +)
        let count = percentiles.count
        let avg = count > 0 ? avgPct / count : 0

        return VStack(spacing: AppTheme.spacingM) {
            Text(appLanguage == "zh" ? "综合排名" : "Overall Ranking")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))

            Text("\(avg)%")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text(appLanguage == "zh"
                 ? "你的价值观独特度超过了 \(avg)% 的用户"
                 : "Your values uniqueness exceeds \(avg)% of users")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(AppTheme.spacingL)
        .frame(maxWidth: .infinity)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.radiusL))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusL)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Dimension Card

    private func dimensionCard(key: String, score: Double, percentile: Int) -> some View {
        let label = appLanguage == "zh" ? (AppTheme.sectionLabelsZh[key] ?? key) : (AppTheme.sectionLabelsEn[key] ?? key)
        let icon = AppTheme.sectionIcons[key] ?? "circle.fill"

        return GlassCard(cornerRadius: AppTheme.radiusL, padding: AppTheme.spacingM) {
            HStack(spacing: AppTheme.spacingM) {
                // Icon circle
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.accent.opacity(0.12), in: Circle())

                // Content
                VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                    HStack {
                        Text(label)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)

                        Spacer()

                        // Percentile ranking — mono number
                        Text("\(percentile)%")
                            .font(AppTheme.monoNumber)
                            .foregroundColor(AppTheme.accent)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppTheme.textPrimary.opacity(0.06))
                                .frame(height: 5)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.accent, AppTheme.accentLight],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geo.size.width * CGFloat(percentile) / 100,
                                    height: 5
                                )
                        }
                    }
                    .frame(height: 5)

                    // Score + ranking description
                    HStack {
                        Text(String(format: "%.1f / 7", score))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Text(appLanguage == "zh"
                             ? "超过 \(percentile)% 的用户"
                             : "Top \(100 - percentile)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.accentLight)
                    }
                }
            }
        }
    }

    // MARK: - Network

    private func loadInsights() {
        isLoading = true
        NetworkManager.shared.fetchValuesInsights { result in
            DispatchQueue.main.async {
                isLoading = false
                if case .success(let data) = result {
                    self.insights = data
                }
            }
        }
    }
}

#Preview {
    ValuesInsightsView()
        .environmentObject(AuthViewModel())
}
