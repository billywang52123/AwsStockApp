import Foundation

// MARK: - API Response Wrapper
struct ApiResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let message: String?
    let error: ApiErrorDetail?
}

struct ApiErrorDetail: Codable, Error {
    let code: String
    let detail: String
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse(endpoint: String, statusCode: Int)
    case decodingError(endpoint: String, Error)
    case serverError(code: String, detail: str)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無效的 API 連線網址。"
        case .requestFailed(let err):
            return "網路連線失敗：\(err.localizedDescription)"
        case .invalidResponse(let endpoint, let statusCode):
            return "伺服器回應異常（\(endpoint) · HTTP \(statusCode)）。"
        case .decodingError(let endpoint, let err):
            return "資料解析失敗（\(endpoint)）：\(err.localizedDescription)"
        case .serverError(let code, let detail):
            return "伺服器錯誤 [\(code)]: \(detail)"
        }
    }

    typealias str = String
}

// MARK: - API Client
class APIClient {
    static let shared = APIClient()

    /// Date formats we accept from the backend, tried in order. Covers both
    /// timezone-aware ISO strings (e.g. `...+00:00` / `...Z`, produced when the
    /// server returns a freshly-written UTC datetime before it round-trips
    /// through the naive DB column) and the naive form read back from the DB.
    /// `ZZZZZ` matches both a numeric offset and `Z`.
    /// en_US_POSIX + UTC:沒鎖 locale 的 DateFormatter 會跟著裝置的 12/24
    /// 小時制與曆法設定走,部分用戶會解析失敗。
    static let dateFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",  // 帶時區的微秒(加買/賣出回傳的即時值)
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",         // 帶時區、無小數秒
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",       // naive 微秒(DB 讀回)
        "yyyy-MM-dd'T'HH:mm:ss",              // naive、無小數秒
        "yyyy-MM-dd",                          // 純日期
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }


    // Default to production; can be overridden for local development / UI tests
    // via UserDefaults key "api_base_url"(e.g. launch argument: -api_base_url http://localhost:8000/api)
    var baseURL = UserDefaults.standard.string(forKey: "api_base_url") ?? "https://st-137db68f559744aaa7b1da59a138d2aa.ecs.us-east-1.on.aws/api"
    
    private init() {}
    
    func request<T: Codable>(_ endpoint: String, method: String = "GET", body: Data? = nil, isRetry: Bool = false) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        APIClient.attachAuthHeaders(to: &request)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if statusCode == 401 {
                // Cognito access token expired? Renew with the refresh token and
                // retry once before giving up.
                if !isRetry, await CognitoAuthService.shared.refreshSession() {
                    return try await self.request(endpoint, method: method, body: body, isRetry: true)
                }
                // Session token rejected (expired / secret rotated) — drop it so
                // the next launch re-registers instead of failing forever.
                KeychainStore.shared.sessionToken = nil
            }
            throw APIError.invalidResponse(endpoint: endpoint, statusCode: statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)

            for formatter in APIClient.dateFormatters {
                if let date = formatter.date(from: dateStr) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateStr)")
        }
        
        let apiResponse: ApiResponse<T>
        do {
            apiResponse = try decoder.decode(ApiResponse<T>.self, from: data)
        } catch {
            throw APIError.decodingError(endpoint: endpoint, error)
        }

        if !apiResponse.success {
            let err = apiResponse.error ?? ApiErrorDetail(code: "UNKNOWN_ERROR", detail: "發生未知的伺服器錯誤")
            throw APIError.serverError(code: err.code, detail: err.detail)
        }

        guard let responseData = apiResponse.data else {
            throw APIError.invalidResponse(endpoint: endpoint, statusCode: httpResponse.statusCode)
        }
        
        return responseData
    }
    
    /// Attach auth headers: the session JWT (preferred) plus the legacy
    /// X-User-Id header, kept during the transition for servers/paths that
    /// don't take tokens yet.
    static func attachAuthHeaders(to request: inout URLRequest) {
        if let token = KeychainStore.shared.sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(AppPreferenceStore.shared.currentUserId, forHTTPHeaderField: "X-User-Id")
        // AI 分析引擎切換(設定頁):claude = AWS Bedrock(預設)/ openai = OpenAI GPT
        request.setValue(AppPreferenceStore.shared.aiProvider, forHTTPHeaderField: "X-AI-Provider")
    }

    /// Like request() but accepts an Encodable body and encodes it as JSON automatically.
    func requestBody<T: Codable, B: Encodable>(_ endpoint: String, method: String = "POST", body: B) async throws -> T {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(body)
        return try await request(endpoint, method: method, body: bodyData)
    }

    // MARK: - Admin Simulated Date

    func getSimDate() async throws -> SimDateStatus {
        try await request("/admin/sim-date", method: "GET")
    }

    func setSimDate(_ date: String) async throws -> SimDateStatus {
        try await requestBody(
            "/admin/sim-date",
            method: "PUT",
            body: SimDateUpdateBody(date: date)
        )
    }

    func clearSimDate() async throws -> SimDateStatus {
        try await request("/admin/sim-date", method: "DELETE")
    }
}
