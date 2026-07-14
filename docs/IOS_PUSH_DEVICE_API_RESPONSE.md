# iOS Push Device API 回傳規格

這份文件提供給 iOS 開發者，說明 App 將 APNs device token 傳到 ECS 後，實際會收到什麼 HTTP 與 JSON 回應。

> 目前這是後端程式碼定義的 API contract。新版 ECS 部署完成後，請再用實機取得的 APNs token 做一次 runtime 驗證。

## 1. API URL

完整後端路徑：

```http
POST /api/push-devices
```

目前 iOS 專案的 `APIClient.baseURL` 已經包含 `/api`：

```swift
https://stock.wbilly.com/api
```

因此 iOS 呼叫 `APIClient` 時只需要傳：

```swift
"/push-devices"
```

不要再寫成 `/api/push-devices`，否則會變成錯誤的 `/api/api/push-devices`。

## 2. Request

```http
POST https://stock.wbilly.com/api/push-devices
Authorization: Bearer <登入後取得的 session JWT>
Content-Type: application/json
```

Xcode Development build：

```json
{
  "device_token": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "platform": "ios",
  "environment": "sandbox"
}
```

TestFlight／App Store build 將 `environment` 改成：

```json
{
  "device_token": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "platform": "ios",
  "environment": "production"
}
```

欄位限制：

| 欄位 | 必填 | 可接受內容 |
|---|---:|---|
| `device_token` | 是 | 32～512 字元；可傳純 hex，也接受 Xcode 常見的 `<ab cd ...>` 格式 |
| `platform` | 否 | 目前只能是 `ios`，預設也是 `ios` |
| `environment` | 否 | `sandbox` 或 `production`，預設為 `sandbox` |

## 3. 成功回傳：token 已存入 RDS，SNS 尚未設定

HTTP status：

```http
200 OK
```

JSON：

```json
{
  "success": true,
  "data": {
    "id": "e903f79b-ec6e-4c96-818d-f8481bfbc252",
    "platform": "ios",
    "environment": "sandbox",
    "enabled": true,
    "registration_status": "pending_sns_configuration",
    "last_registered_at": "2026-07-13T04:00:00.000000+00:00"
  },
  "message": null,
  "error": null
}
```

這個回應代表：

- APNs token 已成功寫入 RDS `push_devices` table。
- token 已與目前登入者的 `user_id` 綁定。
- AWS SNS APNs Platform Application 還沒設定，所以目前還不能透過 SNS 發送通知。
- 對 iOS 第一階段驗收來說，這是成功，不應顯示錯誤。

## 4. 成功回傳：token 已存入 RDS 且 SNS Endpoint 已建立

SNS 設定完成後，iOS 再呼叫同一支 API，HTTP status 一樣是：

```http
200 OK
```

JSON：

```json
{
  "success": true,
  "data": {
    "id": "e903f79b-ec6e-4c96-818d-f8481bfbc252",
    "platform": "ios",
    "environment": "sandbox",
    "enabled": true,
    "registration_status": "active",
    "last_registered_at": "2026-07-13T04:05:00.000000+00:00"
  },
  "message": null,
  "error": null
}
```

`active` 代表：

- token 已存入 RDS。
- SNS Platform Endpoint 已建立或更新。
- 後端可以使用該 SNS Endpoint 發送 APNs push。

## 5. 重複呼叫會回傳什麼

同一個 `environment + device_token` 重複呼叫時，後端會更新原本資料，不會新增重複裝置。

回傳仍是 `200 OK`，而且：

- `id` 維持同一筆資料的 ID。
- `last_registered_at` 更新。
- SNS 未設定時維持 `pending_sns_configuration`。
- SNS 已設定時回傳 `active`。

所以 App 每次收到 APNs token 時都可以安全地重新呼叫，不需要先判斷是否上傳過。

## 6. iOS 使用現有 APIClient 時實際拿到的物件

後端 HTTP response 有最外層 `success/data/message/error` wrapper，但現有 `APIClient.requestBody` 會先解析 wrapper，最後只回傳 `data`。

