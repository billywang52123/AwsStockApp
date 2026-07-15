import SwiftUI

/// 18a 新 Onboarding 第 1 步:投資風格測驗(可跳過),取代舊 1a-03 情境選擇。
/// 即 16a `StyleQuizView` 嵌進 onboarding 流程,onboarding 進度 1/3
/// (其後 2/3 持股輸入、3/3 AI 推薦),外加題內 N/5 子進度。
/// 跳過(右上「先跳過」或底部「跳過測驗,直接加入持股 →」)不落任何風格
/// (`styleProfile` 維持未測);完成測驗則照 16b 顯示結果後再進 2/3。
struct OnboardingStyleQuizView: View {
    /// 進 onboarding 2/3(持股輸入);跳過與測驗完成共用同一出口
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            StyleQuizView(onFinished: onContinue, onOnboardingSkip: onContinue)
        }
    }
}
