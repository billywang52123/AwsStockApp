import Foundation
import SwiftUI
import Combine

@MainActor
class UserScenarioViewModel: ObservableObject {
    @Published var selectedScenario: String? = nil
    
    let scenarios = [
        "我買了股票，但不知道該不該繼續放著",
        "我看不懂線圖和新聞，市場起伏讓我心慌",
        "股票一跌，我就開始焦慮、想一直看盤",
        "我只是想每天快速用白話知道持股發生什麼事"
    ]
    
    func selectScenario(_ scenario: String) {
        selectedScenario = scenario
        HapticManager.shared.triggerSelection()
    }
}
