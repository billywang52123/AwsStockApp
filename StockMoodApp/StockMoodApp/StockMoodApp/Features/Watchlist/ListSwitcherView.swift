import SwiftUI

// MARK: - 11a · 持股頁清單切換 ListSwitcher

/// 觸發列:白底 pill + 標題 + chevron(展開時反轉 180°)
struct ListSwitcherTrigger: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColor.primary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.easeOut(duration: 0.25), value: isExpanded)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(AppColor.cardBackground)
            .clipShape(Capsule())
            .shadow(color: Color(hex: "2B2824").opacity(0.16), radius: 13, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切換清單,目前是\(title)")
    }
}

/// 下拉選單容器:scrim + 選單(scale 0.96→1 + fade,錨點左上)
struct ListSwitcherMenu: View {
    @ObservedObject var viewModel: WatchlistViewModel
    @Binding var isPresented: Bool
    let onCreateList: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // scrim:點擊任意處收合;持股頁內容維持原樣不位移
            Color(hex: "2B2824").opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 2) {
                holdingRowView

                ForEach(viewModel.watchlists) { list in
                    watchlistRowView(list)
                }

                Rectangle()
                    .fill(AppColor.bgTrack)
                    .frame(height: 1)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)

                createRowView
            }
            .padding(10)
            .frame(width: 262)
            .background(AppColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color(hex: "2B2824").opacity(0.26), radius: 30, x: 0, y: 24)
            .padding(.top, 8)
            .padding(.leading, 24)
            .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
    }

    // 「我的持股」列
    private var holdingRowView: some View {
        let isSelected = viewModel.selectedList == nil
        return Button {
            HapticManager.shared.triggerSelection()
            close()
            Task { await viewModel.select(nil) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 17))
                    .foregroundColor(AppColor.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("我的持股")
                        .font(.system(size: 14, weight: isSelected ? .heavy : .bold, design: .rounded))
                        .foregroundColor(isSelected ? Color(hex: "4A4770") : AppColor.inkPrimary)
                    Text("\(viewModel.holdingCount) 檔 · 已買進")
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColor.inkQuaternary)
                }
                Spacer()
                if isSelected { checkmark }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(isSelected ? AppColor.primaryBgTint : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // 觀察清單列(實心星=有資料 / 空心星=空清單)
    private func watchlistRowView(_ list: WatchlistSummary) -> some View {
        let isSelected = viewModel.selectedList?.id == list.id
        return Button {
            HapticManager.shared.triggerSelection()
            close()
            Task { await viewModel.select(list) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: list.stockCount > 0 ? "star.fill" : "star")
                    .font(.system(size: 17))
                    .foregroundColor(list.tintColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(list.name)
                        .font(.system(size: 14, weight: isSelected ? .heavy : .bold, design: .rounded))
                        .foregroundColor(isSelected ? Color(hex: "4A4770") : AppColor.inkPrimary)
                        .lineLimit(1)
                    Text("\(list.stockCount) 檔 · 觀察中")
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppColor.inkQuaternary)
                }
                Spacer()
                if isSelected { checkmark }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(isSelected ? AppColor.primaryBgTint : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // 「新增觀察清單」列 → 11b
    private var createRowView: some View {
        Button {
            HapticManager.shared.triggerImpact(style: .light)
            close()
            onCreateList()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColor.primary)
                Text("新增觀察清單")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.primary)
                Spacer()
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(AppColor.primary)
    }
}

// MARK: - 11b · 新增觀察清單 CreateWatchlistSheet

struct CreateWatchlistSheet: View {
    @ObservedObject var viewModel: WatchlistViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedColor: WatchlistColorOption = .amber
    @State private var isSubmitting = false
    @FocusState private var nameFocused: Bool

    private let quickNames = ["半導體", "高股息", "ETF 名單", "存股候選"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // grabber
            Capsule()
                .fill(AppColor.bgTrack)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            Text("新增觀察清單")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)
                .padding(.top, 18)
            Text("還沒買的先放這裡,AI 幫你先盯著")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 4)

            // 名稱輸入框
            TextField("清單名稱,例如:半導體觀察", text: $name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .focused($nameFocused)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(AppColor.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(nameFocused ? AppColor.primary : AppColor.bgTrack, lineWidth: 1.5)
                )
                .padding(.top, 20)

            // 快速套用 chips(fade+up stagger 40ms)
            FlowChips(items: quickNames) { item in
                HapticManager.shared.triggerSelection()
                name = item
            }
            .padding(.top, 16)

            // 清單顏色 5 圓點
            HStack(spacing: 12) {
                ForEach(WatchlistColorOption.allCases) { option in
                    Button {
                        HapticManager.shared.triggerSelection()
                        selectedColor = option
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .padding(selectedColor == option ? -2 : 0)
                                    .opacity(selectedColor == option ? 1 : 0)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(option.color, lineWidth: 2)
                                    .padding(-4)
                                    .opacity(selectedColor == option ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清單顏色")
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 4)

            // CTA
            Button {
                submit()
            } label: {
                if isSubmitting {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                } else {
                    Text("建立清單")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
            }
            .background(AppColor.primary.opacity(trimmedName.isEmpty ? 0.4 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: AppColor.primary.opacity(trimmedName.isEmpty ? 0 : 0.3), radius: 12, x: 0, y: 10)
            .disabled(trimmedName.isEmpty || isSubmitting)
            .padding(.top, 24)

            Text("建立後可從持股頁左上角隨時切換")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 42)
        .background(AppColor.background)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.hidden)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        isSubmitting = true
        Task {
            let ok = await viewModel.create(name: trimmedName, color: selectedColor.rawValue)
            isSubmitting = false
            if ok { dismiss() }
        }
    }
}

// MARK: - 快速套用 chips(可換行,fade+up stagger)

struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColor.inkSecondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(AppColor.bgTrack)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 8)
                .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.04), value: appeared)
            }
        }
        .onAppear { appeared = true }
    }
}
