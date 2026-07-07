import Foundation
import Combine
import SwiftUI
import LocalAuthentication

// MARK: - 隱私與安心(spec 05 · 10c)
// 金額模糊 / Face ID 鎖持股頁 / 背景遮罩 的全 App 共用狀態。

@MainActor
final class PrivacyManager: ObservableObject {
    static let shared = PrivacyManager()

    /// 金額模糊(眼睛 toggle):全 App 同步,開 App 時套用「預設模糊」偏好
    @Published var amountsHidden: Bool

    /// Face ID 鎖開啟時,持股頁是否已解鎖(回背景即重新上鎖)
    @Published var holdingsUnlocked = false

    private init() {
        amountsHidden = AppPreferenceStore.shared.blurAmountsByDefault
    }

    var faceIDLockEnabled: Bool {
        get { AppPreferenceStore.shared.faceIDLockEnabled }
        set {
            objectWillChange.send()
            AppPreferenceStore.shared.faceIDLockEnabled = newValue
            if !newValue { holdingsUnlocked = false }
        }
    }

    var blurAmountsByDefault: Bool {
        get { AppPreferenceStore.shared.blurAmountsByDefault }
        set {
            objectWillChange.send()
            AppPreferenceStore.shared.blurAmountsByDefault = newValue
        }
    }

    /// 裝置是否支援生物辨識(不支援時設定頁顯示說明)
    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func toggleAmountsHidden() {
        amountsHidden.toggle()
        HapticManager.shared.triggerImpact(style: .light)
    }

    /// 持股頁 Face ID 解鎖;失敗可 fallback 裝置密碼
    func unlockHoldings() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "使用裝置密碼"
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "解鎖你的持股頁"
            )
            if ok {
                holdingsUnlocked = true
                HapticManager.shared.triggerNotification(type: .success)
            }
            return ok
        } catch {
            return false
        }
    }

    /// App 回背景:重新上鎖(遮罩由 SnapshotShield 處理)
    func handleEnterBackground() {
        holdingsUnlocked = false
    }
}
