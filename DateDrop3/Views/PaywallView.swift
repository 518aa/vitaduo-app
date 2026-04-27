//
//  PaywallView.swift
//  DateDrop3
//
//  付费墙 - 购买匹配次数
//

import SwiftUI
import StoreKit
import Combine
import Foundation

struct PaywallView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @AppStorage("app_language") private var appLanguage = "en"

    @StateObject private var matchViewModel = MatchViewModel()
    @StateObject private var iapStore = IAPStore(productIds: [
        "matches.3",
        "matches.10",
        "matches.unlimited"
    ])

    @State private var selectedPackage: Package?
    @State private var isPurchasing = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showTerms = false
    @State private var animateGradient = false

    private var packages: [Package] {
        let basePackages: [Package]
        if appLanguage == "zh" {
            basePackages = [
                Package(
                    id: 1,
                    matchesCount: 3,
                    price: 18,
                    originalPrice: 18,
                    description: "3次匹配",
                    subtitle: "适合初次体验",
                    features: ["3次智能匹配", "无限聊天", "查看匹配度"],
                    productId: "matches.3",
                    isRecommended: false,
                    icon: "heart.circle"
                ),
                Package(
                    id: 2,
                    matchesCount: 10,
                    price: 48,
                    originalPrice: 60,
                    description: "10次匹配",
                    subtitle: "最受欢迎",
                    features: ["10次智能匹配", "节省20%", "优先匹配推荐", "无限聊天"],
                    productId: "matches.10",
                    isRecommended: true,
                    icon: "star.circle.fill"
                ),
                Package(
                    id: 3,
                    matchesCount: -1,
                    price: 98,
                    originalPrice: 128,
                    description: "无限次",
                    subtitle: "最佳价值",
                    features: ["无限智能匹配", "节省23%", "专属客服", "优先体验新功能"],
                    productId: "matches.unlimited",
                    isRecommended: false,
                    icon: "infinity.circle.fill"
                )
            ]
        } else {
            basePackages = [
                Package(
                    id: 1,
                    matchesCount: 3,
                    price: 18,
                    originalPrice: 18,
                    description: "3 matches",
                    subtitle: "Try it out",
                    features: ["3 Smart Matches", "Unlimited Chat", "View Compatibility"],
                    productId: "matches.3",
                    isRecommended: false,
                    icon: "heart.circle"
                ),
                Package(
                    id: 2,
                    matchesCount: 10,
                    price: 48,
                    originalPrice: 60,
                    description: "10 matches",
                    subtitle: "Most Popular",
                    features: ["10 Smart Matches", "Save 20%", "Priority Matching", "Unlimited Chat"],
                    productId: "matches.10",
                    isRecommended: true,
                    icon: "star.circle.fill"
                ),
                Package(
                    id: 3,
                    matchesCount: -1,
                    price: 98,
                    originalPrice: 128,
                    description: "Unlimited",
                    subtitle: "Best Value",
                    features: ["Unlimited Matches", "Save 23%", "Priority Support", "Early Access"],
                    productId: "matches.unlimited",
                    isRecommended: false,
                    icon: "infinity.circle.fill"
                )
            ]
        }
        let availableProductIds = Set(iapStore.products.map { $0.id })
        if availableProductIds.isEmpty {
            return []
        }
        return basePackages.filter { availableProductIds.contains($0.productId) }
    }

    var body: some View {
        ZStack {
            // 动画背景
            AppTheme.bgPrimary
                .ignoresSafeArea()
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.03))
                        .frame(width: 300, height: 300)
                        .offset(x: animateGradient ? 100 : -100)
                        .animation(
                            Animation.easeInOut(duration: 8)
                                .repeatForever(autoreverses: true),
                            value: animateGradient
                        )
                )
                .onAppear {
                    animateGradient = true
                }

            ScrollView {
                VStack(spacing: 24) {
                    // 顶部关闭按钮
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding()

                    // 顶部图标和标题
                    VStack(spacing: 16) {
                        // 主图标
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 100, height: 100)

                            Image(systemName: "heart.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.white, Color.white.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .shadow(color: Color.purple.opacity(0.3), radius: 20)

                        // 标题
                        VStack(spacing: 8) {
                            Text(appLanguage == "zh" ? "继续寻找真爱" : "Keep Searching for Love")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)

                            Text(appLanguage == "zh" ? "选择合适的套餐，遇见那个'万一'" : "Choose a package to find the one")
                                .font(.system(size: 15))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)

                    // 套餐选择
                    VStack(spacing: 12) {
                        if iapStore.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else if packages.isEmpty {
                            Text(appLanguage == "zh" ? "暂无可购买项目" : "No products available")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        } else {
                            ForEach(packages) { package in
                                PackageCard(
                                    package: package,
                                    priceText: priceText(for: package),
                                    originalPriceText: originalPriceText(for: package),
                                    isSelected: selectedPackage?.id == package.id,
                                    showDiscount: package.originalPrice > package.price,
                                    onTap: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedPackage = package
                                        }
                                    }
                                )
                                .scaleEffect(selectedPackage?.id == package.id ? 1.02 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedPackage?.id)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // 购买按钮
                    Button(action: purchase) {
                        HStack(spacing: 12) {
                            if isPurchasing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: selectedPackage != nil ? "lock.open.fill" : "cart.fill")
                                    .font(.system(size: 18))

                                Text(selectedPackage == nil
                                    ? (appLanguage == "zh" ? "选择套餐" : "Select Package")
                                    : (appLanguage == "zh" ? "立即购买" : "Buy Now"))
                                    .font(.system(size: 18, weight: .semibold))

                                if let package = selectedPackage {
                                    Text(priceText(for: package))
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            selectedPackage != nil
                                ? LinearGradient(
                                    colors: [Color.white, Color.white.opacity(0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .cornerRadius(28)
                        .shadow(color: selectedPackage != nil ? Color.white.opacity(0.3) : .clear, radius: 10)
                    }
                    .padding(.horizontal, 24)
                    .disabled(selectedPackage == nil || isPurchasing)

                    // 信任和安全提示
                    VStack(spacing: 16) {
                        // 安全提示
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                            Text(appLanguage == "zh" ? "安全支付由Apple处理" : "Secure payment by Apple")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }

                        // 条款链接
                        HStack(spacing: 20) {
                            Button(action: { showTerms = true }) {
                                Text(appLanguage == "zh" ? "条款与隐私政策" : "Terms & Privacy")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray.opacity(0.8))
                                    .underline()
                            }

                            Text(appLanguage == "zh" ? "购买记录可在App Store账户设置中查看" : "Purchase history is available in App Store settings")
                                .font(.system(size: 14))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .alert(appLanguage == "zh" ? "购买成功" : "Purchase Successful", isPresented: $showSuccess) {
            Button(appLanguage == "zh" ? "开始使用" : "Start Using") {
                dismiss()
            }
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text(appLanguage == "zh" ? "已成功购买" : "Successfully purchased")
                    .font(.headline)
                if let package = selectedPackage {
                    Text("• \(package.description)")
                    Text("• \(appLanguage == "zh" ? "立即生效" : "Activated now")")
                }
            }
        }
        .alert(appLanguage == "zh" ? "购买失败" : "Purchase Failed", isPresented: $showError) {
            Button(appLanguage == "zh" ? "重试" : "Retry", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showTerms) {
            TermsView()
        }
    }

    // MARK: - 购买逻辑

    private func purchase() {
        guard let package = selectedPackage else { return }
        isPurchasing = true

        guard let product = iapStore.product(for: package.productId) else {
            isPurchasing = false
            showError(message: appLanguage == "zh" ? "内购商品未加载，请检查StoreKit配置" : "IAP products not loaded. Check StoreKit configuration.")
            return
        }
        Task {
            do {
                let purchased = try await iapStore.purchase(product)
                if purchased {
                    let amount = NSDecimalNumber(decimal: product.price).doubleValue
                    await finalizePurchase(package: package, amount: amount)
                } else {
                    isPurchasing = false
                }
            } catch {
                isPurchasing = false
                await MainActor.run {
                    showError(message: error.localizedDescription)
                }
            }
        }
    }

    private func restorePurchases() {
        Task {
            do {
                try await iapStore.restore()
                await MainActor.run {
                    showError(message: appLanguage == "zh" ? "购买记录已恢复" : "Purchases restored")
                }
            } catch {
                await MainActor.run {
                    showError(message: error.localizedDescription)
                }
            }
        }
    }

    private func finalizePurchase(package: Package, amount: Double) async {
        let matchesToAdd = package.matchesCount == -1 ? 999 : package.matchesCount
        matchViewModel.purchaseMatches(
            matchesAdded: matchesToAdd,
            amount: amount
        )
        isPurchasing = false
        showSuccess = true
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    private func priceText(for package: Package) -> String {
        if let product = iapStore.product(for: package.productId) {
            return product.displayPrice
        }
        return appLanguage == "zh" ? "未知价格" : "Unknown"
    }

    private func originalPriceText(for package: Package) -> String {
        if package.originalPrice > package.price {
            return "¥\(package.originalPrice)"
        }
        return ""
    }
}

// MARK: - 套餐模型

struct Package: Identifiable {
    let id: Int
    let matchesCount: Int
    let price: Int
    let originalPrice: Int
    let description: String
    let subtitle: String
    let features: [String]
    let productId: String
    let isRecommended: Bool
    let icon: String
}

// MARK: - 套餐卡片

struct PackageCard: View {
    let package: Package
    let priceText: String
    let originalPriceText: String
    let isSelected: Bool
    let showDiscount: Bool
    let onTap: () -> Void
    @AppStorage("app_language") private var appLanguage = "en"

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            if package.isRecommended {
                recommendedBadge
            }

            mainContent
        }
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: isSelected ? Color.green.opacity(0.2) : .clear, radius: 10)
    }

    private var recommendedBadge: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
                Text(recommendedText)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(orangeGradient)
            .cornerRadius(12)
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
    }

    private var recommendedText: String {
        appLanguage == "zh" ? "推荐" : "Recommended"
    }

    private var mainContent: some View {
        VStack(spacing: 12) {
            headerRow
            divider
            featuresList
        }
        .padding(16)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            iconView
            descriptionView
            Spacer()
            priceView
        }
    }

    private var iconView: some View {
        Image(systemName: package.icon)
            .font(.system(size: 32))
            .foregroundStyle(iconGradient)
            .frame(width: 50, height: 50)
            .background(Circle().fill(iconBackground))
    }

    private var iconGradient: LinearGradient {
        LinearGradient(
            colors: iconColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconColors: [Color] {
        isSelected
            ? [Color.white, Color.white.opacity(0.8)]
            : [Color.white.opacity(0.6), Color.white.opacity(0.4)]
    }

    private var iconBackground: Color {
        isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.05)
    }

    private var descriptionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(package.description)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text(package.subtitle)
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
    }

    private var priceView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if showDiscount {
                Text(originalPriceText)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .strikethrough()
            }

            Text(priceText)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(isSelected ? .green : .white)

            if showDiscount {
                discountBadge
            }
        }
    }

    private var discountBadge: some View {
        let discount = Int((1.0 - Float(package.price) / Float(package.originalPrice)) * 100)
        return Text("-\(discount)%")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.15))
            .cornerRadius(6)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(height: 1)
    }

    private var featuresList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(package.features, id: \.self) { feature in
                featureRow(feature)
            }
        }
    }

    private func featureRow(_ feature: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)

            Text(feature)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))

            Spacer()
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(borderGradient, lineWidth: isSelected ? 2 : 1)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: borderColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColors: [Color] {
        isSelected
            ? [Color.green.opacity(0.8), Color.green.opacity(0.4)]
            : [Color.white.opacity(0.1)]
    }

    private var orangeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.orange, Color.orange.opacity(0.8)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - 条款视图

