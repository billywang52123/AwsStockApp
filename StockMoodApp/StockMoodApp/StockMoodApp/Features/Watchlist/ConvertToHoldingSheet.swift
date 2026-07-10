import SwiftUI

// MARK: - 11d · 轉入庫存 ConvertToHoldingSheet
/// 觀察清單 → 持股的唯一橋樑:輸入張數/零股與選填均價,
/// 轉入後移出清單、開始計入市值/損益/焦慮分數。
struct ConvertToHoldingSheet: View {
    @ObservedObject var viewModel: WatchlistViewModel
    let stock: WatchStock
    var onConverted: (ConvertResult) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var lots = 1              // 張數(1 張 = 1,000 股)
    @State private var oddSharesText = ""    // 零股:直接輸入(有人只買 10 股)
    @State private var priceText = ""
    @State private var isSubmitting = false
    @State private var showCheck = false

    private var oddShares: Int { Int(oddSharesText) ?? 0 }
    private var totalShares: Int { lots * 1000 + oddShares }

    private var estimatedValueWan: Double? {
        guard let close = stock.closePrice else { return nil }
        return close * Double(totalShares) / 10_000
    }

    private var price: Double? {
        Double(priceText.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(AppColor.bgTrack)
                    .frame(width: 40, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)

                // 標題列:頭像 + 標題 + 個股資訊
                HStack(spacing: 12) {
                    IndustryAvatar(name: stock.name, industry: stock.industry)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("轉入我的持股")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundColor(AppColor.inkPrimary)
                        Text(subtitleText)
                            .font(.system(size: 12, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(AppColor.inkQuaternary)
                    }
                    Spacer()
                }
                .padding(.top, 18)

                // 張數 stepper + 零股直接輸入
                HStack(spacing: 12) {
                    stepperBox(label: "張數", note: "1 張 = 1,000 股", value: $lots, step: 1, range: 0...999)
                    oddSharesBox
                }
                .padding(.top, 20)

                // 合計盒
                HStack {
                    Text("共 \(totalShares.formatted()) 股")
                    Spacer()
                    if let wan = estimatedValueWan {
                        Text("約市值 \(String(format: "%.1f", wan)) 萬")
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Color(hex: "4A4770"))
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .background(AppColor.primaryBgTint)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 12)
                .animation(.easeOut(duration: 0.15), value: totalShares)

                // 買進均價(選填)
                HStack(spacing: 6) {
                    Text("買進均價")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text("選填,之後可補")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.inkFaint)
                }
                .padding(.top, 16)

                HStack {
                    TextField(stock.closePrice.map { "例如 \($0.formatted(.number.precision(.fractionLength(0...2))))" } ?? "每股價格", text: $priceText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .keyboardType(.decimalPad)
                    Text("元 / 股")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppColor.inkFaint)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(AppColor.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AppColor.bgTrack, lineWidth: 1.5)
                )
                .padding(.top, 8)

                // 提示盒
                if let list = viewModel.selectedList {
                    Text("轉入後會移出「\(list.name)」,開始計入市值、損益與焦慮分數。")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.amberText)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 11)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColor.watchScoreBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 14)
                }

                // CTA
                Button {
                    submit()
                } label: {
                    Group {
                        if showCheck {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("確認轉入")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .background(AppColor.primary.opacity(totalShares > 0 ? 1 : 0.4))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: AppColor.primary.opacity(0.35), radius: 13, x: 0, y: 10)
                .disabled(totalShares <= 0 || isSubmitting)
                .padding(.top, 18)

                if viewModel.hasError {
                    Text(viewModel.errorMessage)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.roseStrong)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 42)
        }
        .background(AppColor.background)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.hidden)
    }

    private var subtitleText: String {
        if let close = stock.closePrice {
            return "\(stock.name) \(stock.symbol) · 現價 \(close.formatted(.number.precision(.fractionLength(0...2))))"
        }
        return "\(stock.name) \(stock.symbol)"
    }

    // 張數 / 零股 stepper 欄
    private func stepperBox(label: String, note: String, value: Binding<Int>,
                            step: Int, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                Text(note)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(AppColor.inkFaint)
            }

            HStack(spacing: 10) {
                stepButton(icon: "minus") {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                }
                Text("\(value.wrappedValue)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColor.inkPrimary)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: value.wrappedValue)
                stepButton(icon: "plus") {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(AppColor.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // 零股欄:直接輸入 0–999 股(零股交易常見 10 股、37 股等任意數)
    private var oddSharesBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("零股")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                Text("股,直接輸入")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(AppColor.inkFaint)
            }

            TextField("0", text: $oddSharesText)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(AppColor.inkPrimary)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32)
                .onChange(of: oddSharesText) { _, newValue in
                    // 只收數字,上限 999(滿 1,000 股請用張數)
                    var filtered = String(newValue.filter(\.isNumber).prefix(3))
                    if let n = Int(filtered), n > 999 { filtered = "999" }
                    if filtered != newValue { oddSharesText = filtered }
                }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(AppColor.bgInset)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stepButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.triggerImpact(style: .light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColor.primary)
                .frame(width: 32, height: 32)
                .background(AppColor.cardBackground)
                .clipShape(Circle())
                .shadow(color: Color(hex: "786446").opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private func submit() {
        guard totalShares > 0 else { return }
        isSubmitting = true
        Task {
            if let result = await viewModel.convert(symbol: stock.symbol, shares: totalShares, price: price) {
                HapticManager.shared.triggerImpact(style: .medium)
                withAnimation(.easeOut(duration: 0.3)) { showCheck = true }
                try? await Task.sleep(nanoseconds: 450_000_000)
                onConverted(result)
                dismiss()
            }
            isSubmitting = false
        }
    }
}
