import UIKit
import Vision

// MARK: - 裝置端對帳單辨識(spec 05 · 技術層)
// 隱私優先:先用 Vision framework 在手機上辨識,成功就不上傳圖片;
// 辨識不出持股時才 fallback 到雲端 GPT(TLS + 即用即刪)。
// 解析採保守規則:同一列要同時有「像股票代號的 token」和「股數」才算一筆,
// 寧可漏也不亂猜 —— 漏了還有雲端辨識接手,且用戶匯入前都會再確認。

struct OnDeviceHolding {
    let symbol: String
    let name: String
    let shares: String
    let cost: String?
}

struct OnDeviceScanResult {
    let holdings: [OnDeviceHolding]
    let broker: String?
}

enum ReceiptTextScanner {

    static func scan(_ image: UIImage) async -> OnDeviceScanResult? {
        guard let cgImage = image.cgImage else { return nil }

        let observations: [VNRecognizedTextObservation]? = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                continuation.resume(returning: request.results as? [VNRecognizedTextObservation])
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hant", "en-US"]
            request.usesLanguageCorrection = false  // 數字與代號不要被「校正」

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }

        guard let observations, !observations.isEmpty else { return nil }
        let lines = groupIntoLines(observations)
        let holdings = lines.compactMap(parseHoldingLine)
        let broker = detectBroker(in: lines)
        return OnDeviceScanResult(holdings: dedupe(holdings), broker: broker)
    }

    // MARK: - 依 Y 座標把碎片組回「表格列」

    private static func groupIntoLines(_ observations: [VNRecognizedTextObservation]) -> [String] {
        struct Fragment {
            let text: String
            let midY: CGFloat
            let minX: CGFloat
        }
        let fragments = observations.compactMap { obs -> Fragment? in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return Fragment(text: candidate.string, midY: obs.boundingBox.midY, minX: obs.boundingBox.minX)
        }

        var rows: [[Fragment]] = []
        for fragment in fragments.sorted(by: { $0.midY > $1.midY }) {
            if var last = rows.last, let anchor = last.first,
               abs(anchor.midY - fragment.midY) < 0.012 {
                last.append(fragment)
                rows[rows.count - 1] = last
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }
    }

    // MARK: - 單列解析

    /// 台股代號:4 碼(個股)或 5–6 碼(ETF/受益證券),可帶一個尾碼字母。
    /// Swift Regex 不支援 lookbehind,改用「行首或非數字」前綴 + lookahead。
    private static let symbolPattern = /(?:^|[^\d.])(\d{4,6}[A-Z]?)(?![\d.])/

    private static func parseHoldingLine(_ line: String) -> OnDeviceHolding? {
        // 含日期樣式的列(交易明細)直接跳過,只收庫存列
        if line.contains(/\d{2,4}[\/\-]\d{1,2}[\/\-]\d{1,2}/) { return nil }

        // 候選代號:第一個 4–6 碼數字 token
        guard let symbolMatch = line.firstMatch(of: symbolPattern) else { return nil }
        let symbol = String(symbolMatch.1)

        let rest = line.replacingOccurrences(of: symbol, with: " ", options: [], range: nil)

        // 股數:帶千分位或純整數;成本:帶小數點
        var shares: Int?
        var cost: Double?
        for match in rest.matches(of: /([\d,]+\.\d+|[\d,]+)/) {
            let token = String(match.1).replacingOccurrences(of: ",", with: "")
            if token.contains(".") {
                if cost == nil, let value = Double(token), value > 0, value < 100_000 { cost = value }
            } else {
                if shares == nil, let value = Int(token), value > 0, value < 100_000_000 { shares = value }
            }
        }
        guard let shares else { return nil }

        // 名稱:列內最長的中文字串(沒有就用代號)
        let name = line.matches(of: /[\p{Han}]{2,}/)
            .map { String($0.output) }
            .max(by: { $0.count < $1.count }) ?? symbol

        return OnDeviceHolding(symbol: symbol, name: name, shares: String(shares),
                               cost: cost.map { String($0) })
    }

    private static func dedupe(_ holdings: [OnDeviceHolding]) -> [OnDeviceHolding] {
        var seen = Set<String>()
        return holdings.filter { seen.insert($0.symbol).inserted }
    }

    // MARK: - 券商偵測(9d 來源 chip)

    private static func detectBroker(in lines: [String]) -> String? {
        let text = lines.joined(separator: " ")
        return TaiwanBrokers.common.first { broker in
            text.contains(broker) || text.contains(broker.replacingOccurrences(of: "證券", with: ""))
        }
    }
}
