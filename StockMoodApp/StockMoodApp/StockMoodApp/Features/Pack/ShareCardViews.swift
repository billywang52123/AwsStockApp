import SwiftUI
import UIKit
import Photos

// MARK: - 15L / 15m · 分享卡片

/// 分享圖只整理可公開轉貼的內容。持股市值是唯一可選的個人金額，且預設隱藏。
struct ShareCardContent {
    let kind: PackCardKind
    let title: String
    let subtitle: String
    let primaryValue: String
    let summary: String
    let source: String
    let dataDate: String
    let flashLabel: String?
    let personalValue: String

    static func make(pack: DailyPack, kind: PackCardKind) -> ShareCardContent {
        switch kind {
        case .fact:
            let flashEvent = pack.fact.flashcard?.eventText
            let stock = pack.fact.stocks.first(where: { flashEvent?.contains($0.name) == true })
                ?? pack.fact.stocks.first
            let publicRow = stock?.rows.first(where: { $0.label == "收盤價" }) ?? stock?.rows.first
            let sourceChip = publicRow?.chip ?? pack.fact.flashcard?.chip ?? pack.fact.totalChip
            let summary: String
            if let event = flashEvent {
                summary = event
            } else if let stock, let publicRow {
                summary = "\(stock.name) \(publicRow.label) \(publicRow.value)"
            } else {
                summary = "今日公開市場資料整理"
            }
            return ShareCardContent(
                kind: kind,
                title: stock?.name ?? "今日市場事實",
                subtitle: stock?.symbol ?? "可驗證數據",
                primaryValue: publicRow?.value ?? "資料卡",
                summary: summary,
                source: sourceChip.source,
                dataDate: sourceChip.dataDate,
                flashLabel: pack.fact.flashcard == nil ? nil : "閃卡 · 數據事件",
                personalValue: "我的庫存市值 \(pack.totalValueText)"
            )

        case .inference:
            let sourceChip = pack.inference.steps.compactMap(\.chip).first
            return ShareCardContent(
                kind: kind,
                title: "庫存數據推論",
                subtitle: "這是判斷，不是事實",
                primaryValue: "AI 推論",
                summary: pack.inference.conclusion,
                source: sourceChip?.source ?? "公開市場資料",
                dataDate: sourceChip?.dataDate ?? pack.dataDate,
                flashLabel: nil,
                personalValue: "我的庫存市值 \(pack.totalValueText)"
            )

        case .community:
            let community = pack.communityCard
            let sourceChip = community.chip
            let summary = community.hasData
                ? [community.heatText, community.sentimentText].compactMap { $0 }.joined(separator: " · ")
                : "目前公開討論資料不足"
            return ShareCardContent(
                kind: kind,
                title: community.stockName.isEmpty ? "社群討論" : community.stockName,
                subtitle: community.stockSymbol.isEmpty ? "同學會氣氛" : community.stockSymbol,
                primaryValue: community.hasData ? "\(community.postsToday.formatted()) 則" : "資料不足",
                summary: summary,
                source: sourceChip?.source ?? "同學會發文統計",
                dataDate: sourceChip?.dataDate ?? pack.dataDate,
                flashLabel: nil,
                personalValue: "我的庫存市值 \(pack.totalValueText)"
            )
        }
    }

    var shareText: String {
        "\(title)｜\(summary)\n資料截至 \(dataDate)\n股感安心卡 · 非投資建議"
    }
}

/// 可匯出的 360×450pt 畫布，以 scale 3 輸出精確 1080×1350 px。
struct ShareCardImage: View {
    let content: ShareCardContent
    let hidesHoldingAmount: Bool
    let includesSource: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: backgroundGradient,
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            AngularGradient(
                colors: [TrustCardColor.packTrim.opacity(0.26), .clear,
                         accentColor.opacity(0.22), .clear,
                         TrustCardColor.packTrim.opacity(0.26)],
                center: .center
            )
            .scaleEffect(1.35)
            .rotationEffect(.degrees(22))

