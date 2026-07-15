import SwiftUI
import UIKit
import Photos

// MARK: - 15L / 15m · 分享卡片

/// 分享圖只整理可公開轉貼的內容。持股市值是唯一可選的個人金額，且預設隱藏。
struct ShareDetailRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let changePercent: Double?   // 有值時 value 用台股漲跌色

    init(label: String, value: String, changePercent: Double? = nil) {
        self.label = label
        self.value = value
        self.changePercent = changePercent
    }
}

/// 分享的是「翻開後的卡片內容」（重點句 + 數據列 / 推理鏈），不是卡背樣式。
struct ShareCardContent {
    let kind: PackCardKind
    let title: String
    let subtitle: String
    let headline: String              // 卡片重點句（數據事件 / 推論結論 / 討論熱度）
    let detailRows: [ShareDetailRow]  // 事實卡個股列、社群卡討論量列
    let steps: [String]               // 推論卡推理鏈摘要
    let source: String
    let dataDate: String
    let flashLabel: String?
    let personalValue: String

    static func make(pack: DailyPack, kind: PackCardKind) -> ShareCardContent {
        let personalValue = "我的庫存市值 \(pack.totalValueText)"
        switch kind {
        case .fact:
            let fact = pack.fact
            let sourceChip = fact.flashcard?.chip ?? fact.totalChip
            let rows = fact.stocks.prefix(3).map { stock -> ShareDetailRow in
                let close = stock.rows.first(where: { $0.label == "收盤價" })?.value ?? "—"
                return ShareDetailRow(
                    label: "\(stock.name) \(stock.symbol)",
                    value: "收盤 \(close) · \(String(format: "%+.2f%%", stock.changePercent))",
                    changePercent: stock.changePercent
                )
            }
            return ShareCardContent(
                kind: kind,
                title: "今日市場事實",
                subtitle: "收盤後可驗證數據",
                headline: fact.flashcard?.eventText
                    ?? "\(pack.holdingsCount) 檔持股的收盤數據，券商 App 都查得到",
                detailRows: rows,
                steps: [],
                source: sourceChip.source,
                dataDate: sourceChip.dataDate,
                flashLabel: fact.flashcard == nil ? nil : "閃卡 · 數據事件",
                personalValue: personalValue
            )

        case .inference:
            let inference = pack.inference
            let sourceChip = inference.steps.compactMap(\.chip).first
            return ShareCardContent(
                kind: kind,
                title: "庫存數據推論",
                subtitle: "這是判斷，不是事實",
                headline: inference.conclusion,
                detailRows: [],
                steps: inference.steps.prefix(3).map { "\($0.number). \($0.text)" },
                source: sourceChip?.source ?? "公開市場資料",
                dataDate: sourceChip?.dataDate ?? pack.dataDate,
                flashLabel: nil,
                personalValue: personalValue
            )

        case .community:
            let community = pack.communityCard
            var rows: [ShareDetailRow] = []
            if community.hasData {
                rows.append(ShareDetailRow(label: "今日討論",
                                           value: "\(community.postsToday.formatted()) 則"))
                rows.append(ShareDetailRow(label: "30 日均值",
                                           value: "\(String(format: "%.0f", community.postsBaseline)) 則"))
                if let sentiment = community.sentimentText {
                    rows.append(ShareDetailRow(label: "多空溫度", value: sentiment))
                }
            }
            return ShareCardContent(
                kind: kind,
                title: community.stockName.isEmpty ? "社群討論" : community.stockName,
                subtitle: community.stockSymbol.isEmpty ? "同學會氣氛" : community.stockSymbol,
                headline: community.hasData ? community.heatText : "目前公開討論資料不足",
                detailRows: rows,
                steps: [],
                source: community.chip?.source ?? "同學會發文統計",
                dataDate: community.chip?.dataDate ?? pack.dataDate,
                flashLabel: nil,
                personalValue: personalValue
            )
        }
    }

    var shareText: String {
        "\(title)｜\(headline)\n資料截至 \(dataDate)\n股感安心卡 · 非投資建議"
    }
}

