import SwiftUI

struct ReminderSettingView: View {
    @StateObject private var viewModel = ReminderSettingViewModel()
    @ObservedObject private var privacy = PrivacyManager.shared
    @State private var showSignOutConfirm = false
    @State private var alwaysSkipPackAnimation = AppPreferenceStore.shared.alwaysSkipPackAnimation
    @State private var aiProvider = AppPreferenceStore.shared.aiProvider

    private var accountLabel: String {
        let id = AppPreferenceStore.shared.currentUserId
        if id.hasPrefix("apple-") { return "Apple 帳號" }
        if id.hasPrefix("google-") { return "Google 帳號" }
        return "訪客模式"
    }

    private var isGuest: Bool {
        AppPreferenceStore.shared.currentUserId.hasPrefix("guest-")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background
                    .edgesIgnoringSafeArea(.all)
                
                Form {
                    // 帳號與登出
                    Section(
                        header: Text("帳號").font(.system(.footnote, design: .rounded)),
                        footer: Text(isGuest
                                     ? "訪客資料綁定這台裝置,重新登入訪客即可找回。"
                                     : "登出不會刪除資料,重新登入同一帳號即可找回。")
                            .font(.system(.caption2, design: .rounded))
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundColor(AppColor.primary)
                            Text("目前登入方式")
                                .foregroundColor(AppColor.textPrimary)
                            Spacer()
                            Text(accountLabel)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundColor(AppColor.textSecondary)
                        }

                        Button {
                            showSignOutConfirm = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(AppColor.downText)
                                Text("登出")
                                    .foregroundColor(AppColor.downText)
                                    .font(.system(.body, design: .rounded))
                            }
                        }
                    }

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

                    // 18c 個人化:投資風格 / 投資習慣 + 16e 風格轉變(spec 07)
                    SettingsPersonalizationSection()
                    
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

                    // AI 分析引擎切換:Claude(AWS Bedrock,預設)/ OpenAI(回應較快)
                    Section(
                        header: Text("AI 分析引擎").font(.system(.footnote, design: .rounded)),
                        footer: Text("Claude 分析品質較穩定;OpenAI 回應速度較快。切換只影響 AI 文字生成,持股與帳號資料不受影響。")
                            .font(.system(.caption2, design: .rounded))
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "cpu.fill")
                                .foregroundColor(AppColor.primary)
                            Text("回應引擎")
                                .foregroundColor(AppColor.textPrimary)
                        }
                        Picker("回應引擎", selection: $aiProvider) {
                            Text("Claude").tag("claude")
                            Text("OpenAI(較快)").tag("openai")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden()
                        .onChange(of: aiProvider) { _, newValue in
                            AppPreferenceStore.shared.aiProvider = newValue
                            HapticManager.shared.triggerImpact(style: .light)
                            // 換引擎 = 換一份 insight 快取,先請後端預熱,
                            // 稍後進分析頁就不用等現算
                            Task {
                                let _: String? = try? await APIClient.shared.request("/insights/prewarm", method: "POST")
                            }
                        }
                    }

                    // 每日抽卡包(spec 06):總是跳過開包動畫
                    Section(
                        header: Text("每日卡包").font(.system(.footnote, design: .rounded)),
                        footer: Text("開啟後,點「開啟今日卡包」直接進入三張卡完成態,不播撕開動畫。")
                    ) {
                        Toggle("總是跳過開包動畫", isOn: $alwaysSkipPackAnimation)
                            .tint(AppColor.primary)
                            .onChange(of: alwaysSkipPackAnimation) { _, newValue in
                                AppPreferenceStore.shared.alwaysSkipPackAnimation = newValue
                            }
                    }

                    Section(
                        header: Text("資料日期").font(.system(.footnote, design: .rounded)),
                        footer: Text("檢視後端目前採用的交易資料日，或暫時切換全 App 的模擬日期。")
                            .font(.system(.caption2, design: .rounded))
                    ) {
                        NavigationLink(destination: SimDateSettingView()) {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(AppColor.amberStrong)
                                Text("模擬日期設定")
                                    .foregroundColor(AppColor.textPrimary)
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
                            
                            Toggle("今日安心籤", isOn: $viewModel.dailyCard)
                                .tint(AppColor.primary)
                                .onChange(of: viewModel.dailyCard) { _, _ in viewModel.saveSettings() }
                            
                            Toggle("重大波動提醒", isOn: $viewModel.volatilityAlert)
                                .tint(AppColor.primary)
                                .onChange(of: viewModel.volatilityAlert) { _, _ in viewModel.saveSettings() }
                        }
                    }
                    
                    // 抽籤通知(依收盤時間提醒來求籤)
                    Section(
                        header: Text("抽籤通知").font(.system(.footnote, design: .rounded)),
                        footer: Text("依收盤時間提醒你來求籤;測試期間隨時打開 App 都能抽。")
                            .font(.system(.caption2, design: .rounded))
                    ) {
                        Toggle(isOn: Binding(
                            get: { viewModel.fortuneDayClose },
                            set: { viewModel.toggleFortuneDayClose($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("日間收盤求籤")
                                Text("台灣時間下午 1:30")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(AppColor.textSecondary)
                            }
                        }
                        .tint(AppColor.primary)

                        Toggle(isOn: Binding(
                            get: { viewModel.fortuneNightClose },
                            set: { viewModel.toggleFortuneNightClose($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("夜間收盤求籤")
                                Text("次日凌晨 05:00")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(AppColor.textSecondary)
                            }
                        }
                        .tint(AppColor.primary)
                    }

                    Section(header: Text("推播功能測試").font(.system(.footnote, design: .rounded)), footer: Text("「測試通知」發送本地通知，驗證權限與顯示。「測試遠端推播」向 APNs 取得 token 並上傳後端，顯示註冊狀態（active／pending／404／401），需實機。")) {
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

                        Button(action: {
                            viewModel.sendRemotePushTest()
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundColor(AppColor.primary)
                                Text("測試遠端推播 (APNs → 後端)")
                                    .foregroundColor(AppColor.textPrimary)
                                    .font(.system(.body, design: .rounded))
                                Spacer()
                                if viewModel.remotePushTesting {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(viewModel.remotePushTesting)

                        if let result = viewModel.remotePushResult {
                            Text(result)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(AppColor.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
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
            .confirmationDialog("確定要登出嗎?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("登出", role: .destructive) {
                    HapticManager.shared.triggerImpact(style: .medium)
                    AuthService.shared.signOut()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(isGuest
                     ? "登出後回到登入頁;訪客資料留在這台裝置,重新以訪客登入即可找回。"
                     : "登出後回到登入頁;資料安全保存在雲端,重新登入即可找回。")
            }
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
