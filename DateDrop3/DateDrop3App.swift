//
//  DateDrop3App.swift
//  DateDrop3
//
//  App入口
//

import SwiftUI

@main
struct VitaDuoApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @AppStorage("app_language") private var appLanguage = "en"
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environment(\.locale, Locale(identifier: appLanguage == "zh" ? "zh-Hans" : "en"))
                .onAppear {
                    configureAppearance()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        TelemetryManager.shared.startSession()
                    case .background:
                        TelemetryManager.shared.endSession()
                    default:
                        break
                    }
                }
        }
    }

    private func configureAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = AppTheme.navBarColor
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold, design: .rounded)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold, design: .rounded)
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.accent)

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = AppTheme.tabBarColor
        let itemAppearance = tabBarAppearance.stackedLayoutAppearance
        itemAppearance.normal.iconColor = UIColor.secondaryLabel
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        itemAppearance.selected.iconColor = UIColor(AppTheme.accent)
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.accent)]

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
}

// MARK: - Design System

struct AppTheme {
    // ── Colors ──
    // Primary palette: Indigo + Lavender (insightful, psychological)
    static let accent       = Color(red: 0.39, green: 0.40, blue: 0.95)   // #6366F1 Indigo
    static let accentLight  = Color(red: 0.65, green: 0.55, blue: 0.98)   // #A78BFA Lavender
    static let success      = Color(red: 0.43, green: 0.91, blue: 0.72)   // #6EE7B7 Sage Green
    static let warning      = Color(red: 0.99, green: 0.83, blue: 0.30)   // #FCD34D Amber Glow
    static let bgPrimary    = Color(red: 0.06, green: 0.06, blue: 0.10)   // #0F0F1A
    static let bgCard       = Color(red: 0.12, green: 0.12, blue: 0.20)   // #1E1E32
    static let bgElevated   = Color(red: 0.16, green: 0.16, blue: 0.26)   // #2A2A42

    static let navBarColor  = UIColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 0.85)
    static let tabBarColor  = UIColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 0.95)

    // Semantic
    static let textPrimary  = Color(red: 0.97, green: 0.98, blue: 0.99)   // #F8FAFC
    static let textSecondary = Color(red: 0.58, green: 0.64, blue: 0.72)  // #94A3B8

    // Gradients
    static let heroGradient = LinearGradient(
        colors: [accent, accentLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [bgPrimary, Color(red: 0.08, green: 0.08, blue: 0.15)],
        startPoint: .top,
        endPoint: .bottom
    )

    // Legacy compat
    static let accentColor = accent
    static let background = backgroundGradient

    // ── Typography ──
    static let displayLarge  = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let titleCard     = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let bodyPrimary   = Font.system(size: 17, weight: .regular, design: .default)
    static let captionPill   = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let monoNumber    = Font.system(size: 20, weight: .medium, design: .monospaced)

    // ── Spacing ──
    static let spacingXS: CGFloat  = 4
    static let spacingS: CGFloat   = 8
    static let spacingM: CGFloat   = 16
    static let spacingL: CGFloat   = 24
    static let spacingXL: CGFloat  = 32

    // ── Radii ──
    static let radiusS: CGFloat  = 8
    static let radiusM: CGFloat  = 14
    static let radiusL: CGFloat  = 20
    static let radiusXL: CGFloat = 28

    // ── Dimension labels ──
    static let sectionLabelsZh: [String: String] = [
        "core_values": "核心价值观", "lifestyle": "生活方式",
        "political": "社会观点", "relationship": "关系期望",
        "personality": "人格特质", "communication": "沟通风格"
    ]
    static let sectionLabelsEn: [String: String] = [
        "core_values": "Core Values", "lifestyle": "Lifestyle",
        "political": "Social Views", "relationship": "Relationships",
        "personality": "Personality", "communication": "Communication"
    ]
    static let sectionIcons: [String: String] = [
        "core_values": "diamond.fill", "lifestyle": "sunrise.fill",
        "political": "building.columns.fill", "relationship": "heart.fill",
        "personality": "brain.head.profile.fill", "communication": "bubble.left.and.bubble.right.fill"
    ]
}

// MARK: - Reusable Components

/// Glassmorphism card with blur effect
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = AppTheme.radiusM
    var padding: CGFloat = AppTheme.spacingM
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(padding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Category pill tag
struct PillTag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(AppTheme.captionPill)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// Breathing pulse animation
struct BreathingPulse: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(color.opacity(0.25))
            .scaleEffect(isAnimating ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

/// Accent gradient button
struct AccentButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: 26))
        }
    }
}