/// 可匯出的 360×450pt 畫布，以 scale 3 輸出精確 1080×1350 px。
/// 版面沿用翻開後的卡片正面（淺色底 + 標籤 pill + 重點句 + 數據列），分享的是內容不是卡背。
struct ShareCardImage: View {
    let content: ShareCardContent
    let hidesHoldingAmount: Bool
    let includesSource: Bool

    var body: some View {
        ZStack {
            background

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1.5)
                .padding(10)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    CardTagPill(text: content.kind.tagText, bg: tagBg, fg: tagFg)
                    Spacer()
                    if let flashLabel = content.flashLabel {
                        Label(flashLabel, systemImage: "sparkles")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(colors: TrustCardColor.flashcardTag,
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                    }
                }

                Text(content.title)
                    .font(.system(size: 25, weight: .heavy, design: .serif))
                    .foregroundColor(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.top, 16)

                Text(content.subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(muted)
                    .padding(.top, 4)

                Text(content.headline)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(ink)
                    .lineSpacing(7)
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                if !content.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(content.steps, id: \.self) { step in
                            Text(step)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundColor(ink.opacity(0.85))
                                .lineSpacing(4)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 12)
                }

                if !content.detailRows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(content.detailRows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().overlay(borderColor.opacity(0.6)) }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(row.label)
                                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                    .foregroundColor(ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(row.value)
                                    .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                                    .foregroundColor(row.changePercent.map(changeColor) ?? ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 12)
                }

                if !hidesHoldingAmount {
                    Label(content.personalValue, systemImage: "lock.open.fill")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(.top, 10)
                }

                Spacer(minLength: 10)

                if includesSource {
                    Label("\(content.source) · 資料截至 \(content.dataDate)",
                          systemImage: "chart.bar.fill")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(muted)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                HStack {
                    Text("股感安心卡")
                        .fontWeight(.bold)
                    Spacer()
                    Text("現況描述 · 非投資建議")
                }
                .font(.system(size: 9.5, design: .rounded))
                .foregroundColor(muted.opacity(0.85))
                .padding(.top, 9)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
        }
        .frame(width: 360, height: 450)
        .clipped()
    }