建議 model：

```swift
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
```

呼叫方式：

```swift
let body = PushDeviceRegisterRequest(
    deviceToken: apnsToken,
    environment: "sandbox"
)

let result: PushDeviceRegistration = try await APIClient.shared.requestBody(
    "/push-devices",
    method: "POST",
    body: body
)

print(result.id)
print(result.registrationStatus)
```

因為現有 `APIClient` 使用：

```swift
decoder.keyDecodingStrategy = .convertFromSnakeCase
```

所以 JSON 的 `registration_status`、`last_registered_at` 會自動對應到 Swift 的 `registrationStatus`、`lastRegisteredAt`。

## 7. iOS 應該如何處理 registration_status

```swift
switch result.registrationStatus {
case "active":
    print("裝置已完成 SNS 推播註冊")

case "pending_sns_configuration":
    // Token 已成功存進 RDS，這不是 iOS 錯誤。
    print("裝置 token 已儲存，等待後端完成 SNS 設定")

default:
    print("Unknown push registration status: \(result.registrationStatus)")
}
```

不要因為收到 `pending_sns_configuration` 而重試迴圈；下次 App 啟動或 APNs 再次回傳 token 時正常註冊即可。

## 8. 常見錯誤回傳

### 8.1 JWT 無效或過期

```http
401 Unauthorized
```

FastAPI HTTP error 格式：

```json
{
  "detail": "登入憑證無效或已過期"
}
```

現有 `APIClient` 收到 401 時會清除 `KeychainStore.shared.sessionToken`。此時 App 應讓使用者重新登入，登入完成後再上傳 token。

注意：目前 ECS 還開著 legacy `X-User-Id` 過渡模式；正式環境關閉後，沒有有效 Bearer JWT 就會收到 401。

### 8.2 device_token 太短

例如：

```json
{
  "device_token": "abc",
  "platform": "ios",
  "environment": "sandbox"
}
```

回傳：

```http
422 Unprocessable Entity
```

FastAPI 會回傳 validation error array：

```json
{
  "detail": [
    {
      "type": "string_too_short",
      "loc": ["body", "device_token"],
      "msg": "String should have at least 32 characters",
      "input": "abc",
      "ctx": {
        "min_length": 32
      }
    }
  ]
}
```

### 8.3 environment 填錯

例如傳入 `development`：

```http
422 Unprocessable Entity
```

允許值只有：

```text
sandbox
production
```

### 8.4 platform 填錯

例如傳入 `android`：

```http
422 Unprocessable Entity
```

目前允許值只有 `ios`。

### 8.5 RDS 或 SNS 發生非預期錯誤

```http
500 Internal Server Error
```

這類錯誤應記錄 log 並在稍後重試。不要在主執行緒無限重試，避免影響 App 啟動。

## 9. 查詢確認 API

iOS 或測試人員可以確認目前使用者已註冊的裝置：

```http
GET /api/push-devices
Authorization: Bearer <登入後取得的 session JWT>
```

成功回傳：

```json
{
  "success": true,
  "data": [
    {
      "id": "e903f79b-ec6e-4c96-818d-f8481bfbc252",
      "platform": "ios",
      "environment": "sandbox",
      "enabled": true,
      "registration_status": "pending_sns_configuration",
      "last_registered_at": "2026-07-13T04:00:00.000000+00:00"
    }
  ],
  "message": null,
  "error": null
}
```

如果使用者還沒有裝置：

```json
{
  "success": true,
  "data": [],
  "message": null,
  "error": null
}
```

## 10. iOS 驗收判斷

iOS 第一階段完成條件：

1. App 成功取得 APNs token。
2. `POST /push-devices` 收到 HTTP 200。
3. response 的 `success == true`。
4. `data.id` 有值。
5. `registration_status` 是 `pending_sns_configuration` 或 `active`。
6. 再呼叫 `GET /push-devices` 可以看到相同 `id`。

符合以上條件即代表「iOS token 已成功傳到 ECS 並寫入 RDS」。

