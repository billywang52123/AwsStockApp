import Foundation
import SwiftUI
import Combine

@MainActor
class ReminderSettingViewModel: ObservableObject {
    @Published var enabled = true
    @Published var timeSlot: ReminderTimeSlot = .evening
    @Published var anxietyScore = true
    @Published var dailyCard = true
    @Published var volatilityAlert = false
    @Published var showPermissionAlert = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    private let container: DependencyContainer
    
    init(container: DependencyContainer? = nil) {
        self.container = container ?? .shared
        
        Task {
            await loadSettings()
        }
    }
    
    func loadSettings() async {
        hasError = false
        do {
            let setting = try await container.reminderService.getReminderSetting()
            self.enabled = setting.enabled
            self.timeSlot = setting.timeSlot
            self.anxietyScore = setting.items.anxietyScore
            self.dailyCard = setting.items.dailyCard
            self.volatilityAlert = setting.items.volatilityAlert
        } catch {
            hasError = true
            errorMessage = error.localizedDescription
            print("Load reminder settings failed: \(error)")
        }
    }
    
    func saveSettings() {
        let setting = ReminderSetting(
            enabled: enabled,
            timeSlot: timeSlot,
            items: ReminderItems(
                anxietyScore: anxietyScore,
                dailyCard: dailyCard,
                volatilityAlert: volatilityAlert
            )
        )
        
        hasError = false
        Task {
            do {
                try await container.reminderService.saveReminderSetting(setting)
                NotificationManager.shared.scheduleReminder(setting: setting)
                HapticManager.shared.triggerNotification(type: .success)
            } catch {
                hasError = true
                errorMessage = error.localizedDescription
                print("Save reminder settings failed: \(error)")
            }
        }
    }
    
    func toggleReminder(newValue: Bool) {
        if newValue {
            NotificationManager.shared.requestAuthorization { [weak self] granted in
                guard let self = self else { return }
                Task { @MainActor in
                    if granted {
                        self.enabled = true
                        self.saveSettings()
                    } else {
                        self.enabled = false
                        self.showPermissionAlert = true
                    }
                }
            }
        } else {
            self.enabled = false
            self.saveSettings()
        }
    }
    
    func sendTestNotification() {
        NotificationManager.shared.checkPermission { granted in
            Task { @MainActor in
                if granted {
                    NotificationManager.shared.triggerTestNotification()
                    HapticManager.shared.triggerNotification(type: .success)
                } else {
                    NotificationManager.shared.requestAuthorization { grantedNow in
                        Task { @MainActor in
                            if grantedNow {
                                NotificationManager.shared.triggerTestNotification()
                                HapticManager.shared.triggerNotification(type: .success)
                            } else {
                                self.showPermissionAlert = true
                            }
                        }
                    }
                }
            }
        }
    }
}
