//
//  ValuesRadarView.swift
//  DateDrop3
//
//  价值观雷达图 — 展示用户6个维度的问卷结果可视化
//

import SwiftUI

// MARK: - Data Model

struct ValuesProfile: Codable {
    let sections: [String: Double]  // section name -> average score (1-7)
    let totalQuestions: Int
    let completedAt: String?

    var dimensionNames: [String] {
        Array(sections.keys)
    }

    var dimensionScores: [Double] {
        Array(sections.values)
    }
}

// MARK: - Radar Chart Shape

struct RadarChartShape: Shape {
    let values: [Double]
    let maxValue: Double

    func path(in rect: CGRect) -> Path {
        guard values.count >= 3 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.85
        let angleStep = .pi * 2 / Double(values.count)
        let startAngle = -.pi / 2  // start from top

        var path = Path()
        for (i, value) in values.enumerated() {
            let angle = startAngle + angleStep * Double(i)
            let r = radius * (value / maxValue)
            let point = CGPoint(
                x: center.x + r * cos(angle),
                y: center.y + r * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Radar Grid Shape

struct RadarGridShape: Shape {
    let count: Int
    let rings: Int

    func path(in rect: CGRect) -> Path {
        guard count >= 3 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * 0.85
        let angleStep = .pi * 2 / Double(count)
        let startAngle = -.pi / 2

        var path = Path()

        // Draw concentric rings
        for ring in 1...rings {
            let r = radius * Double(ring) / Double(rings)
            for i in 0..<count {
                let angle = startAngle + angleStep * Double(i)
                let point = CGPoint(
                    x: center.x + r * cos(angle),
                    y: center.y + r * sin(angle)
                )
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }

        // Draw axis lines
        for i in 0..<count {
            let angle = startAngle + angleStep * Double(i)
            let edgePoint = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            path.move(to: center)
            path.addLine(to: edgePoint)
        }

        return path
    }
}

// MARK: - Radar Chart View

struct RadarChartView: View {
    let values: [Double]
    let labels: [String]
    let icons: [String]
    let maxValue: Double

    private let ringCount = 4

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                // Grid
                RadarGridShape(count: labels.count, rings: ringCount)
                    .stroke(AppTheme.textPrimary.opacity(0.08), lineWidth: 1)

                // Data fill — indigo->lavender gradient
                RadarChartShape(values: values, maxValue: maxValue)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.accent.opacity(0.40),
                                AppTheme.accentLight.opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Data outline
                RadarChartShape(values: values, maxValue: maxValue)
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accentLight],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2.5
                    )

                // Data points
                ForEach(0..<values.count, id: \.self) { i in
                    let angle = -.pi / 2 + (.pi * 2 / Double(values.count)) * Double(i)
                    let r = (size / 2 * 0.85) * (values[i] / maxValue)
                    let cx = size / 2 + r * cos(angle)
                    let cy = size / 2 + r * sin(angle)

                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: AppTheme.accent.opacity(0.5), radius: 4)
                        .position(x: cx, y: cy)
                }

                // Labels with icons
                ForEach(0..<labels.count, id: \.self) { i in
                    let angle = -.pi / 2 + (.pi * 2 / Double(labels.count)) * Double(i)
                    let labelR = size / 2 * 0.85 + 32
                    let lx = size / 2 + labelR * cos(angle)
                    let ly = size / 2 + labelR * sin(angle)

                    VStack(spacing: 2) {
                        Image(systemName: icons[i])
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.accentLight)
                        Text(labels[i])
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary.opacity(0.75))
                    }
                    .position(x: lx, y: ly)
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// MARK: - Full Values Profile View

struct ValuesProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var profile: ValuesProfile?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: AppTheme.spacingL) {
                    // Header
                    VStack(spacing: AppTheme.spacingXS) {
                        Text(appLanguage == "zh" ? "你的价值观雷达" : "Your Values Radar")
                            .font(AppTheme.displayMedium)
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(.top, AppTheme.spacingM)

                        Text(appLanguage == "zh" ? "基于66题问卷的科学分析" : "Based on 66-question scientific assessment")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    if let profile = profile {
                        // Radar chart wrapped in GlassCard
                        let sortedSections = profile.sections.sorted { $0.key < $1.key }
                        let labels = sortedSections.map { AppTheme.sectionLabelsEn[$0.key] ?? $0.key }
                        let icons = sortedSections.map { AppTheme.sectionIcons[$0.key] ?? "circle.fill" }
                        let scores = sortedSections.map { $0.value }

                        GlassCard(cornerRadius: AppTheme.radiusL, padding: AppTheme.spacingL) {
                            RadarChartView(
                                values: scores,
                                labels: appLanguage == "zh"
                                    ? sortedSections.map { AppTheme.sectionLabelsZh[$0.key] ?? $0.key }
                                    : labels,
                                icons: icons,
                                maxValue: 7.0
                            )
                            .frame(height: 280)
                        }
                        .padding(.horizontal, AppTheme.spacingM)

                        // Score breakdown bars
                        GlassCard(cornerRadius: AppTheme.radiusL, padding: AppTheme.spacingM) {
                            VStack(spacing: AppTheme.spacingM) {
                                ForEach(sortedSections, id: \.key) { key, score in
                                    scoreBar(
                                        icon: AppTheme.sectionIcons[key] ?? "circle.fill",
                                        label: appLanguage == "zh"
                                            ? (AppTheme.sectionLabelsZh[key] ?? key)
                                            : (AppTheme.sectionLabelsEn[key] ?? key),
                                        score: score,
                                        maxScore: 7.0
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.spacingM)

                        // Insight card
                        insightCard(profile: profile)
                            .padding(.horizontal, AppTheme.spacingM)
                            .padding(.bottom, AppTheme.spacingXL)

                    } else if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                            .padding(.top, 60)
                    } else if let error = errorMessage {
                        VStack(spacing: AppTheme.spacingM) {
                            Text(error)
                                .foregroundColor(.red)
                                .font(AppTheme.bodyPrimary)
                                .padding()
                            AccentButton(
                                title: appLanguage == "zh" ? "重试" : "Retry",
                                action: { loadProfile() }
                            )
                            .padding(.horizontal, AppTheme.spacingL)
                        }
                    } else {
                        // No data yet
                        VStack(spacing: AppTheme.spacingS) {
                            Image(systemName: "chart.radar")
                                .font(.system(size: 40))
                                .foregroundColor(AppTheme.textSecondary)
                            Text(appLanguage == "zh" ? "完成问卷后查看你的价值观雷达" : "Complete the questionnaire to see your values radar")
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
        .onAppear {
            loadProfile()
        }
    }

    // MARK: - Score Bar

    private func scoreBar(icon: String, label: String, score: Double, maxScore: Double) -> some View {
        VStack(spacing: AppTheme.spacingS) {
            HStack(spacing: AppTheme.spacingS) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                Text(String(format: "%.1f", score))
                    .font(AppTheme.monoNumber)
                    .foregroundColor(AppTheme.accent)

                Text("/ \(Int(maxScore))")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary)
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
                            width: geo.size.width * CGFloat(score / maxScore),
                            height: 5
                        )
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: - Insight Card

    private func insightCard(profile: ValuesProfile) -> some View {
        let sorted = profile.sections.sorted { $0.value > $1.value }
        let topSection = sorted.first
        let topLabel = topSection.map { appLanguage == "zh" ? (AppTheme.sectionLabelsZh[$0.key] ?? $0.key) : (AppTheme.sectionLabelsEn[$0.key] ?? $0.key) } ?? ""

        return GlassCard(cornerRadius: AppTheme.radiusL, padding: AppTheme.spacingM) {
            VStack(alignment: .leading, spacing: AppTheme.spacingS) {
                Label(
                    appLanguage == "zh" ? "洞察" : "Insight",
                    systemImage: "lightbulb.fill"
                )
                .font(AppTheme.titleCard)
                .foregroundColor(AppTheme.textPrimary)

                if let top = topSection {
                    Text(appLanguage == "zh"
                         ? "你在「\(topLabel)」维度得分最高 (\(String(format: "%.1f", top.value))/7)，这反映了你在该领域的强烈倾向。"
                         : "Your highest dimension is \"\(topLabel)\" (\(String(format: "%.1f", top.value))/7), reflecting a strong orientation in this area.")
                        .font(AppTheme.bodyPrimary)
                        .foregroundColor(AppTheme.textSecondary)
                        .lineSpacing(4)
                }

                Divider()
                    .background(AppTheme.textPrimary.opacity(0.08))

                let avg = profile.sections.values.reduce(0, +) / Double(profile.sections.count)
                HStack {
                    Text(appLanguage == "zh" ? "综合均值" : "Overall average")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f", avg))
                        .font(AppTheme.monoNumber)
                        .foregroundColor(AppTheme.accent)
                    Text("/ 7")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
    }

    // MARK: - Network

    private func loadProfile() {
        guard let userId = authViewModel.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil

        NetworkManager.shared.fetchValuesProfile(userId: userId) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let profile):
                    self.profile = profile
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    ValuesProfileView()
        .environmentObject(AuthViewModel())
}
