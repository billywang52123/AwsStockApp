import SwiftUI

// MARK: - 9a · 更新持股入口 UpdateIntentSheet(spec 04)
// 核心 UX:先問意圖(加碼/賣出/覆蓋),再問數字,
// 避免直接改股數造成「取代還是攤平」語意不明。

enum HoldingUpdateIntent: Identifiable, Equatable {
    case buy       // 9b 加碼買進(往上攤平)
    case sell      // 9c 賣出
    case override  // 覆蓋為最新庫存(取代股數、均價保留)

    var id: Int {
        switch self {
        case .buy: return 0
        case .sell: return 1
        case .override: return 2
        }
    }
}

struct UpdateIntentSheet: View {
    let holding: Holding
    let onSelect: (HoldingUpdateIntent) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("更新\(holding.name)持股")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .padding(.top, 18)

            Text("目前 \(holding.totalShares.formatted()) 股\(avgPriceText),先選這次想做的事")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 4)

            VStack(spacing: 11) {
                intentRow(
                    iconText: "+", iconColor: AppColor.upText, iconBg: Color(hex: "F5EAEA"),
                    title: "我有加買",
                    subtitle: "輸入這次買的股數和價格,自動幫你往上攤平均價"
                ) { select(.buy) }

                intentRow(
                    iconText: "−", iconColor: AppColor.downText, iconBg: Color(hex: "EAF2EC"),
                    title: "我有賣出",
                    subtitle: "股數減少、均價不變,幫你算這筆已實現損益"
                ) { select(.sell) }

                intentRow(
                    systemIcon: "arrow.triangle.2.circlepath", iconColor: AppColor.inkTertiary, iconBg: AppColor.bgTrack,
                    title: "直接改成最新庫存",
                    subtitle: "以券商 App 上的股數為準,取代目前紀錄、均價保留"
                ) { select(.override) }
            }
            .padding(.top, 18)

            // 提示盒:多券商引導走截圖匯入
            Text("有好幾家券商的話,用「拍照或匯入對帳單」一次帶入,我們會幫你分帳加總。")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(Color(hex: "4A4770"))
                .lineSpacing(12 * 0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(AppColor.primaryBgTint)
                .cornerRadius(14)
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 44)
        .background(AppColor.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var avgPriceText: String {
        guard let avg = holding.avgPrice else { return "" }
        return " · 均價 \(avg.formatted(.number.precision(.fractionLength(0...1))))"
    }

    private func select(_ intent: HoldingUpdateIntent) {
        HapticManager.shared.triggerImpact(style: .light)
        dismiss()
        onSelect(intent)
    }

    @ViewBuilder
    private func intentRow(
        iconText: String? = nil,
        systemIcon: String? = nil,
        iconColor: Color,
        iconBg: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(iconBg)
                        .frame(width: 46, height: 46)
                    if let text = iconText {
                        Text(text)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(iconColor)
                    } else if let icon = systemIcon {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(iconColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColor.inkFaint)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}
