import Foundation
import Combine
import SwiftUI

// MARK: - 10a 隱私儀表板(spec 05)

@MainActor
class PrivacyDashboardViewModel: ObservableObject {
    @Published var summary: PrivacySummary?
    @Published var isLoading = false
    @Published var isDeleting = false
    /// 刪除完成後逐項顯示「N 筆 ✓ 已刪除」
    @Published var deletedResult: PrivacySummary?
    @Published var errorMessage: String?

    private let container: DependencyContainer

    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
    }

    func load() async {
        isLoading = summary == nil
        errorMessage = nil
        do {
            summary = try await container.privacyService.getSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 一鍵全部刪除:伺服器當下即刪 + 本機偏好一併清空,結果逐項可見
    func deleteAll() async {
        isDeleting = true
        errorMessage = nil
        do {
            let deleted = try await container.privacyService.deleteAllData()
            AppPreferenceStore.shared.resetPrivacyPreferences()
            deletedResult = deleted
            summary = .zero
            HapticManager.shared.triggerNotification(type: .success)
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.triggerNotification(type: .error)
        }
        isDeleting = false
    }
}
