import SwiftUI

// MARK: - 出處 chip(信任系統原子元件)
// 所有 AI 結論句尾掛可點小標籤;點開 bottom sheet 顯示欄位/原始值/算法/資料日期/來源

struct SourceChipView: View {
    let chip: SourceChip
    var tint: SourceChipTint = .neutral
    let onTap: (SourceChip) -> Void

    enum SourceChipTint {
        case neutral      // 事實卡/一般:灰
        case inference    // 推論卡:藍紫

        var bg: Color { self == .neutral ? TrustCardColor.sourceChipBg : TrustCardColor.inferenceChipBg }
        var border: Color { self == .neutral ? TrustCardColor.sourceChipBorder : TrustCardColor.inferenceChipBorder }
        var text: Color { self == .neutral ? TrustCardColor.sourceChipText : TrustCardColor.inferenceChipText }
    }

    var body: some View {
        Button {
            HapticManager.shared.triggerImpact(style: .light)
            onTap(chip)
        } label: {
            HStack(spacing: 3) {
                Text(chip.label)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)   // 不可換行
                Text("›")
                    .font(.system(size: 10.5, weight: .bold))
            }
            .foregroundColor(tint.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.bg)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(tint.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 15i · 出處 chip Bottom Sheet `SourceChipSheet`

struct SourceChipSheet: View {
    let chip: SourceChip
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Grabber
            Capsule()
                .fill(AppColor.bgTrack)
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            // 頂部:chip 原樣放大 + 關閉鈕
            HStack {
                SourceChipView(chip: chip) { _ in }
                    .scaleEffect(1.25, anchor: .leading)
                    .allowsHitTesting(false)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppColor.inkTertiary)
                        .frame(width: 28, height: 28)
                        .background(AppColor.bgTrack)
                        .clipShape(Circle())
                }
            }
            .padding(.top, 22)

            Text("這個 chip 是這句 AI 結論用到的資料出處")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 10)

            // 資料明細表
            VStack(spacing: 0) {
                detailRow("使用的欄位", chip.field)
                divider
                detailRow("原始數值", chip.rawValue, monospaced: true)
                divider
                detailRow("計算方式", chip.formula, monospaced: true, allowWrap: true)
                divider
                detailRow("資料日期", chip.dataDate, monospaced: true)
                divider
                detailRow("資料來源", chip.source, allowWrap: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(AppColor.bgInset)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 16)

            // 驗證提示盒
            Text("✓ 這個數字你在券商 App 也查得到——不用相信 AI,可以自己驗證。")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundColor(Color(hex: "4A4770"))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppColor.primaryBgTint)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 12)

            // CTA
            Button(action: onClose) {
                Text("我知道了")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())
            .padding(.top, 18)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
        .background(AppColor.background.ignoresSafeArea())
        .presentationDetents([.height(470)])
        .presentationDragIndicator(.hidden)
    }

    private var divider: some View {
        Rectangle().fill(Color(hex: "EFEAE0")).frame(height: 1)
    }

    private func detailRow(_ label: String, _ value: String,
                           monospaced: Bool = false, allowWrap: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced
                      ? .system(size: 12.5, weight: .bold, design: .monospaced)
                      : .system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(allowWrap ? nil : 1)
                .lineSpacing(4)
        }
        .padding(.vertical, 11)
    }
}

// MARK: - 15g · 名詞小卡(虛線術語點開)

struct GlossaryTermSheet: View {
    let term: GlossaryTerm
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(AppColor.bgTrack)
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            HStack(spacing: 8) {
                Text("📖")
                    .font(.system(size: 20))
                Text(term.term)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Spacer()
            }
            .padding(.top, 12)

            Text(term.definition)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppColor.inkSecondary)
                .lineSpacing(8)

            Text("名詞小卡只解釋概念,不是對任何個股的評價。")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkFaint)

            Button(action: onClose) {
                Text("我知道了")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())
            .padding(.top, 4)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .background(AppColor.background.ignoresSafeArea())
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
    }
}