            Circle()
                .fill(accentColor.opacity(0.34))
                .frame(width: 250, height: 250)
                .blur(radius: 48)
                .offset(x: 118, y: -178)

            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .strokeBorder(TrustCardColor.packTrimDark, lineWidth: 4)
                .padding(12)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(TrustCardColor.packTrim.opacity(0.78), lineWidth: 1.5)
                .padding(18)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
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
                    Spacer()
                    Text(content.kind.tagText)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 14)

                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(colors: [accentColor.opacity(0.55), .clear],
                                               center: .center, startRadius: 8, endRadius: 65)
                            )
                            .frame(width: 130, height: 130)
                        Circle()
                            .strokeBorder(TrustCardColor.packTrim.opacity(0.72), lineWidth: 1.5)
                            .frame(width: 82, height: 82)
                        Circle()
                            .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                            .frame(width: 68, height: 68)
                        Text(content.kind.emblemGlyph)
                            .font(.system(size: 34, weight: .heavy, design: .serif))
                            .foregroundColor(.white)
                            .shadow(color: accentColor, radius: 12)
                    }
                    Spacer()
                }

                Text(content.title)
                    .font(.system(size: 28, weight: .heavy, design: .serif))
                    .foregroundColor(TrustCardColor.packTitleInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(content.subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.62))
                    .padding(.top, 4)

                Text(content.primaryValue)
                    .font(.system(size: 38, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.top, 12)

                Text(content.summary)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.84))
                    .lineSpacing(6)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 8)

                if !hidesHoldingAmount {
                    Label(content.personalValue, systemImage: "lock.open.fill")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.10))
                        .clipShape(Capsule())
                        .padding(.top, 10)
                }

                Spacer(minLength: 10)

                if includesSource {
                    Label("\(content.source) · 資料截至 \(content.dataDate)",
                          systemImage: "chart.bar.fill")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                HStack {
                    Text("股感安心卡")
                        .fontWeight(.bold)
                    Spacer()
                    Text("現況描述 · 非投資建議")
                }
                .font(.system(size: 9.5, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
                .padding(.top, 9)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
        }
        .frame(width: 360, height: 450)
        .clipped()
    }

    private var backgroundGradient: [Color] {
        switch content.kind {
        case .fact: return TrustCardColor.cardBackFact
        case .inference: return TrustCardColor.cardBackInference
        case .community: return TrustCardColor.cardBackCommunity
        }
    }

    private var accentColor: Color {
        switch content.kind {
        case .fact: return TrustCardColor.cardBackEmblemFact
        case .inference: return TrustCardColor.cardBackEmblemInference
        case .community: return TrustCardColor.cardBackEmblemCommunity
        }
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
            ShareCardThumbnail(content: content)

            VStack(alignment: .leading, spacing: 8) {
                Text(content.kind.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Text("分享的是卡片樣式；預設只保留可公開數據、出處與免責說明。")
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

private struct ShareCardThumbnail: View {
    let content: ShareCardContent

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TrustCardColor.packTrim.opacity(0.75), lineWidth: 1.5)
                .padding(5)
            VStack(spacing: 8) {
                Image(systemName: content.flashLabel == nil ? "sparkles" : "sparkles.rectangle.stack.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TrustCardColor.packTrim)
                Text(content.kind.emblemGlyph)
                    .font(.system(size: 28, weight: .heavy, design: .serif))
                    .foregroundColor(.white)
                Text(content.title)
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(8)
        }
        .frame(width: 104, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(content.kind.title)分享卡預覽")
    }

    private var gradient: [Color] {
        switch content.kind {
        case .fact: return TrustCardColor.cardBackFact
        case .inference: return TrustCardColor.cardBackInference
        case .community: return TrustCardColor.cardBackCommunity
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
