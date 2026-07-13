import SwiftUI

// MARK: - 9d · 匯入合併決策 ImportMergeRow(spec 04)
// 接在對帳單辨識結果之後,偵測到與現有持股重複時顯示。

struct ImportMergeView: View {
    @ObservedObject var viewModel: ImportMergeViewModel
    let onDone: () -> Void
    @State private var showReplaceAllConfirm = false
    @State private var showCustomBrokerInput = false
    @State private var customBrokerText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 大標
            Text(viewModel.duplicates.isEmpty
                 ? "確認匯入 \(viewModel.candidates.count) 檔持股"
                 : "有 \(viewModel.duplicates.count) 檔和現有持股重複")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(AppColor.inkPrimary)

            Text("先確認怎麼合併,我們才會更新紀錄;預設都幫你選好了")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .padding(.top, 4)

            sourceChip.padding(.top, 14)

            VStack(spacing: 12) {
                ForEach(viewModel.duplicates) { candidate in
                    duplicateCard(candidate)
                }
                ForEach(viewModel.newOnes) { candidate in
                    newRow(candidate)
                }
            }
            .padding(.top, 16)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(AppColor.roseStrong)
                    .padding(.top, 10)
            }

            ctaButton.padding(.top, 20)

            Text("合併只影響 App 內的紀錄,不會動到你的券商帳戶")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .confirmationDialog("取代全部會刪掉原本的分帳", isPresented: $showReplaceAllConfirm, titleVisibility: .visible) {
            Button("確定取代", role: .destructive) {
                Task { if await viewModel.submit() { onDone() } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            let lines = viewModel.replaceAllVictims.map { victim in
                "\(victim.name):" + victim.lots.map { "\($0.brokerDisplayName) \($0.shares.formatted()) 股" }.joined(separator: "、")
            }
            Text("將被刪除的分帳 — " + lines.joined(separator: ";"))
        }
        .alert("輸入券商名稱", isPresented: $showCustomBrokerInput) {
            TextField("例如 富邦證券", text: $customBrokerText)
            Button("確定") {
                let trimmed = customBrokerText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { viewModel.broker = trimmed }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 來源 chip

    private var sourceChip: some View {
        Menu {
            // 辨識到券商時,提供一鍵採用(仍是用戶主動確認的動作)
            if let detected = viewModel.detectedBroker {
                Button("採用辨識結果:\(detected)") { viewModel.broker = detected }
                Divider()
            }
            ForEach(TaiwanBrokers.common, id: \.self) { name in
                Button(name) { viewModel.broker = name }
            }
            Button("其他券商…") {
                customBrokerText = viewModel.broker ?? viewModel.detectedBroker ?? ""
                showCustomBrokerInput = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 15))
                    .foregroundColor(AppColor.primary)

                if let broker = viewModel.broker {
                    (Text("這次截圖來自 ")
                        .foregroundColor(AppColor.inkTertiary)
                     + Text(broker)
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.inkPrimary))
                        .font(.system(size: 12, design: .rounded))
                } else if let detected = viewModel.detectedBroker {
                    // 有辨識結果,但仍要用戶確認(辨識不一定準確)
                    (Text("辨識為 ")
                        .foregroundColor(AppColor.amberStrong)
                     + Text(detected)
                        .fontWeight(.bold)
                        .foregroundColor(AppColor.amberStrong)
                     + Text(",請確認來源")
                        .foregroundColor(AppColor.amberStrong))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                } else {
                    Text("辨識不出券商,請先選擇來源")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColor.amberStrong)
                }

                Text(viewModel.broker == nil ? "選券商" : "改來源")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColor.primary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    viewModel.brokerRequired ? AppColor.amberBadge : Color.clear,
                    lineWidth: 1.5
                )
            )
            .shadow(color: Color(hex: "786446").opacity(0.06), radius: 6, x: 0, y: 4)
        }
    }

    // MARK: - 重複持股卡

    private func duplicateCard(_ candidate: ImportCandidate) -> some View {
        let industry = candidate.existing?.industry ?? ""
        let style = IndustryStyle.style(for: industry)

        return VStack(alignment: .leading, spacing: 12) {
            // 第一層:頭像 + 名稱 + 白話理由
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(style.avatarBg).frame(width: 42, height: 42)
                    Text(String(candidate.name.prefix(1)))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(style.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(candidate.name) \(candidate.symbol)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkPrimary)
                    Text(viewModel.defaultReason(for: candidate))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                }
                Spacer()
            }

            // 第二層:算式盒
            formulaBox(candidate)

            // 第三層:三段選擇 MergeChoiceSegments
            HStack(spacing: 8) {
                ForEach(viewModel.segmentOptions(for: candidate), id: \.1) { option in
                    segmentButton(candidate: candidate, action: option.0, label: option.1)
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }

    @ViewBuilder
    private func formulaBox(_ candidate: ImportCandidate) -> some View {
        let action = viewModel.action(for: candidate)
        let existing = candidate.existing

        Group {
            switch action {
            case .addLot, .mergeAdd:
                // 加總型:現有 + 匯入 = 合併後
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    formulaColumn(label: "現有", value: "\(existing?.totalShares.formatted() ?? "0") 股")
                    Text("+")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                    formulaColumn(label: "匯入·\(viewModel.broker ?? "?")", value: "\(candidate.shares.formatted()) 股")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("合併後")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(AppColor.inkQuaternary)
                        Text("\(viewModel.mergedShares(for: candidate).formatted()) 股")
                            .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundColor(AppColor.inkPrimary)
                    }
                }
            case .replaceBroker, .replaceAll:
                // 取代型:舊值刪除線 → 新值 + 差額 pill
                let oldShares = action == .replaceAll
                    ? (existing?.totalShares ?? 0)
                    : (viewModel.sameBrokerLot(for: candidate)?.shares ?? 0)
                let newTotal = viewModel.mergedShares(for: candidate)
                let diff = newTotal - (existing?.totalShares ?? 0)
                HStack(spacing: 8) {
                    Text("\(oldShares.formatted()) 股")
                        .font(.system(size: 12, design: .rounded).monospacedDigit())
                        .strikethrough()
                        .foregroundColor(AppColor.inkFaint)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColor.inkQuaternary)
                    Text("\(candidate.shares.formatted()) 股")
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(AppColor.inkPrimary)
                    Spacer()
                    Text("\(diff >= 0 ? "+" : "")\(diff.formatted())")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(diff >= 0 ? AppColor.downText : AppColor.upText)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(diff >= 0 ? Color(hex: "EAF2EC") : Color(hex: "F5EAEA"))
                        .clipShape(Capsule())
                }
            case .skip:
                HStack {
                    Text("這檔先不動,維持 \(existing?.totalShares.formatted() ?? "0") 股")
                        .font(.system(size: 12, design: .rounded).monospacedDigit())
                        .foregroundColor(AppColor.inkQuaternary)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(AppColor.bgInset)
        .cornerRadius(14)
        .animation(.easeOut(duration: 0.2), value: action)
    }

    private func formulaColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(AppColor.inkQuaternary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(AppColor.inkSecondary)
        }
    }

    private func segmentButton(candidate: ImportCandidate, action: MergeAction, label: String) -> some View {
        let selected = viewModel.action(for: candidate) == action
        return Button {
            viewModel.actions[candidate.symbol] = action
            HapticManager.shared.triggerSelection()
        } label: {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(label)
                    .font(.system(size: 12, weight: selected ? .bold : .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(selected ? Color(hex: "5B5FA8") : AppColor.inkTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(selected ? Color(hex: "EEEEFA") : AppColor.background)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? AppColor.primary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: selected)
    }

    // MARK: - 無衝突新持股列

    private func newRow(_ candidate: ImportCandidate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(candidate.name) \(candidate.symbol)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Text("\(candidate.shares.formatted()) 股\(candidate.cost.map { " · 成本 \($0.trimmedString)" } ?? "")")
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundColor(AppColor.inkQuaternary)
            }
            Spacer()
            Text("新加入")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.downText)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Color(hex: "EAF2EC"))
                .clipShape(Capsule())
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            if !viewModel.replaceAllVictims.isEmpty {
                showReplaceAllConfirm = true
            } else {
                Task { if await viewModel.submit() { onDone() } }
            }
        } label: {
            Group {
                if viewModel.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("確認合併,更新 \(viewModel.affectedCount) 檔")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(AppColor.primary)
            .cornerRadius(18)
            .shadow(color: AppColor.primary.opacity(0.35), radius: 13, x: 0, y: 10)
        }
        .disabled(!viewModel.canSubmit)
        .opacity(viewModel.canSubmit ? 1 : 0.4)
    }
}
