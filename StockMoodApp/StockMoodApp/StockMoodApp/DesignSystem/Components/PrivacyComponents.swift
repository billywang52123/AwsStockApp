import SwiftUI

// MARK: - 隱私共用元件(spec 05)

// MARK: 10d · TrustNote 關鍵時刻就地說明
/// 一句話說明,出現在動作發生的當下;輕、無底色,不打斷流程。
struct TrustNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13))
                .foregroundColor(AppColor.downText)
            Text(text)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(AppColor.inkTertiary)
                .lineSpacing(11 * 0.6)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: 10c · 金額模糊
/// 掛在金額 Text 上:眼睛 toggle 開啟時模糊,股名/漲跌 pill 不掛。
private struct SensitiveAmountModifier: ViewModifier {
    @ObservedObject private var privacy = PrivacyManager.shared

    func body(content: Content) -> some View {
        content
            .blur(radius: privacy.amountsHidden ? 6 : 0)
            .animation(.easeOut(duration: 0.2), value: privacy.amountsHidden)
            .accessibilityLabel(privacy.amountsHidden ? "金額已隱藏" : "")
    }
}

extension View {
    func sensitiveAmount() -> some View {
        modifier(SensitiveAmountModifier())
    }
}

/// 持股頁 nav bar 的眼睛鈕
struct AmountBlurToggle: View {
    @ObservedObject private var privacy = PrivacyManager.shared

    var body: some View {
        Button {
            privacy.toggleAmountsHidden()
        } label: {
            Image(systemName: privacy.amountsHidden ? "eye.slash" : "eye")
                .font(.system(size: 17))
                .foregroundColor(AppColor.inkTertiary)
                .frame(width: 44, height: 44, alignment: .trailing)
        }
        .accessibilityLabel(privacy.amountsHidden ? "顯示金額" : "隱藏金額")
    }
}

// MARK: 10c · SnapshotShield 背景遮罩
/// App 進背景/App Switcher 時蓋住內容,快照不外洩。永遠開啟。
struct SnapshotShield: View {
    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundColor(AppColor.primary.opacity(0.6))
                Text("內容已遮罩")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppColor.inkTertiary)
            }
        }
    }
}

// MARK: 10c · HoldingsLock Face ID 鎖持股頁
struct HoldingsLockView: View {
    @ObservedObject private var privacy = PrivacyManager.shared
    @State private var isUnlocking = false
    @State private var failed = false

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 52))
                    .foregroundColor(AppColor.primary)

                Text("用 Face ID 解鎖持股")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)

                if failed {
                    Text("沒有認證成功,再試一次就好")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(AppColor.inkTertiary)
                }

                Button {
                    unlock()
                } label: {
                    Text("解鎖")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .frame(height: 46)
                        .background(AppColor.primary)
                        .clipShape(Capsule())
                }
                .disabled(isUnlocking)
            }
        }
        .onAppear { unlock() }
    }

    private func unlock() {
        guard !isUnlocking else { return }
        isUnlocking = true
        failed = false
        Task {
            let ok = await privacy.unlockHoldings()
            isUnlocking = false
            failed = !ok
        }
    }
}
