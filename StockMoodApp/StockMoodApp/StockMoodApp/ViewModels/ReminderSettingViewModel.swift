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

    // 遠端推播測試(打 POST /push-devices,顯示 active / pending / 404 / 401)
    @Published var remotePushTesting = false
    @Published var remotePushResult: String?

    // 抽籤通知(日間收盤 13:30 / 夜間收盤次日 05:00,台灣時間)
    @Published var fortuneDayClose = AppPreferenceStore.shared.fortuneDayCloseNotifyEnabled
    @Published var fortuneNightClose = AppPreferenceStore.shared.fortuneNightCloseNotifyEnabled
    
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
                        // 使用者開啟推播 → 向 APNs 註冊以取得 device token 上傳後端
                        PushDeviceService.shared.registerForRemoteNotificationsIfPermitted()
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
    
    // MARK: - 抽籤通知

    func toggleFortuneDayClose(_ on: Bool) {
        setFortuneNotify(day: on, night: fortuneNightClose)
    }

    func toggleFortuneNightClose(_ on: Bool) {
        setFortuneNotify(day: fortuneDayClose, night: on)
    }

    private func setFortuneNotify(day: Bool, night: Bool) {
        // 關閉不需要權限;開啟前先要通知授權,被拒就跳權限提示
        let apply: (Bool, Bool) -> Void = { [weak self] day, night in
            guard let self else { return }
            self.fortuneDayClose = day
            self.fortuneNightClose = night
            AppPreferenceStore.shared.fortuneDayCloseNotifyEnabled = day
            AppPreferenceStore.shared.fortuneNightCloseNotifyEnabled = night
            NotificationManager.shared.scheduleFortuneReminders(dayClose: day, nightClose: night)
            HapticManager.shared.triggerNotification(type: .success)
        }

        let turningOn = (day && !fortuneDayClose) || (night && !fortuneNightClose)
        guard turningOn else {
            apply(day, night)
            return
        }
        NotificationManager.shared.requestAuthorization { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                if granted {
                    apply(day, night)
                } else {
                    // 還原 toggle 並提示去系統設定開權限
                    self.fortuneDayClose = AppPreferenceStore.shared.fortuneDayCloseNotifyEnabled
                    self.fortuneNightClose = AppPreferenceStore.shared.fortuneNightCloseNotifyEnabled
                    self.showPermissionAlert = true
                }
            }
        }
    }

    /// 測試遠端推播鏈路:向 APNs 註冊並把 token 打到後端,顯示回傳狀態。
    func sendRemotePushTest() {
        remotePushTesting = true
        remotePushResult = nil
        Task { @MainActor in
            let message = await PushDeviceService.shared.runRemotePushDiagnostic()
            self.remotePushResult = message
            self.remotePushTesting = false
            HapticManager.shared.triggerNotification(type: .success)
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
