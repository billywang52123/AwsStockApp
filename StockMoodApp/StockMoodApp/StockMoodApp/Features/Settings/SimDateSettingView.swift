import SwiftUI

struct SimDateSettingView: View {
    @StateObject private var viewModel = SimDateSettingViewModel()

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            Form {
                noticeSection
                statusSection
                datePickerSection
                actionSection
            }
            .scrollContentBackground(.hidden)
            .disabled(viewModel.isLoading)
        }
        .navigationTitle("模擬日期")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .alert("無法更新模擬日期", isPresented: errorAlertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "請稍後再試。")
        }
    }

    private var noticeSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppColor.amberStrong)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("這是全域資料日期")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundColor(AppColor.textPrimary)
                    Text("套用後會同步影響所有使用者的每日卡包、個股、大盤與庫存分析。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(AppColor.amberText)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(AppColor.amberBg)
    }

    private var statusSection: some View {
        Section(header: Text("目前狀態").font(.system(.footnote, design: .rounded))) {
            if viewModel.isLoading && viewModel.status == nil {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(AppColor.primary)
                    Text("正在讀取資料日期…")
                        .foregroundColor(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else if let status = viewModel.status {
                statusRow(
                    title: "時間模式",
                    value: status.overridden ? "模擬時間" : "真實時間",
                    icon: status.overridden ? "clock.badge.exclamationmark.fill" : "clock.fill",
                    valueColor: status.overridden ? AppColor.amberStrong : AppColor.downStrong
                )
                statusRow(title: "App 採用日期", value: viewModel.displayDate(status.effectiveToday))
                statusRow(title: "模擬交易日", value: viewModel.displayDate(status.simulatedTradeDate))
                statusRow(
                    title: "實際資料日",
                    value: resolvedDataDateText(status),
                    valueColor: status.resolvedDataDate == nil ? AppColor.textSecondary : AppColor.textPrimary
                )
            } else {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Label("重新讀取目前狀態", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .foregroundColor(AppColor.primary)
            }
        }
    }

    private var datePickerSection: some View {
        Section(
            header: Text("選擇模擬日期").font(.system(.footnote, design: .rounded)),
            footer: Text("後端會將模擬交易日換算為所選日期的一年前；若當天無資料，會自動回退至最近的資料日。")
                .font(.system(.caption2, design: .rounded))
        ) {
            DatePicker(
                "模擬日期",
                selection: selectedDateBinding,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(AppColor.primary)
            .accessibilityHint("選擇套用到全 App 的模擬日期")
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                Task { await viewModel.apply() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text("套用模擬日期")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.white)
                .padding(.vertical, 8)
            }
            .listRowBackground(viewModel.canApply ? AppColor.primary : AppColor.primary.opacity(0.45))
            .disabled(!viewModel.canApply)

            Button {
                Task { await viewModel.restoreRealTime() }
            } label: {
                Label("恢復真實時間", systemImage: "arrow.counterclockwise.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .foregroundColor(AppColor.textPrimary)
            .disabled(!viewModel.canRestoreRealTime)

            if let message = viewModel.feedbackMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundColor(AppColor.downStrong)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
    }

    private func statusRow(
        title: String,
        value: String,
        icon: String? = nil,
        valueColor: Color = AppColor.textPrimary
    ) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .foregroundColor(valueColor)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            Text(title)
                .foregroundColor(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func resolvedDataDateText(_ status: SimDateStatus) -> String {
        guard status.dataAvailable else { return "資料來源不可用" }
        return viewModel.displayDate(status.resolvedDataDate)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.selectedDate },
            set: {
                viewModel.selectedDate = $0
                viewModel.clearFeedback()
            }
        )
    }
}

#Preview {
    NavigationStack {
        SimDateSettingView()
    }
}
