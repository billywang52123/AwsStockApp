import Combine
import SwiftUI

// MARK: - 語音輸入持股(spec 08 · 19a–19c)
//
// 19a VoiceEntryCard:新增持股頁的語音入口卡(截圖卡與手動列之間)
// 19b VoiceListeningSheet:聆聽中(裝置端轉文字、即時逐字稿、3 秒靜音自動結束)
// 19c VoiceParseResultList:AI 解析確認(原句引用、換算註記、補成本選填、低信心金色卡)

// MARK: - View Model

/// 19c 一筆可編輯的解析結果(股數/成本可改、成本選填展開)
struct VoiceDraftHolding: Identifiable {
    let id = UUID()
    let base: VoiceParsedHolding
    var sharesText: String
    var costText: String
    /// 「補上成本(選填)」展開成本輸入
    var showCostField = false

    var canAdd: Bool { base.symbol != nil }
}

@MainActor
final class VoiceInputViewModel: ObservableObject {
    enum Phase {
        case listening
        case parsing
        case result
        case failed(String)
        case denied           // 麥克風/語音權限被拒 → 導向設定或手動輸入
    }

    @Published var phase: Phase = .listening
    @Published var transcript = ""
    @Published var drafts: [VoiceDraftHolding] = []
    /// 解析中三步驟進度(0–3):聽寫完成 → AI 解析 → 對應股名股數(沿用 7b)
    @Published var parseStepsDone = 0
    @Published var isSaving = false
    @Published var saveDone = false

    let transcriber = SpeechTranscriber()
    private let container: DependencyContainer
    private var cancellables = Set<AnyCancellable>()

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
        transcriber.onAutoFinish = { [weak self] in self?.finishListening() }
        // 辨識在背景中斷(裝置端模型不可用、audio session 被搶…)時,
        // 聆聽畫面要跟著退到安撫失敗態,不能停在「我在聽」空等
        transcriber.$failure
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] failure in
                guard let self, case .listening = self.phase else { return }
                self.phase = .failed(failure.message)
            }
            .store(in: &cancellables)
    }

    var addableDrafts: [VoiceDraftHolding] { drafts.filter { $0.canAdd } }

    // MARK: 19b 聆聽

    func startListening() {
        Task {
            guard await SpeechTranscriber.requestPermissions() else {
                phase = .denied
                return
            }
            phase = .listening
            saveDone = false
            transcriber.start()
            if let failure = transcriber.failure {
                phase = .failed(failure.message)
            }
        }
    }

    /// 「說完了」/ 3 秒靜音自動結束共用
    func finishListening() {
        let text = transcriber.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcriber.stop()
        guard !text.isEmpty else {
            phase = .failed(SpeechTranscriber.Failure.recognitionFailed.message)
            return
        }
        transcript = text
        parse(text)
    }

    func cancelListening() {
        transcriber.stop()
    }

    // MARK: 解析(19b → 19c 過場)

    private func parse(_ text: String) {
        phase = .parsing
        parseStepsDone = 1  // 聽寫完成
        Task {
            do {
                let result = try await container.portfolioService.parseVoiceHoldings(text: text)
                parseStepsDone = 2  // AI 解析
                guard !result.items.isEmpty else {
                    phase = .failed(result.message ?? SpeechTranscriber.Failure.recognitionFailed.message)
                    return
                }
                transcript = result.transcript
                drafts = result.items.map {
                    VoiceDraftHolding(
                        base: $0,
                        sharesText: $0.shares.map(String.init) ?? "",
                        costText: $0.costPrice.map { c in
                            c == c.rounded() ? String(Int(c)) : String(c)
                        } ?? ""
                    )
                }
                parseStepsDone = 3  // 對應股名股數
                try? await Task.sleep(nanoseconds: 400_000_000)  // 全部完成停 0.4s 再 push
                withAnimation(.easeOut(duration: 0.3)) { phase = .result }
                HapticManager.shared.triggerSelection()
            } catch {
                // 安撫原則:不用錯誤紅、不講技術細節
                phase = .failed(SpeechTranscriber.Failure.recognitionFailed.message)
            }
        }
    }

    /// 「再說一次」:回 19b 重新錄音
    func retry() {
        drafts = []
        parseStepsDone = 0
        startListening()
    }

    // MARK: 19c 加入持股

    func addHoldings() async -> [String] {
        let targets = addableDrafts
        guard !targets.isEmpty, !isSaving else { return [] }
        isSaving = true
        var added: [String] = []
        for draft in targets {
            guard let symbol = draft.base.symbol else { continue }
            let item = PortfolioItem(
                id: UUID(),
                symbol: symbol,
                name: draft.base.name ?? symbol,
                costPrice: Double(draft.costText),
                shares: Int(draft.sharesText),
                broker: nil,
                createdAt: Date()
            )
            do {
                try await container.portfolioService.addPortfolioItem(item)
                added.append(symbol)
            } catch {
                print("Voice add holding failed: \(error)")
            }
        }
        isSaving = false
        if !added.isEmpty {
            saveDone = true
            HapticManager.shared.triggerImpact(style: .medium)
            AchievementCenter.shared.evaluate()
            try? await Task.sleep(nanoseconds: 600_000_000)  // 成功打勾停留
        }
        return added
    }
}

