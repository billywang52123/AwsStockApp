import SwiftUI

// MARK: - 12c · 籤詩結果(直式籤詩紙 + 三欄位)+ 13c 頂部狀態條
struct FortuneResultView: View {
    let fortune: FortuneResult
    var onReplay: (() -> Void)? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // 13c 綜合狀態條(光效強度隨籤等變化的收斂版)
                FortuneTopBar(level: fortune.overallLevel, fortune: fortune)
                    .padding(.top, 8)
                    .entrance(index: 0)

                HStack {
                    Text(fortuneDateTextResult())
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                    Spacer()
                    Text("今日已抽 · 明天可再抽")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkQuaternary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(AppColor.bgTrack)
                        .clipShape(Capsule())
                }
                .padding(.top, 14)

                // 籤詩紙(紅雙框直式)
                fortunePaper
                    .padding(.top, 12)
                    .entrance(index: 1)

                Text("籤詩由 AI 依你的持股與市場資訊生成\n僅供情緒陪伴與資訊參考,不構成投資建議")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(AppColor.inkFaint)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                // 重看儀式(同一支籤,不重抽)
                if let onReplay {
                    Button {
                        HapticManager.shared.triggerSelection()
                        onReplay()
                    } label: {
                        Text("重看開籤動畫 (測試)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(AppColor.inkQuaternary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(Color.black.opacity(0.03))
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // ── 籤詩紙 ───────────────────────────────────────────────

    private var fortunePaper: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 籤頭:安心籤 · 第 N 籤 + 籤等大字
            VStack(spacing: 6) {
                Text("安心籤 · \(fortune.stickLabel)")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .kerning(2)
                    .foregroundColor(AppColor.inkTertiary)

                Text(fortune.overallLevel.label)
                    .font(.system(size: 52, weight: .heavy, design: .serif))
                    .foregroundColor(fortune.overallLevel.textColor)

                Text(fortune.levelNote)
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .kerning(1)
                    .foregroundColor(AppColor.inkSecondary)

                // 六級對照列(目前籤等高亮)
                HStack(spacing: 5) {
                    ForEach(FortuneLevel.allCases.reversed(), id: \.self) { level in
                        Text(level.label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(level == fortune.overallLevel ? .white : level.textColor.opacity(0.55))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 7)
                            .background(level == fortune.overallLevel ? level.textColor : level.bgTint.opacity(0.6))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)

            paperDivider.padding(.top, 18)

            // 欄位一:持股與狀態
            if !fortune.holdings.isEmpty {
                sectionTitle("持股與狀態")
                VStack(spacing: 9) {
                    ForEach(fortune.holdings) { holding in
                        HStack(spacing: 10) {
                            IndustryAvatar(name: holding.name, industry: "")
                                .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(holding.name)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(AppColor.inkPrimary)
                                Text(holding.comment)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(AppColor.inkTertiary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(holding.level.label)
                                .font(.system(size: 12, weight: .heavy, design: .serif))
                                .foregroundColor(holding.level.textColor)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
                                .background(holding.level.bgTint)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 18)

                paperDivider.padding(.top, 16)
            }

            // 欄位二:說明
            sectionTitle("說明")
            Text(fortune.summary)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(AppColor.inkSecondary)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.horizontal, 18)

            HStack(spacing: 8) {
                Text("今天的節奏")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
                Text(fortune.stance)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(fortune.overallLevel.textColor)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(fortune.overallLevel.bgTint)
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.top, 10)
            .padding(.horizontal, 18)

            Text(fortune.stanceNote)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .lineSpacing(5)
                .padding(.top, 4)
                .padding(.horizontal, 18)

            paperDivider.padding(.top, 16)

            // 欄位三:注意事項
            sectionTitle("注意事項")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(fortune.notices.enumerated()), id: \.offset) { _, notice in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(AppColor.amberNumber)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(notice)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.inkSecondary)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
        }
        .background(Color(hex: "FFFDF8"))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // 紅雙框:外框 + 內細框(籤詩紙語彙)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(hex: "C97F7F"), lineWidth: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: "C97F7F").opacity(0.45), lineWidth: 1)
                .padding(5)
        )
        .shadow(color: Color(hex: "786446").opacity(0.1), radius: 12, x: 0, y: 8)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text("「\(title)」")
            .font(.system(size: 14, weight: .heavy, design: .serif))
            .kerning(2)
            .foregroundColor(AppColor.inkPrimary)
            .padding(.top, 14)
            .padding(.horizontal, 18)
    }

    private var paperDivider: some View {
        Rectangle()
            .fill(Color(hex: "C97F7F").opacity(0.25))
            .frame(height: 1)
            .padding(.horizontal, 18)
    }
}

private func fortuneDateTextResult() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_TW")
    formatter.dateFormat = "M 月 d 日"
    let week = ["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: Date()) - 1]
    return "\(formatter.string(from: Date())) · 週\(week)"
}

// MARK: - 13c · 結果頁頂部狀態條(金光 glowPulse / 黑煙二態,強度隨籤等)
struct FortuneTopBar: View {
    let level: FortuneLevel
    let fortune: FortuneResult
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var subtitle: String {
        let counts = Dictionary(grouping: fortune.holdings, by: { $0.level.isAuspicious })
        let up = counts[true]?.count ?? 0
        let total = fortune.holdings.count
        if total == 0 { return "把持股加進來,籤詩會更貼近你" }
        return "\(total) 檔中 \(up) 檔偏多 · \(level.levelHint)"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if level.isAuspicious {
                    // 金光:溫暖光暈,強度隨籤等
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "FFE296").opacity(0.9), Color(hex: "E4B384").opacity(0.25)],
                                center: .center, startRadius: 2, endRadius: 24
                            )
                        )
                        .scaleEffect(pulsing && !reduceMotion ? 1.0 + 0.08 * Double(level.revealIntensity) : 0.92)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulsing)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "B0813F"))
                } else {
                    // 黑煙:低飽和灰黑,不閃爍
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "5C5850").opacity(0.5), Color(hex: "3A3733").opacity(0.15)],
                                center: .center, startRadius: 2, endRadius: 24
                            )
                        )
                        .scaleEffect(pulsing && !reduceMotion ? 1.05 : 0.95)
                        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: pulsing)
                    Image(systemName: "smoke.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "5C5850"))
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(level.label)
                        .font(.system(size: 17, weight: .heavy, design: .serif))
                        .foregroundColor(level.textColor)
                    Text(level.topBarNote)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(AppColor.inkSecondary)
                }
                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppColor.inkTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(level.bgTint.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(level.textColor.opacity(0.25), lineWidth: 1)
        )
        .onAppear { pulsing = true }
    }
}

extension FortuneLevel {
    /// 13c 副標的短語
    var levelHint: String {
        switch self {
        case .daikichi: return "大方向順風"
        case .kichi: return "整體安穩"
        case .shokichi: return "穩中帶光"
        case .shokyo: return "短線有雜音"
        case .kyo: return "今天逆風"
        case .daikyo: return "先別做決定"
        }
    }
}
