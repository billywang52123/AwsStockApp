import Foundation
import SwiftUI
import Combine

@MainActor
class CardDrawViewModel: ObservableObject {
    @Published var cardResult: DrawCardResult? = nil
    @Published var isFlipped = false
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    private let container: DependencyContainer
    
    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }
    
    func loadCardStatus() async {
        isLoading = true
        hasError = false
        do {
            cardResult = try await container.cardDrawService.getTodayCard()
            isFlipped = cardResult != nil
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load card status failed: \(error)")
        }
        isLoading = false
    }
    
    func drawCard() async {
        isLoading = true
        hasError = false
        HapticManager.shared.triggerImpact(style: .heavy)
        do {
            let result = try await container.cardDrawService.drawTodayCard()
            cardResult = result
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isFlipped = true
            }
            HapticManager.shared.triggerNotification(type: .success)
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Draw card failed: \(error)")
        }
        isLoading = false
    }
    
    func resetCard() {
        cardResult = nil
        isFlipped = false
        UserDefaults.standard.removeObject(forKey: "com.stockmoodapp.lastDrawnCardType")
    }
}