// MARK: - 19a 語音入口卡

struct VoiceEntryCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.triggerImpact(style: .medium)  // 19a→19b 進場 medium haptic
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 17)
                        .fill(Color(hex: "EEEEFA"))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "mic")
                                .font(.system(size: 24))
                                .foregroundColor(AppColor.primary)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("用說的加持股")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(AppColor.textPrimary)
                        Text("像「幫我加台積電兩張,成本九百八」,股數、成本 AI 都聽得懂")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(AppColor.inkTertiary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // CTA「按住開始說」(sheet 內才開始錄音,放開/說完了結束)
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 17))
                    Text("按住開始說")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AppColor.primary)
                .cornerRadius(16)
                .shadow(color: AppColor.primary.opacity(0.30), radius: 20, x: 0, y: 8)
            }
            .padding(22)
            .background(AppColor.cardBackground)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "DCDDF3"), lineWidth: 1.5)
            )
            .shadow(color: Color(hex: "786446").opacity(0.10), radius: 28, x: 0, y: 12)
            .overlay(alignment: .topTrailing) {
                Text("新")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColor.primary)
                    .clipShape(Capsule())
                    .offset(x: -14, y: -11)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 語音流程 Sheet(19b 聆聽 → 解析中 → 19c 確認)

struct VoiceHoldingsFlowView: View {
    @StateObject private var viewModel = VoiceInputViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// 「加入這 N 檔持股」完成(symbols 非空)→ 由外層收尾返回持股頁
    let onAddCompleted: ([String]) -> Void
    /// 「有漏的?手動補上」:把已解析結果帶回手動輸入頁,結果保留
    let onManualSupplement: ([VoiceDraftHolding]) -> Void

    var body: some View {
        ZStack {
            AppColor.background.edgesIgnoringSafeArea(.all)

            switch viewModel.phase {
            case .listening:
                VoiceListeningSheet(
                    transcriber: viewModel.transcriber,
                    onFinish: { viewModel.finishListening() },
                    onCancel: {
                        viewModel.cancelListening()
                        dismiss()
                    }
                )
            case .parsing:
                parsingView
            case .result:
                VoiceParseResultList(
                    viewModel: viewModel,
                    onRetry: { viewModel.retry() },
                    onManualSupplement: {
                        onManualSupplement(viewModel.drafts)
                        dismiss()
                    },
                    onAdd: {
                        Task {
                            let symbols = await viewModel.addHoldings()
                            if !symbols.isEmpty { onAddCompleted(symbols) }
                        }
                    }
                )
            case .failed(let message):
                failedView(message)
            case .denied:
                deniedView
            }
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.cancelListening() }
        .interactiveDismissDisabled(viewModel.isSaving)
    }

    // MARK: 解析中(19b → 19c 過場,沿用 7b 三步驟)

