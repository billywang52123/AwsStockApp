import SwiftUI

// MARK: - 10b · 你的資料存在哪裡 DataMapView(spec 05)
// 圖解式三區塊:這台手機上 / 我們的伺服器 / 永遠不會有。

struct DataMapView: View {
    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    locationCard(
                        icon: "iphone",
                        iconBg: Color(hex: "EEEEFA"),
                        iconColor: AppColor.primary,
                        title: "這台手機上",
                        items: [
                            "登入金鑰(存在 iOS Keychain,系統加密)",
                            "顯示偏好(金額模糊、Face ID 開關)",
                        ],
                        note: "登出即清空;刪除 App 就全部消失。"
                    )

                    locationCard(
                        icon: "server.rack",
                        iconBg: Color(hex: "FBEFDF"),
                        iconColor: AppColor.amberNumber,
                        title: "我們的伺服器",
                        items: [
                            "一組匿名編號(不連姓名或 Email)",
                            "持股三欄:代號・股數・均價",
                            "異動與抽卡紀錄、提醒時段",
                        ],
                        note: "用 HTTPS 加密傳輸;登入 Email 不儲存,只用來換匿名編號。隱私儀表板可一鍵全部刪除。"
                    )

                    locationCard(
                        icon: "hand.raised",
                        iconBg: Color(hex: "EAF2EC"),
                        iconColor: AppColor.downText,
                        title: "永遠不會有",
                        items: [
                            "券商帳號密碼",
                            "下單權限(我們沒接任何券商 API)",
                            "身分證件、信用卡",
                        ],
                        note: nil,
                        background: AppColor.bgInset
                    )

                    // 流程註解:截圖辨識
                    Text("對帳單截圖只用來辨識代號與股數:優先在你的手機上辨識(不上傳);需要上傳時走加密連線、辨識完即刪除、不寫入紀錄檔。")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Color(hex: "4A4770"))
                        .lineSpacing(12 * 0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(AppColor.primaryBgTint)
                        .cornerRadius(14)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("你的資料存在哪裡")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func locationCard(
        icon: String,
        iconBg: Color,
        iconColor: Color,
        title: String,
        items: [String],
        note: String?,
        background: Color = .white
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(iconBg).frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(AppColor.inkPrimary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(iconColor.opacity(0.6))
                            .frame(width: 7, height: 7)
                            .padding(.top, 5)
                        Text(item)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(AppColor.inkSecondary)
                            .lineSpacing(12 * 0.7)
                    }
                }
            }

            if let note {
                Text(note)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(AppColor.inkQuaternary)
                    .lineSpacing(11 * 0.6)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(background)
        .cornerRadius(20)
        .shadow(color: Color(hex: "786446").opacity(0.06), radius: 9, x: 0, y: 6)
    }
}
