//
//  EULAView.swift
//  DateDrop3
//
//  EULA & Terms of Service — required for Guideline 1.2 (User Generated Content)
//

import SwiftUI

struct EULAView: View {
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("eula_accepted") private var eulaAccepted = false

    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text(appLanguage == "zh" ? "使用条款" : "Terms of Use")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)

                    Text(appLanguage == "zh"
                         ? "请仔细阅读以下条款后继续使用 VitaDuo"
                         : "Please read the following terms before using VitaDuo")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if appLanguage == "zh" {
                            eulaContentChinese
                        } else {
                            eulaContentEnglish
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        eulaAccepted = true
                        onAccept()
                    }) {
                        Text(appLanguage == "zh" ? "我已阅读并同意" : "I Agree")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white)
                            .cornerRadius(28)
                    }

                    Button(action: onDecline) {
                        Text(appLanguage == "zh" ? "拒绝" : "Decline")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
    }

    // MARK: - English EULA

    @ViewBuilder
    private var eulaContentEnglish: some View {
        eulaSection(title: "1. User-Generated Content") {
            """
VitaDuo allows users to communicate with matched users. By using this app, you agree that:

• There is zero tolerance for objectionable content, including but not limited to: hate speech, \
harassment, bullying, nudity, pornography, graphic violence, illegal content, or any content that \
exploits or harms minors.

• There is zero tolerance for abusive behavior toward other users.

• You are solely responsible for content you post or send. Content that violates these terms may \
result in immediate removal and permanent account termination.
"""
        }

        eulaSection(title: "2. Reporting & Moderation") {
            """
We provide in-app tools to:

• Flag and report objectionable content or abusive users.
• Block users from contacting you.
• Remove your own messages from the conversation.

The VitaDuo team will review all reports and act on confirmed violations within 24 hours, including \
removing offending content and suspending or terminating the offending account.
"""
        }

        eulaSection(title: "3. AI-Powered Features") {
            """
VitaDuo uses a third-party AI service (ZhipuAI GLM) to power features such as intelligent chat \
assistants, match introductions, and message translation.

• Chat messages and anonymized profile data may be transmitted to ZhipuAI for AI-generated responses.
• No personally identifiable information (such as your real name, contact details, or exact location) \
is shared with AI services without your knowledge.
• By agreeing to these terms, you consent to the use of your messages to generate AI responses \
within the app.

You may contact us at support@vitaduo.app to request data deletion at any time.
"""
        }

        eulaSection(title: "4. Privacy") {
            """
We collect only the minimum information necessary to provide our service. You may provide optional \
information (such as your city or contact details) to enhance your experience, but these are not \
required to use core app features.

For full details, please review our Privacy Policy at vitaduo.app/privacy.
"""
        }

        eulaSection(title: "5. Contact & Reporting") {
            """
To report inappropriate activity, abuse, or policy violations:

• Use the in-app "Report" button in any chat conversation.
• Email us directly at: support@vitaduo.app

We are committed to maintaining a safe and respectful community.
"""
        }
    }

    // MARK: - Chinese EULA

    @ViewBuilder
    private var eulaContentChinese: some View {
        eulaSection(title: "1. 用户生成内容") {
            """
VitaDuo 允许用户与匹配对象进行通信。使用本应用，即表示您同意：

• 零容忍不当内容，包括但不限于：仇恨言论、骚扰、霸凌、裸露、色情、严重暴力、违法内容，或任何伤害未成年人的内容。

• 零容忍对其他用户的辱骂行为。

• 您对自己发布或发送的内容承担全部责任。违反本条款的内容将被立即删除，账号可能被永久封禁。
"""
        }

        eulaSection(title: "2. 举报与内容管理") {
            """
我们提供以下应用内工具：

• 举报不当内容或滥用行为的用户。
• 屏蔽不希望联系您的用户。
• 从对话中删除您自己发送的消息。

VitaDuo 团队将审核所有举报，并在 24 小时内处理已确认的违规行为，包括删除违规内容并暂停或终止违规账号。
"""
        }

        eulaSection(title: "3. AI 功能说明") {
            """
VitaDuo 使用第三方 AI 服务（智谱 AI GLM）来支持智能聊天助手、匹配介绍和消息翻译等功能。

• 聊天消息和匿名化的个人资料数据可能会被传输至智谱 AI 以生成 AI 回复。
• 未经您知情，您的真实姓名、联系方式或精确位置等个人身份信息不会被共享给 AI 服务。
• 同意本条款即表示您授权使用您的消息在应用内生成 AI 回复。

您可以随时通过 support@vitaduo.app 联系我们请求删除数据。
"""
        }

        eulaSection(title: "4. 隐私保护") {
            """
我们仅收集提供服务所需的最少信息。您可以选择性提供额外信息（如城市或联系方式）以改善体验，但这些信息不是使用核心功能的必要条件。

完整内容请查看我们的隐私政策：vitaduo.app/privacy
"""
        }

        eulaSection(title: "5. 联系与举报") {
            """
如需举报不当活动、滥用行为或违规内容：

• 在任何聊天对话中使用应用内"举报"按钮。
• 直接发送邮件至：support@vitaduo.app

我们致力于维护安全、尊重的社区环境。
"""
        }
    }

    // MARK: - Helper

    @ViewBuilder
    private func eulaSection(title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text(content())
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

#Preview {
    EULAView(onAccept: {}, onDecline: {})
}