    private var parsingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .progressViewStyle(CircularProgressViewStyle(tint: AppColor.primary))

            VStack(alignment: .leading, spacing: 14) {
                parseStepRow(index: 1, title: "聽寫完成")
                parseStepRow(index: 2, title: "AI 解析語句")
                parseStepRow(index: 3, title: "對應股名與股數")
            }
            .padding(24)
            .background(AppColor.cardBackground)
            .cornerRadius(20)
            .shadow(color: Color(hex: "786446").opacity(0.06), radius: 16, x: 0, y: 6)
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func parseStepRow(index: Int, title: String) -> some View {
        let done = viewModel.parseStepsDone >= index
        return HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? AppColor.secondary : AppColor.inkFaint)
            Text(title)
                .font(.system(size: 14, weight: done ? .bold : .regular, design: .rounded))
                .foregroundColor(done ? AppColor.textPrimary : AppColor.inkTertiary)
        }
        .animation(.easeOut(duration: 0.25), value: done)
    }

    // MARK: 失敗(安撫語氣,不用錯誤紅)

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "ear")
                .font(.system(size: 44))
                .foregroundColor(AppColor.primary.opacity(0.6))
            Text(message)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 40)

            Button(action: { viewModel.retry() }) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill").font(.system(size: 15))
                    Text("再說一次").fontWeight(.bold)
                }
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppColor.primary)
                .cornerRadius(16)
            }
            .padding(.horizontal, 40)

            Button("改用手動輸入") { dismiss() }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .frame(minHeight: 44)
            Spacer()
        }
    }

    // MARK: 權限被拒(導向設定,不擋其他入口)

    private var deniedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 44))
                .foregroundColor(AppColor.inkQuaternary)
            Text("需要麥克風和語音辨識權限\n才能用說的加持股")
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(AppColor.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)

            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }) {
                Text("去設定開啟")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppColor.primary)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)

            Button("先用截圖或手動輸入") { dismiss() }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .frame(minHeight: 44)
            Spacer()
        }
    }
}

// MARK: - 19b 聆聽中

/// 直接觀察 SpeechTranscriber:逐字稿 partial result 與音量每次更新都要即時重繪
struct VoiceListeningSheet: View {
    @ObservedObject var transcriber: SpeechTranscriber
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Text("我在聽,慢慢說")
                .font(.system(size: 24, weight: .heavy, design: .serif))
                .foregroundColor(AppColor.textPrimary)
                .padding(.top, 26)

            VStack(spacing: 2) {
                Text("說股票名稱和數量就可以,想記成本也可以一起說")
                Text("例如「台積電兩張,成本九百八」")
            }
            .font(.system(size: 13, design: .rounded))
            .foregroundColor(AppColor.inkTertiary)
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            .padding(.top, 10)
            .padding(.horizontal, 24)

            MicPulseButton()
                .padding(.top, 40)

            VoiceLevelBars(level: transcriber.audioLevel)
                .padding(.top, 28)

            liveTranscriptCard
                .padding(.top, 26)
                .padding(.horizontal, 24)

            Spacer(minLength: 16)

            Button(action: {
                HapticManager.shared.triggerImpact(style: .light)
                onFinish()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                    Text("說完了")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(AppColor.inkPrimary)
                .cornerRadius(18)
            }
            .padding(.horizontal, 24)

            Text("語音在手機上轉文字,錄音不會上傳")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkFaint)
                .padding(.top, 10)
                .padding(.bottom, 16)
        }
    }

    private var liveTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("即時逐字稿")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkFaint)
                .kerning(1)

            HStack(alignment: .top, spacing: 2) {
                Text(transcriber.transcript.isEmpty
                     ? "開始說話,文字會出現在這裡…"
                     : transcriber.transcript)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(transcriber.transcript.isEmpty
                                     ? AppColor.inkFaint : AppColor.inkPrimary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                BlinkingCursor()
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(AppColor.cardBackground)
        .cornerRadius(20)
        .shadow(color: Color(hex: "786446").opacity(0.08), radius: 22, x: 0, y: 8)
    }
}

