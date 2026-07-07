import Foundation
import SwiftUI
import Combine

@MainActor
class DailyExplanationViewModel: ObservableObject {
    @Published var summary: DailySummary? = nil
    @Published var isLoading = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    private let container: DependencyContainer
    
    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }
    
    func loadSummary() async {
        isLoading = true
        hasError = false
        do {
            summary = try await container.dailySummaryService.getDailySummary()
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load summary failed: \(error)")
        }
        isLoading = false
    }
}
