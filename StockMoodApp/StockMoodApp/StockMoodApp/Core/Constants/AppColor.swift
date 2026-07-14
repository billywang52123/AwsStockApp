import SwiftUI

struct AppColor {
    static let background = Color(hex: "F7F4EE")      // Option 1a: Soft warm beige
    static let primary = Color(hex: "7B7FD4")         // Option 1a: Gentle lavender/blue-purple
    static let secondary = Color(hex: "6E9A7F")       // Option 1a: Soft sage green
    static let warning = Color(hex: "E4B384")         // Option 1a: Light peach orange
    static let danger = Color(hex: "D47B7B")          // Option 1a: Soft muted red
    static let textPrimary = Color(hex: "3A3733")     // Option 1a: Dark warm charcoal
    static let textSecondary = Color(hex: "8A857C")   // Option 1a: Medium warm gray
    static let cardBackground = Color.white           // Clean pure white

    // MARK: - 方向 A 暖陽米杏 Design Tokens(docs/uiux/specs/00-通用規格)

    // 基底
    static let bgInset = Color(hex: "FAF8F3")         // 卡內註解盒
    static let bgTrack = Color(hex: "F1EDE3")         // 進度軌道、灰 pill
    static let inkPrimary = Color(hex: "3A3733")
    static let inkSecondary = Color(hex: "5C5850")
    static let inkTertiary = Color(hex: "8A857C")
    static let inkQuaternary = Color(hex: "A9A49B")
    static let inkFaint = Color(hex: "B4AFA5")

    // 主色
    static let primaryBgTint = Color(hex: "F1F1FB")   // 白話盒底
    static let gradientCardTop = Color(hex: "787CD0") // 漸層卡 150°
    static let gradientCardBottom = Color(hex: "5B5FA8")

    // 漲跌/多空(台股慣例:紅=多、綠=空,降飽和)
    static let upText = Color(hex: "C97F7F")
    static let upStrong = Color(hex: "B0605C")
    static let upBgTint = Color(hex: "F5E3E3")
    static let downText = Color(hex: "6E9A7F")
    static let downStrong = Color(hex: "5F8A70")
    static let downBgTint = Color(hex: "E4EEE7")
    static let neutralText = Color(hex: "8A857C")
    static let neutralBgTint = Color(hex: "F1EDE3")
    static let pnlOnGradient = Color(hex: "FFCFC5")   // 漸層卡上的損益正值

    // 警示 rose(安撫色階)
    static let roseBg = Color(hex: "FAF0F0")
    static let roseBorder = Color(hex: "E8CFCF")
    static let roseIconBg = Color(hex: "F5E3E3")
    static let roseText = Color(hex: "8A6A6A")
    static let roseBadge = Color(hex: "C97F7F")
    static let roseStrong = Color(hex: "B0605C")

    // 警示 amber
    static let amberBg = Color(hex: "FDF6E9")
    static let amberBorder = Color(hex: "ECD9B8")
    static let amberIconBg = Color(hex: "FBEFDF")
    static let amberText = Color(hex: "96794F")
    static let amberStrong = Color(hex: "B0813F")
    static let amberBadge = Color(hex: "E4B384")
    static let amberNumber = Color(hex: "D9A264")

    // 分數
    static let riskScore = Color(hex: "D9A264")
    static let anxietyScore = Color(hex: "7B7FD4")

    // 觀察清單(spec 05 · tokens.color.watchlist)
    static let watchScoreBg = Color(hex: "FDF9F0")
    static let watchScoreBorder = Color(hex: "EEDFC2")
    static let watchScoreStrong = Color(hex: "B0813F")
    static let watchGradientTop = Color(hex: "E0B072")
    static let watchGradientBottom = Color(hex: "C08F4F")
    static let watchStarBadgeBg = Color(hex: "FBEFDF")
    static let watchStarIcon = Color(hex: "D9A264")
    static let watchStatusPillBg = Color(hex: "FBEFDF")
    static let watchStatusPillText = Color(hex: "B0813F")
}