struct TermsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("app_language") private var appLanguage = "en"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 服务条款
                    VStack(alignment: .leading, spacing: 12) {
                        Text(appLanguage == "zh" ? "服务条款" : "Terms of Service")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)

                        termsContent
                    }

                    Divider()
                        .background(Color.white.opacity(0.2))

                    // 隐私政策
                    VStack(alignment: .leading, spacing: 12) {
                        Text(appLanguage == "zh" ? "隐私政策" : "Privacy Policy")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)

                        privacyContent
                    }

                    // 退款说明
                    VStack(alignment: .leading, spacing: 12) {
                        Text(appLanguage == "zh" ? "退款政策" : "Refund Policy")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)

                        refundContent
                    }
                }
                .padding()
            }
            .background(AppTheme.bgPrimary.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(appLanguage == "zh" ? "完成" : "Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private var termsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLanguage == "zh"
                ? "• 购买套餐后，匹配次数将立即添加到您的账户\n• 匹配次数不可退款，除非出现技术故障\n• 我们保留随时修改套餐价格的权利\n• 滥用服务可能导致账户暂停"
                : "• Match credits are added immediately after purchase\n• Credits are non-refundable except in case of technical failure\n• We reserve the right to modify package prices\n• Service abuse may result in account suspension")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .lineSpacing(4)
        }
    }

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLanguage == "zh"
                ? "• 我们尊重您的隐私，不会共享您的个人信息\n• 购买信息仅由Apple处理，我们不会存储支付细节\n• 使用数据仅用于改善服务质量"
                : "• We respect your privacy and never share your personal information\n• Payment data is handled by Apple only; we don't store payment details\n• Usage data is used solely to improve service quality")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .lineSpacing(4)
        }
    }

    private var refundContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLanguage == "zh"
                ? "• 如遇技术问题导致购买失败，请联系客服\n• 我们会在5个工作日内处理退款请求\n• Apple的退款政策同样适用于本应用"
                : "• Contact support if technical issues cause purchase failure\n• Refund requests are processed within 5 business days\n• Apple's refund policy also applies to this app")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .lineSpacing(4)
        }
    }
}

@MainActor
final class IAPStore: ObservableObject {
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var lastError: String?

    private let productIds: [String]
    private var updateListenerTask: Task<Void, Error>?

    init(productIds: [String]) {
        self.productIds = productIds
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        do {
            products = try await Product.products(for: productIds)
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try IAPStore.checkVerified(verification)
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async throws {
        try await AppStore.sync()
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try IAPStore.checkVerified(result)
                    await transaction.finish()
                } catch {
                    await self?.refreshProductsIfNeeded()
                }
            }
        }
    }

    private func refreshProductsIfNeeded() async {
        if products.isEmpty {
            await loadProducts()
        }
    }

    nonisolated private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}

#Preview {
    PaywallView()
        .environmentObject(AuthViewModel())
}
