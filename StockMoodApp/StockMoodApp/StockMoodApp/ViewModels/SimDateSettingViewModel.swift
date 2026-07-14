import Foundation
import Combine
import UIKit

@MainActor
final class SimDateSettingViewModel: ObservableObject {
    @Published var selectedDate = Date()
    @Published private(set) var status: SimDateStatus?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var feedbackMessage: String?
    @Published var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient? = nil) {
        self.apiClient = apiClient ?? .shared
    }

    var isBusy: Bool { isLoading || isSaving }

    var canApply: Bool {
        guard !isBusy else { return false }
        guard let status else { return true }
        return !status.overridden || apiDateString(from: selectedDate) != status.effectiveToday
    }

    var canRestoreRealTime: Bool {
        !isBusy && status?.overridden == true
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let loadedStatus = try await apiClient.getSimDate()
            update(with: loadedStatus, syncPicker: true)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func apply() async {
        guard canApply else { return }
        isSaving = true
        feedbackMessage = nil
        errorMessage = nil

        do {
            let updatedStatus = try await apiClient.setSimDate(apiDateString(from: selectedDate))
            update(with: updatedStatus, syncPicker: true)
            AppPreferenceStore.shared.shouldRegeneratePackAfterSimDateChange = true
            NotificationCenter.default.post(name: .simDateDidChange, object: updatedStatus)
            feedbackMessage = "已套用模擬日期"
            HapticManager.shared.triggerNotification(type: .success)
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.triggerNotification(type: .error)
        }

        isSaving = false
    }

    func restoreRealTime() async {
        guard canRestoreRealTime else { return }
        isSaving = true
        feedbackMessage = nil
        errorMessage = nil

        do {
            let updatedStatus = try await apiClient.clearSimDate()
            update(with: updatedStatus, syncPicker: true)
            AppPreferenceStore.shared.shouldRegeneratePackAfterSimDateChange = true
            NotificationCenter.default.post(name: .simDateDidChange, object: updatedStatus)
            feedbackMessage = "已恢復真實時間"
            HapticManager.shared.triggerNotification(type: .success)
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.triggerNotification(type: .error)
        }

        isSaving = false
    }

    func clearFeedback() {
        feedbackMessage = nil
    }

    func displayDate(_ value: String?) -> String {
        guard let value else { return "尚未解析" }
        guard let date = Self.apiDateFormatter.date(from: value) else { return value }
        return Self.displayDateFormatter.string(from: date)
    }

    private func update(with newStatus: SimDateStatus, syncPicker: Bool) {
        status = newStatus
        if syncPicker, let date = Self.apiDateFormatter.date(from: newStatus.effectiveToday) {
            selectedDate = date
        }
    }

    private func apiDateString(from date: Date) -> String {
        Self.apiDateFormatter.string(from: date)
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter
    }()
}