// MARK: - 每日抽卡包 + AI 信任系統色票(spec 06 · tokens.color.trustCard)
struct TrustCardColor {
    // 卡包封面(藍紫漸層 165°)
    static let packGradient = [Color(hex: "8B8FE0"), Color(hex: "6C70C4"), Color(hex: "54589E")]
    static let packGlow = Color(hex: "54589E").opacity(0.35)

    // 事實卡:灰底冷靜、等寬數字
    static let factBg = Color(hex: "F2F3F5")
    static let factBorder = Color(hex: "E2E4E9")
    static let factLabelBg = Color(hex: "E2E4E9")
    static let factLabelText = Color(hex: "5B5F68")
    static let factNumber = Color(hex: "3A3D45")

    // 推論卡:藍紫漸層 + 「AI 推論」標籤
    static let inferenceBg = [Color(hex: "F0F3FD"), Color(hex: "E4E9FB")]
    static let inferenceBorder = Color(hex: "B9C4EE")
    static let inferenceLabelBg = Color(hex: "5E6FD8")
    static let inferenceText = Color(hex: "2E3560")
    static let inferenceStepNumber = Color(hex: "3C4370")
    static let inferenceChipBg = Color(hex: "5E6FD8").opacity(0.10)
    static let inferenceChipBorder = Color(hex: "C3CCF2")
    static let inferenceChipText = Color(hex: "4E5CB8")
    static let inferenceMuted = Color(hex: "8A93B8")

    // 陪伴卡:暖色手寫感
    static let companionBg = [Color(hex: "FBF3E6"), Color(hex: "F4E6CE")]
    static let companionBorder = Color(hex: "EAD9B8")
    static let companionLabelBg = Color(hex: "C98A4A")
    static let companionText = Color(hex: "6A5232")

    // 出處 chip
    static let sourceChipBg = Color(hex: "E8E9EE")
    static let sourceChipBorder = Color(hex: "D8DAE1")
    static let sourceChipText = Color(hex: "5B5F68")

    // 閃卡五色流光環
    static let flashcardRing = [Color(hex: "7B7FD4"), Color(hex: "5AC8FA"), Color(hex: "9DBFAA"),
                                Color(hex: "E4B384"), Color(hex: "D08C8C"), Color(hex: "7B7FD4")]
    static let flashcardTag = [Color(hex: "E4B384"), Color(hex: "D08C8C")]

    // 15k 誠實度對帳
    static let honestyMet = Color(hex: "6E9A7F")
    static let honestyMiss = Color(hex: "B4AFA5")
    static let metRowBg = Color(hex: "F4F7F4")     // 應驗列偏綠系
    static let missRowBg = Color(hex: "F7F5F0")    // 未發生列中性(不用紅色)

    // 開包深色舞台
    static let darkPackBg = [Color(hex: "2B2850"), Color(hex: "1B1A33"), Color(hex: "121124")]
    static let darkSkipPillBg = Color.white.opacity(0.10)
    static let darkSkipPillBorder = Color.white.opacity(0.22)
}

// MARK: - 產業配色(曝險 bar、頭像、權重 bar 共用)
struct IndustryStyle {
    let color: Color
    let avatarBg: Color

    static func style(for industry: String) -> IndustryStyle {
        if industry.contains("半導體") {
            return IndustryStyle(color: Color(hex: "7B7FD4"), avatarBg: Color(hex: "EEEEFA"))
        }
        if industry.contains("ETF") || industry.contains("指數") {
            return IndustryStyle(color: Color(hex: "6E9A7F"), avatarBg: Color(hex: "EAF2EC"))
        }
        if industry.contains("IC") {
            return IndustryStyle(color: Color(hex: "A493D9"), avatarBg: Color(hex: "F0EBF8"))
        }
        if industry.contains("電子") || industry.contains("電腦") || industry.contains("光電") || industry.contains("通信") {
            return IndustryStyle(color: Color(hex: "E4B384"), avatarBg: Color(hex: "FBEFDF"))
        }
        if industry.contains("金融") || industry.contains("金控") || industry.contains("保險") || industry.contains("銀行") {
            return IndustryStyle(color: Color(hex: "C48181"), avatarBg: Color(hex: "F5EAEA"))
        }
        return IndustryStyle(color: Color(hex: "8A857C"), avatarBg: Color(hex: "F1EDE3"))
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 1)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
