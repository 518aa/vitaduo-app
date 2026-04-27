//
//  ValuesTabContainer.swift
//  DateDrop3
//
//  价值观Tab的容器 — 雷达图 / 洞察 / 每日卡片 三个子页面
//

import SwiftUI

enum ValuesSubTab: String, CaseIterable {
    case radar = "radar"
    case insights = "insights"
    case dailyCard = "daily"
    case share = "share"
}

struct ValuesTabContainer: View {
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var selectedSubTab: ValuesSubTab = .radar

    private let subTabLabelsZh = ["雷达", "洞察", "每日", "分享"]
    private let subTabLabelsEn = ["Radar", "Insights", "Daily", "Share"]
    private let subTabIcons = ["hexagon.fill", "chart.bar.fill", "sparkles", "square.and.arrow.up"]

    var body: some View {
        ZStack {
            AppTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with sub-tabs
                HStack(spacing: 0) {
                    ForEach(ValuesSubTab.allCases.indices, id: \.self) { i in
                        let tab = ValuesSubTab.allCases[i]
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                selectedSubTab = tab
                            }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: subTabIcons[i])
                                    .font(.system(size: 16))
                                Text(appLanguage == "zh" ? subTabLabelsZh[i] : subTabLabelsEn[i])
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(selectedSubTab == tab ? AppTheme.accent : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedSubTab == tab
                                    ? AppTheme.accent.opacity(0.12)
                                    : Color.clear
                            )
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Sub-tab content
                TabView(selection: $selectedSubTab) {
                    ValuesProfileView()
                        .tag(ValuesSubTab.radar)

                    ValuesInsightsView()
                        .tag(ValuesSubTab.insights)

                    DailyCardView()
                        .tag(ValuesSubTab.dailyCard)

                    ShareProfileView()
                        .tag(ValuesSubTab.share)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
        }
    }
}

#Preview {
    ValuesTabContainer()
        .environmentObject(AuthViewModel())
}
