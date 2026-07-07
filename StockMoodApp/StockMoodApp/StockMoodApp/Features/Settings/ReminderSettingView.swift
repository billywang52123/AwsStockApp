import SwiftUI

struct ReminderSettingView: View {
    @StateObject private var viewModel = ReminderSettingViewModel()
    @ObservedObject private var privacy = PrivacyManager.shared

    var body: some View {
        NavigationView {
            ZStack {
                AppColor.background
                    .edgesIgnoringSafeArea(.all)
                
                Form {
                    Section(header: Text("投資情緒成就").font(.system(.footnote, design: .rounded))) {
                        NavigationLink(destination: AchievementListView()) {
                            HStack(spacing: 10) {
                                Image(systemName: "crown.fill")
                                    .foregroundColor(AppColor.primary)
                                Text("我的冷靜成就")
                                    .foregroundColor(AppColor.textPrimary)
                            }
                        }
                    }
                    
                    // 10a–10c 隱私與安心(spec 05)
                    Section(
                        header: Text("隱私與安心").font(.system(.footnote, design: .rounded)),
                        footer: Text("我們有什麼、沒有什麼,3 秒看完。").font(.system(.caption2, design: .rounded))
                    ) {
                        NavigationLink(destination: PrivacyDashboardView()) {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(AppColor.downText)
                                Text("隱私儀表板")
                                    .foregroundColor(AppColor.textPrimary)
                            }
                        }

                        NavigationLink(destination: DataMapView()) {
                            HStack(spacing: 10) {
                                Image(systemName: "map.fill")
                                    .foregroundColor(AppColor.primary)
                                Text("你的資料存在哪裡")
                                    .foregroundColor(AppColor.textPrimary)
                            }
                        }

                        Toggle("開啟 App 時金額預設模糊", isOn: Binding(
                            get: { privacy.blurAmountsByDefault },
                            set: { privacy.blurAmountsByDefault = $0 }
                        ))
                        .tint(AppColor.primary)

                        if privacy.biometricsAvailable {
                            Toggle("進入持股頁需要 Face ID", isOn: Binding(
                                get: { privacy.faceIDLockEnabled },
                                set: { privacy.faceIDLockEnabled = $0 }
                            ))
                            .tint(AppColor.primary)
                        } else {
                            HStack {
                                Text("Face ID 鎖")
                                    .foregroundColor(AppColor.textSecondary)
                                Spacer()
                                Text("此裝置未設定生物辨識")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(AppColor.textSecondary.opacity(0.7))
                            }
                        }
                    }

                    Section(header: Text("推播提醒設定").font(.system(.footnote, design: .rounded))) {
                        Toggle("啟用每日提醒", isOn: Binding(
                            get: { viewModel.enabled },
                            set: { viewModel.toggleReminder(newValue: $0) }
                        ))
                        .tint(AppColor.primary)
                        
                        if viewModel.enabled {
                            Picker("提醒時段", selection: $viewModel.timeSlot) {
                                Text("開盤前 (08:30)").tag(ReminderTimeSlot.morning)
                                Text("午間休息 (12:30)").tag(ReminderTimeSlot.noon)
                                Text("收盤後 (14:00)").tag(ReminderTimeSlot.afterMarket)
                                Text("晚間整理 (20:00)").tag(ReminderTimeSlot.evening)
                            }
                            .pickerStyle(MenuPickerStyle())
                            .onChange(of: viewModel.timeSlot) { _, _ in
                                viewModel.saveSettings()
                            }
                        }
                    }
                    
                    if viewModel.enabled {
                        Section(header: Text("提醒內容選擇").font(.system(.footnote, design: .rounded)), footer: Text("系統將根據您勾選的項目，在設定時段發送對應的通知。")) {
                            Toggle("今日持股焦慮分數", isOn: $viewModel.anxietyScore)
                                .tint(AppColor.primary)
                                .onChange(of: viewModel.anxietyScore) { _, _ in viewModel.saveSettings() }
                            
                            Toggle("今日情緒陪伴卡", isOn: $viewModel.dailyCard)
                                .tint(AppColor.primary)
                                .onChange(of: viewModel.dailyCard) { _, _ in viewModel.saveSettings() }
                            
                            Toggle("重大波動提醒", isOn: $viewModel.volatilityAlert)
                                .tint(AppColor.primary)
                                .onChange(of: viewModel.volatilityAlert) { _, _ in viewModel.saveSettings() }
                        }
                    }
                    
                    Section(header: Text("推播功能測試").font(.system(.footnote, design: .rounded)), footer: Text("點擊將在 1 秒後發送一則本地測試通知，可用於驗證通知權限與顯示效果。")) {
                        Button(action: {
                            viewModel.sendTestNotification()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundColor(AppColor.primary)
                                Text("傳送測試通知 (1秒後)")
                                    .foregroundColor(AppColor.textPrimary)
                                    .font(.system(.body, design: .rounded))
                            }
                        }
                    }
                    
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Text("StockMood App MVP")
                                    .font(.system(.footnote, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(AppColor.textSecondary)
                                Text("內容僅供資訊參考，不構成投資建議。")
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundColor(AppColor.textSecondary.opacity(0.8))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("設定")
            .alert(isPresented: $viewModel.showPermissionAlert) {
                Alert(
                    title: Text("通知權限不足"),
                    message: Text("請前往 iOS [設定] -> [通知] 啟用 StockMood 的通知權限，才能正常收到提醒。"),
                    dismissButton: .default(Text("好的"))
                )
            }
        }
    }
}
