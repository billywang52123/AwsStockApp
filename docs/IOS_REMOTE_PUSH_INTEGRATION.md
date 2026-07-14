# iOS Remote Push 串接說明

這份文件說明 iOS App 為了接收後端的 AI 個人化推播，需要修改的內容，以及目前後端已完成的 API。

## 1. 整體流程

```text
iOS App 向 Apple APNs 註冊
        ↓
Apple 回傳 APNs device token
        ↓
iOS 呼叫 POST /api/push-devices
        ↓
ECS FastAPI 從登入 JWT 判斷 user_id
        ↓
user_id + device token 存入 RDS PostgreSQL
        ↓
SNS 設定完成後，後端為 token 建立 SNS Platform Endpoint
        ↓
排程 Lambda 產生 AI 個人化內容，再經 SNS → APNs → iPhone
```

iOS **不直接呼叫 SNS**，也不需要持有 AWS Access Key。iOS 只向 APNs 取得 token，再把 token 傳給現有 ECS API。

## 2. 後端目前完成的內容

- 新增 RDS table：`push_devices`
- 新增裝置註冊、查詢、刪除 API
- token 會綁定後端從登入資訊取得的 `user_id`
- 同一裝置重複註冊採 upsert，不會一直增加重複資料
- 同一實體裝置換帳號登入時，會改綁目前登入者
- SNS 尚未設定時仍可先存 RDS，回傳 `pending_sns_configuration`
- SNS 設定完成後重新註冊，會建立／更新 SNS Endpoint，回傳 `active`
- API 不會把原始 device token 回傳給 App

## 3. iOS 必須修改的內容

### 3.1 開啟 Xcode capability

在 target 的 **Signing & Capabilities** 加入：

1. `Push Notifications`
2. `Background Modes` → 勾選 `Remote notifications`（若未來要處理背景資料或 silent push）

一般顯示通知不依賴 Background Modes，但建議現在一併設定，避免後續 AI 推播需要背景更新時再調整。

### 3.2 請求通知權限並向 APNs 註冊

現有 `NotificationManager.requestAuthorization` 只取得使用者顯示通知的授權，還需要在授權成功後呼叫：

```swift
import UIKit

NotificationManager.shared.requestAuthorization { granted in
    guard granted else { return }

    DispatchQueue.main.async {
        UIApplication.shared.registerForRemoteNotifications()
    }
}
```

建議在使用者登入成功，或使用者開啟「個人化推播」設定時執行。

### 3.3 接收 APNs device token

如果專案是 SwiftUI App lifecycle，可新增／使用 `AppDelegate`：

```swift
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()

        Task {
            do {
                try await PushDeviceService.shared.register(deviceToken: token)
            } catch {
                print("Failed to register push token: \(error)")
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("APNs registration failed: \(error)")
    }
}
```

並在 `@main App` 掛入：

```swift
@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

APNs token 可能會改變，因此不要只在第一次安裝時上傳。每次 APNs 回傳 token 時都呼叫後端註冊 API；後端已處理重複註冊。

### 3.4 新增呼叫後端的 Service

此 repo 已有 `APIClient.shared.requestBody(...)`，它會自動附加目前登入的 `Authorization: Bearer ...` 與過渡期 `X-User-Id` header，因此不需要自行操作 JWT。

```swift
import Foundation

struct PushDeviceRegisterRequest: Encodable {
    let deviceToken: String
    let platform = "ios"
    let environment: String
}

struct PushDeviceRegistration: Codable {
    let id: String
    let platform: String
    let environment: String
    let enabled: Bool
    let registrationStatus: String
    let lastRegisteredAt: Date
}

final class PushDeviceService {
    static let shared = PushDeviceService()
    private init() {}