    @ViewBuilder
    private var background: some View {
        switch content.kind {
        case .fact:
            TrustCardColor.factBg
        case .inference:
            LinearGradient(colors: TrustCardColor.inferenceBg,
                           startPoint: .top, endPoint: .bottom)
        case .community:
            LinearGradient(colors: TrustCardColor.communityBg,
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var ink: Color {
        switch content.kind {
        case .fact: return TrustCardColor.factNumber
        case .inference: return TrustCardColor.inferenceText
        case .community: return TrustCardColor.communityText
        }
    }

    private var muted: Color {
        switch content.kind {
        case .fact: return TrustCardColor.factLabelText
        case .inference: return TrustCardColor.inferenceMuted
        case .community: return TrustCardColor.communityText.opacity(0.7)
        }
    }

    private var borderColor: Color {
        switch content.kind {
        case .fact: return TrustCardColor.factBorder
        case .inference: return TrustCardColor.inferenceBorder
        case .community: return TrustCardColor.communityBorder
        }
    }

    private var tagBg: Color {
        switch content.kind {
        case .fact: return TrustCardColor.factLabelBg
        case .inference: return TrustCardColor.inferenceLabelBg
        case .community: return TrustCardColor.communityLabelBg
        }
    }

    private var tagFg: Color {
        content.kind == .fact ? TrustCardColor.factLabelText : .white
    }
}

struct ShareCardSheet: View {
    let pack: DailyPack
    let kind: PackCardKind

    @Environment(\.dismiss) private var dismiss
    @State private var hidesHoldingAmount = true
    @State private var includesSource = true
    @State private var isPreparing = false
    @State private var renderedImage: UIImage?
    @State private var showsSystemShare = false
    @State private var feedbackMessage: String?
    @State private var errorMessage: String?

    private var content: ShareCardContent { .make(pack: pack, kind: kind) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    previewCard
                    privacyCard
                    destinationCard

                    Text("分享內容為現況數據與出處，非投資建議｜資料截至 \(content.dataDate)")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(AppColor.inkFaint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(AppColor.background.ignoresSafeArea())
            .navigationTitle("分享這張卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showsSystemShare) {
            if let renderedImage {
                ActivityShareSheet(items: [renderedImage, content.shareText])
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("無法完成分享", isPresented: errorAlertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "請稍後再試。")
        }
    }

    private var previewCard: some View {
        HStack(spacing: 18) {
            ShareCardThumbnail(content: content,
                               hidesHoldingAmount: hidesHoldingAmount,
                               includesSource: includesSource)

            VStack(alignment: .leading, spacing: 8) {
                Text(content.kind.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Text("分享的是這張卡翻開後的內容；預設只保留可公開數據、出處與免責說明。")
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                    .lineSpacing(6)
                Label("輸出 1080 × 1350", systemImage: "rectangle.portrait")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColor.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 7)
    }

    private var privacyCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $hidesHoldingAmount) {
                settingLabel(icon: "eye.slash.fill", title: "隱藏我的持股金額",
                             subtitle: "預設開啟，不輸出庫存市值、成本或損益")
            }
            .tint(AppColor.primary)
            .padding(.vertical, 13)

            Divider()

            Toggle(isOn: $includesSource) {
                settingLabel(icon: "checkmark.seal.fill", title: "附出處浮水印",
                             subtitle: "讓卡片轉貼後仍能辨識資料來源與日期")
            }
            .tint(AppColor.primary)
            .padding(.vertical, 13)
        }
        .padding(.horizontal, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("分享方式")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)

            HStack(spacing: 12) {
                shareAction(icon: "square.and.arrow.up.fill", title: "更多") {
                    prepareSystemShare()
                }
                shareAction(icon: "square.and.arrow.down.fill", title: "存成圖片") {
                    saveToPhotos()
                }
                shareAction(icon: "doc.on.doc.fill", title: "複製文字") {
                    UIPasteboard.general.string = content.shareText
                    feedbackMessage = "已複製分享文字"
                    HapticManager.shared.triggerImpact(style: .light)
                }
            }

            if isPreparing {
                HStack(spacing: 8) {
                    ProgressView().tint(AppColor.primary)
                    Text("正在製作分享卡…")
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
            } else if let feedbackMessage {
                Label(feedbackMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColor.downStrong)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func settingLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundColor(AppColor.primary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Text(subtitle)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
            }
        }
    }

    private func shareAction(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColor.primaryBgTint)
                        .frame(width: 54, height: 54)
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(AppColor.primary)
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
        .accessibilityHint(title == "更多" ? "開啟系統分享選單" : "")
    }

    private func prepareSystemShare() {
        guard !isPreparing else { return }
        isPreparing = true
        feedbackMessage = nil
        Task { @MainActor in
            defer { isPreparing = false }
            guard let image = renderImage() else {
                errorMessage = "分享卡圖片產生失敗，請稍後再試。"
                return
            }
            renderedImage = image
            HapticManager.shared.triggerImpact(style: .light)
            showsSystemShare = true
        }
    }

    private func saveToPhotos() {
        guard !isPreparing else { return }
        isPreparing = true
        feedbackMessage = nil
        Task { @MainActor in
            defer { isPreparing = false }
            guard let image = renderImage() else {
                errorMessage = "分享卡圖片產生失敗，請稍後再試。"
                return
            }

            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                errorMessage = "請在系統設定允許加入照片，才能儲存分享卡。"
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                feedbackMessage = "分享卡已存入照片"
                HapticManager.shared.triggerImpact(style: .medium)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func renderImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: ShareCardImage(
                content: content,
                hidesHoldingAmount: hidesHoldingAmount,
                includesSource: includesSource
            )
        )
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

/// 預覽縮圖 = 實際輸出圖的 1/3 縮小版,所見即所得(含隱私/出處開關狀態)。
private struct ShareCardThumbnail: View {
    let content: ShareCardContent
    let hidesHoldingAmount: Bool
    let includesSource: Bool

    var body: some View {
        ShareCardImage(content: content,
                       hidesHoldingAmount: hidesHoldingAmount,
                       includesSource: includesSource)
            .scaleEffect(1.0 / 3.0)
            .frame(width: 120, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppColor.inkFaint, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(content.kind.title)分享卡預覽")
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
