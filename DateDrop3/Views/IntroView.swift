//
//  IntroView.swift
//  DateDrop3
//
//  沉浸式引导页 — 价值观探索旅程的起点
//

import SwiftUI

struct IntroView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var showEULA = false
    @State private var showRegister = false
    @State private var showResearchConsent = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var opacity1 = false
    @State private var opacity2 = false
    @State private var opacity3 = false
    @State private var tapCount = 0

    var body: some View {
        ZStack {
            // Background
            AppTheme.bgPrimary.ignoresSafeArea()

            // Ambient orbs
            Circle()
                .fill(AppTheme.accent.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: -80, y: -120)

            Circle()
                .fill(AppTheme.accentLight.opacity(0.06))
                .frame(width: 250, height: 250)
                .blur(radius: 50)
                .offset(x: 100, y: 200)

            VStack(spacing: 0) {
                Spacer()

                // Central icon cluster
                ZStack {
                    BreathingPulse(color: AppTheme.accent)
                        .frame(width: 160, height: 160)

                    Circle()
                        .fill(AppTheme.bgCard)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.accent.opacity(0.3), lineWidth: 2)
                        )
                        .overlay(
                            Image(systemName: "hexagon.fill")
                                .font(.system(size: 36, design: .rounded))
                                .foregroundStyle(AppTheme.accent)
                        )
                }
                .scaleEffect(pulseScale)
                .padding(.bottom, 40)

                // Title
                Text("VitaDuo")
                    .font(AppTheme.displayLarge)
                    .foregroundStyle(AppTheme.textPrimary)
                    .opacity(opacity1 ? 1 : 0)
                    .offset(y: opacity1 ? 0 : 16)
                    .onTapGesture(count: 3) {
                        // Dev backdoor: triple-tap for review login
                        tapCount += 1
                        if tapCount >= 1 {
                            authViewModel.reviewLogin(nickname: "test", contact: "8502test")
                        }
                    }

                // Tagline
                Text(appLanguage == "zh"
                     ? "探索你的价值观宇宙"
                     : "Explore Your Values Universe")
                    .font(AppTheme.titleCard)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 8)
                    .opacity(opacity2 ? 1 : 0)
                    .offset(y: opacity2 ? 0 : 12)

                // Subtitle
                Text(appLanguage == "zh"
                     ? "通过科学问卷发现你的核心价值观\n并与志同道合的人建立深度连接"
                     : "Discover your core values through a scientific assessment\nand connect with like-minded people")
                    .font(AppTheme.bodyPrimary)
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.top, 16)
                    .padding(.horizontal, 40)
                    .opacity(opacity3 ? 1 : 0)
                    .offset(y: opacity3 ? 0 : 12)

                Spacer()

                // Language toggle
                HStack(spacing: 0) {
                    Text("EN")
                        .font(AppTheme.captionPill)
                        .foregroundStyle(appLanguage == "en" ? AppTheme.accent : AppTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(appLanguage == "en" ? AppTheme.accent.opacity(0.12) : Color.clear)
                        .clipShape(Capsule())
                        .onTapGesture { appLanguage = "en" }

                    Text("中文")
                        .font(AppTheme.captionPill)
                        .foregroundStyle(appLanguage == "zh" ? AppTheme.accent : AppTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(appLanguage == "zh" ? AppTheme.accent.opacity(0.12) : Color.clear)
                        .clipShape(Capsule())
                        .onTapGesture { appLanguage = "zh" }
                }
                .padding(.bottom, 16)

                // CTA button
                AccentButton(
                    title: appLanguage == "zh" ? "开始探索" : "Get Started"
                ) {
                    showEULA = true
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                Text(appLanguage == "zh"
                     ? "继续即表示同意我们的使用条款"
                     : "By continuing you agree to our Terms")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.5))
                    .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showEULA) {
            EULAView(onAccept: {
                showEULA = false
                showRegister = true
            })
        }
        .fullScreenCover(isPresented: $showRegister) {
            RegisterView()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.6)) { opacity1 = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.6)) { opacity2 = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.6)) { opacity3 = true }
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.03
            }
        }
    }
}

#Preview {
    IntroView().environmentObject(AuthViewModel())
}