    func register(deviceToken: String) async throws {
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif

        let body = PushDeviceRegisterRequest(
            deviceToken: deviceToken,
            environment: environment
        )

        let result: PushDeviceRegistration = try await APIClient.shared.requestBody(
            "/push-devices",
            method: "POST",
            body: body
        )

        print("Push registration status: \(result.registrationStatus)")
    }
}
```

注意：現有 `APIClient.baseURL` 已包含 `/api`，所以 endpoint 是 `/push-devices`，不是 `/api/push-devices`。

### 3.5 登入時機

裝置註冊 API 必須能識別登入者。建議流程：

1. App 完成登入並取得後端 session token。
2. 請求通知權限。
3. 呼叫 `registerForRemoteNotifications()`。
4. 在 `didRegisterForRemoteNotificationsWithDeviceToken` 將 token 傳到後端。

如果 APNs 先回傳 token、登入尚未完成，可以先暫存在 Keychain／UserDefaults，登入完成後再呼叫 API。

## 4. API Contract

### 註冊或更新裝置

```http
POST /api/push-devices
Authorization: Bearer <目前登入 token>
Content-Type: application/json
```

```json
{
  "device_token": "64-character-or-longer-apns-token",
  "platform": "ios",
  "environment": "sandbox"
}
```

成功回應：

```json
{
  "success": true,
  "data": {
    "id": "e903f79b-ec6e-4c96-818d-f8481bfbc252",
    "platform": "ios",
    "environment": "sandbox",
    "enabled": true,
    "registration_status": "pending_sns_configuration",
    "last_registered_at": "2026-07-13T04:00:00.000000Z"
  },
  "message": null,
  "error": null
}
```

`registration_status`：

- `pending_sns_configuration`：token 已存 RDS，但 AWS SNS APNs Platform Application 尚未設定。
- `active`：token 已存 RDS，而且 SNS Endpoint 已建立或更新。

### 查詢目前使用者的裝置

```http
GET /api/push-devices
Authorization: Bearer <目前登入 token>
```

### 解除裝置註冊

```http
DELETE /api/push-devices/{device_id}
Authorization: Bearer <目前登入 token>
```

登出時可呼叫 DELETE，避免共用裝置登出後仍收到前一位使用者的個人化通知。App 需要保存 POST 回傳的 `device_id`，或先用 GET 找到目前裝置。

## 5. Sandbox 與 Production

| App 來源 | environment | SNS/APNs 類型 |
|---|---|---|
| Xcode Development build | `sandbox` | APNS_SANDBOX |
| TestFlight | `production` | APNS |
| App Store | `production` | APNS |

Sandbox token 與 Production token 不能混用。若環境填錯，token 仍可能成功存入 RDS，但正式送出通知時會失敗。

## 6. 驗收方式

### 第一階段：只驗證 token 存入 RDS

1. 使用真實 iPhone 執行 App（Simulator 的行為與 entitlement 需另外確認，Hackathon 建議直接用實機）。
2. 登入 App。
3. 同意通知權限。
4. 確認 Xcode console 有取得 token，API 回傳成功。
5. 後端回傳 `pending_sns_configuration` 是可接受結果，代表 RDS 儲存已成功。
6. 再呼叫 `GET /api/push-devices`，應看見該裝置。
7. 重複啟動／註冊不應產生多筆相同裝置。

### 第二階段：驗證 SNS → APNs 實際推播

等後端完成 SNS Platform Application、APNs `.p8` credential 與推播 Lambda 後：

1. App 再註冊一次，狀態應為 `active`。
2. 從 SNS 或測試 Lambda 發送測試訊息。
3. App 在前景、背景、鎖屏狀態各測一次。
4. 登出並刪除 device registration 後，不應再收到該帳號的個人化推播。

## 7. 目前尚未完成／不在 iOS 這次修改範圍

- AWS SNS APNs Platform Application 的正式設定
- AI 個人化內容產生 Lambda
- EventBridge 排程
- 批次查詢使用者持股與產生通知內容
- 從 Lambda 經 SNS 發送 push payload
- App 點擊通知後的 deep link／指定頁面導向

iOS 這一階段先完成「取得 APNs token → 傳給 ECS API → 確認 RDS 有資料」即可。