// MARK: - 19c AI 解析確認

struct VoiceParseResultList: View {
    @ObservedObject var viewModel: VoiceInputViewModel
    let onRetry: () -> Void
    let onManualSupplement: () -> Void
    let onAdd: () -> Void

    @State private var rowsAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("聽懂了,是這 \(viewModel.addableDrafts.count) 檔嗎?")
                        .font(.system(size: 28, weight: .heavy, design: .serif))
                        .foregroundColor(AppColor.textPrimary)
                        .padding(.top, 28)

                    Text("確認一下,認錯了可以直接改")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.top, 6)

                    transcriptQuoteBox
                        .padding(.top, 18)

                    VStack(spacing: 12) {
                        ForEach(viewModel.drafts.indices, id: \.self) { index in
                            VoiceHoldingRow(draft: $viewModel.drafts[index])
                                .opacity(rowsAppeared ? 1 : 0)
                                .offset(y: rowsAppeared ? 0 : 12)
                                .animation(.easeOut(duration: 0.35).delay(Double(index) * 0.06),
                                           value: rowsAppeared)
                        }
                    }
                    .padding(.top, 16)

                    // 雙選項列:再說一次 / 手動補上
                    HStack(spacing: 18) {
                        Spacer()
                        Button(action: onRetry) {
                            HStack(spacing: 5) {
                                Image(systemName: "mic.fill").font(.system(size: 15))
                                Text("再說一次")
                            }
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(AppColor.primary)
                            .frame(minHeight: 44)
                        }
                        Button(action: onManualSupplement) {
                            Text("有漏的?手動補上")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(AppColor.primary)
                                .frame(minHeight: 44)
                        }
                        Spacer()
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            // CTA
            VStack(spacing: 8) {
                Button(action: onAdd) {
                    HStack(spacing: 8) {
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        } else if viewModel.saveDone {
                            Image(systemName: "checkmark")
                        }
                        Text(viewModel.saveDone ? "已加入" : "加入這 \(viewModel.addableDrafts.count) 檔持股")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(AppColor.primary)
                    .cornerRadius(18)
                }
                .disabled(viewModel.addableDrafts.isEmpty || viewModel.isSaving || viewModel.saveDone)
                .opacity(viewModel.addableDrafts.isEmpty ? 0.4 : 1)

                Text("解析結果僅供輸入輔助,加入前請確認與實際持股一致")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(AppColor.inkFaint)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(AppColor.background)
        }
        .onAppear { rowsAppeared = true }
    }

    private var transcriptQuoteBox: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "mic")
                .font(.system(size: 15))
                .foregroundColor(AppColor.primary)
            Text("你說:「\(viewModel.transcript)」")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(Color(hex: "4A4770"))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .background(AppColor.primaryBgTint)
        .cornerRadius(16)
    }
}

// MARK: 19c 持股列(一般 / 含成本 / 未提成本 / 低信心)

