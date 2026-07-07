import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func checkPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }
    
    func scheduleReminder(setting: ReminderSetting) {
        // Cancel existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        guard setting.enabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "股票情緒陪伴"
        content.sound = .default
        
        var messageParts: [String] = []
        if setting.items.anxietyScore {
            messageParts.append("今日持股焦慮分數已更新")
        }
        if setting.items.dailyCard {
            messageParts.append("來抽今日陪伴卡")
        }
        if setting.items.volatilityAlert {
            messageParts.append("留意您的持股大幅波動")
        }
        
        content.body = messageParts.isEmpty ? "快來看看今天持股的白話情緒分析吧！" : messageParts.joined(separator: "，") + "！"
        
        var dateComponents = DateComponents()
        // Morning: 08:30, Noon: 12:30, AfterMarket: 14:00, Evening: 20:00
        switch setting.timeSlot {
        case .morning:
            dateComponents.hour = 8
            dateComponents.minute = 30
        case .noon:
            dateComponents.hour = 12
            dateComponents.minute = 30
        case .afterMarket:
            dateComponents.hour = 14
            dateComponents.minute = 0
        case .evening:
            dateComponents.hour = 20
            dateComponents.minute = 0
        }
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "com.stockmoodapp.dailyreminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule daily reminder: \(error)")
            } else {
                print("Daily reminder scheduled successfully for \(setting.timeSlot.rawValue)")
            }
        }
    }
    
    func triggerTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "股票情緒陪伴 (測試推播)"
        content.body = "📊 今日持股焦慮分數已更新，快來看看你的今日陪伴卡吧！"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(identifier: "com.stockmoodapp.testreminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to trigger test notification: \(error)")
            } else {
                print("Test notification triggered successfully")
            }
        }
    }
}
