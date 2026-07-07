import Foundation
import SwiftUI
import Combine

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var currentPageIndex = 0
    
    let cards = [
        ("跌了，不一定是你選錯股票", "個股回檔很多時候是受到大盤與產業板塊波動的影響，看懂波動比盲目自責更重要。"),
        ("不用懂線圖，也能看懂今天為什麼波動", "我們把複雜的技術分析和市場雜訊，翻譯成新手也能輕鬆讀懂的白話持股狀態。"),
        ("每天一張持股卡，陪你冷靜看市場", "透過早晚的情緒溫度整理與陪伴抽卡，幫助你建立安心的投資心理學。")
    ]
    
    func completeOnboarding() {
        AppPreferenceStore.shared.isOnboardingCompleted = true
        HapticManager.shared.triggerNotification(type: .success)
    }
}
