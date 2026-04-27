//
//  ShareableProfileCard.swift
//  DateDrop3
//
//  可分享的价值观Profile卡片 — 生成图片用于社交媒体分享
//

import SwiftUI

struct ShareableProfileCard: View {
    @AppStorage("app_language") private var appLanguage = "en"
    let profile: ValuesProfile
    let nickname: String

    private let sectionLabelsZh: [String: String] = [
        "core_values": "核心价值观", "lifestyle": "生活方式",
        "political": "社会观点", "relationship": "关系期望",
        "personality": "人格特质", "communication": "沟通风格"
    ]
    private let sectionLabelsEn: [String: String] = [
        "core_values": "Core Values", "lifestyle": "Lifestyle",
        "political": "Social Views", "relationship": "Relationships",
        "personality": "Personality", "communication": "Communication"
    ]

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.14, blue: 0.28),
                    Color(red: 0.10, green: 0.22, blue: 0.38),
                    Color(red: 0.08, green: 0.18, blue: 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 20) {
                // App branding
                HStack {
                    Image(systemName: "hexagon.fill")
                        .foregroundColor(AppTheme.accent)
                        .font(.system(size: 16))
                    Text("VitaDuo")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.accent)
                    Spacer()
                    Text(appLanguage == "zh" ? "价值观探索" : "Values Discovery")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 24)

                // Radar chart
                let sortedSections = profile.sections.sorted { $0.key < $1.key }
                let labels = sortedSections.map { appLanguage == "zh" ? (sectionLabelsZh[$0.key] ?? $0.key) : (sectionLabelsEn[$0.key] ?? $0.key) }
                let scores = sortedSections.map { $0.value }

                RadarChartView(values: scores, labels: labels, maxValue: 7.0)
                    .frame(width: 220, height: 220)

                // Score bars
                VStack(spacing: 8) {
                    ForEach(sortedSections, id: \.key) { key, score in
                        HStack {
                            Text(appLanguage == "zh" ? (sectionLabelsZh[key] ?? key) : (sectionLabelsEn[key] ?? key))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 70, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.white.opacity(0.1)).cornerRadius(3)
                                    Rectangle()
                                        .fill(AppTheme.accent)
                                        .frame(width: geo.size.width * CGFloat(score / 7.0))
                                        .cornerRadius(3)
                                }
                            }
                            .frame(height: 6)
                            Text(String(format: "%.1f", score))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppTheme.accent)
                                .frame(width: 30)
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Tagline
                Text(appLanguage == "zh"
                     ? "\(nickname) 的价值观宇宙"
                     : "\(nickname)'s Values Universe")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text("vitaduo.app")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 24)
        }
        .frame(width: 320, height: 520)
        .cornerRadius(24)
    }
}

// MARK: - Share Wrapper View

struct ShareProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var profile: ValuesProfile?
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 24) {
                Text(appLanguage == "zh" ? "分享你的价值观" : "Share Your Values")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 16)

                if let profile = profile {
                    ShareableProfileCard(
                        profile: profile,
                        nickname: authViewModel.currentUser?.nickname ?? "Explorer"
                    )
                    .background(GeometryReader { geo in
                        Color.clear.onAppear {
                            // Capture the card as image
                            let image = Self.render(card: ShareableProfileCard(
                                profile: profile,
                                nickname: authViewModel.currentUser?.nickname ?? "Explorer"
                            ))
                            self.shareImage = image
                        }
                    })

                    Button(action: { showShareSheet = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(appLanguage == "zh" ? "分享到..." : "Share to...")
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(height: 50)
                        .frame(maxWidth: 240)
                        .background(AppTheme.accent)
                        .cornerRadius(25)
                    }

                    Text(appLanguage == "zh"
                         ? "让朋友也来探索他们的价值观"
                         : "Invite friends to explore their values")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }

                Spacer()
            }
        }
        .onAppear { loadProfile() }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheetView(image: image)
            }
        }
    }

    private func loadProfile() {
        guard let userId = authViewModel.currentUser?.id else { return }
        NetworkManager.shared.fetchValuesProfile(userId: userId) { result in
            DispatchQueue.main.async {
                if case .success(let profile) = result {
                    self.profile = profile
                }
            }
        }
    }

    static func render(card: ShareableProfileCard) -> UIImage {
        let controller = UIHostingController(rootView: card)
        let view = controller.view!
        let targetSize = CGSize(width: 320, height: 520)
        view.bounds = CGRect(origin: .zero, size: targetSize)
        view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }
}

// MARK: - UIActivityViewController Wrapper

struct ShareSheetView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ShareProfileView()
        .environmentObject(AuthViewModel())
}