private struct VoiceHoldingRow: View {
    @Binding var draft: VoiceDraftHolding
    @State private var isEditing = false
    @State private var hintAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(draft.base.isLowConfidence ? AppColor.amberIconBg : Color(hex: "EEEEFA"))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(String((draft.base.name ?? draft.base.mention).prefix(1)))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(draft.base.isLowConfidence ? AppColor.amberStrong : AppColor.primary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.base.name ?? draft.base.mention)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.textPrimary)
                    if let symbol = draft.base.symbol {
                        Text(symbol)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.inkTertiary)
                    }
                }

                Spacer()

                if !draft.base.isLowConfidence {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(draft.sharesText.isEmpty ? "股數未提到" : "\(draft.sharesText) 股")
                            .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(draft.sharesText.isEmpty ? AppColor.inkFaint : AppColor.textPrimary)
                        if !draft.costText.isEmpty {
                            Text("成本 \(draft.costText) 元/股")
                                .font(.system(size: 12, design: .rounded).monospacedDigit())
                                .foregroundColor(AppColor.inkTertiary)
                        }
                    }

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) { isEditing.toggle() }
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14))
                            .foregroundColor(AppColor.inkQuaternary)
                            .frame(width: 32, height: 32)
                    }
                }
            }

            // 鉛筆展開:股數/成本就地修改
            if isEditing {
                HStack(spacing: 10) {
                    voiceEditorField(label: "股數", placeholder: "例如 2000", keyboard: .numberPad, text: $draft.sharesText)
                    voiceEditorField(label: "成本", placeholder: "例如 980", keyboard: .decimalPad, text: $draft.costText)
                }
                .transition(.opacity)
            }

            // 卡底註記:低信心 / 換算依據 / 未提成本(進場後延遲淡入,安撫原則)
            Group {
                if draft.base.isLowConfidence {
                    Text("「\(draft.base.mention)」還對不到股票代號,重說一次或手動補上就可以")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.amberText)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(AppColor.amberIconBg)
                        .cornerRadius(10)
                } else if let note = draft.base.note {
                    Text(note)
                        .font(.system(size: 12, design: .rounded).monospacedDigit())
                        .foregroundColor(AppColor.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(AppColor.background)
                        .cornerRadius(10)
                }

                if !draft.base.isLowConfidence && draft.costText.isEmpty && !draft.showCostField && !isEditing {
                    HStack {
                        Text("沒聽到成本價")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.inkTertiary)
                        Spacer()
                        Button("補上成本(選填)") {
                            withAnimation(.easeOut(duration: 0.2)) { draft.showCostField = true }
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.primary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(AppColor.background)
                    .cornerRadius(10)
                }

                if draft.showCostField && !isEditing {
                    voiceEditorField(label: "成本", placeholder: "例如 980", keyboard: .decimalPad, text: $draft.costText)
                        .transition(.opacity)
                }
            }
            .opacity(hintAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.6), value: hintAppeared)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(draft.base.isLowConfidence ? AppColor.amberBg : AppColor.cardBackground)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(draft.base.isLowConfidence ? AppColor.amberBorder : .clear, lineWidth: 1.5)
        )
        .onAppear { hintAppeared = true }
    }

    private func voiceEditorField(label: String, placeholder: String, keyboard: UIKeyboardType, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(AppColor.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundColor(AppColor.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColor.background)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "E3DFD4"), lineWidth: 1.2)
        )
    }
}

// MARK: - 19b 元件:麥克風脈衝 / 音量波形 / 逐字稿游標

private struct MicPulseButton: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            // 外環 2 圈脈衝,錯開 0.6s
            ForEach(0..<2, id: \.self) { ring in
                Circle()
                    .fill(AppColor.primary.opacity(0.22))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulsing ? 2 : 1)
                    .opacity(pulsing ? 0 : 0.5)
                    .animation(
                        .easeOut(duration: 1.8)
                        .repeatForever(autoreverses: false)
                        .delay(Double(ring) * 0.6),
                        value: pulsing
                    )
            }

            Circle()
                .fill(AppColor.primary)
                .frame(width: 96, height: 96)
                .shadow(color: AppColor.primary.opacity(0.40), radius: 32, x: 0, y: 14)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 38))
                        .foregroundColor(.white)
                )
        }
        .onAppear { pulsing = true }
    }
}

/// 7 條音量波形,scaleY 綁實際輸入音量
private struct VoiceLevelBars: View {
    let level: CGFloat
    // 高 14–34 交錯
    private static let baseHeights: [CGFloat] = [16, 24, 32, 34, 30, 22, 14]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<Self.baseHeights.count, id: \.self) { i in
                Capsule()
                    .fill(i.isMultiple(of: 2) ? Color(hex: "9A9EE8") : AppColor.primary)
                    .frame(width: 4, height: Self.baseHeights[i])
                    .scaleEffect(y: 0.25 + 0.75 * min(level * (1 + CGFloat(i % 3) * 0.2), 1),
                                 anchor: .center)
                    .animation(.easeInOut(duration: 0.15), value: level)
            }
        }
        .frame(height: 34)
    }
}

private struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(AppColor.primary)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
