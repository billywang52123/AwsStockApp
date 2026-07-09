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
    
    // Default to production; can be overridden for local development / UI tests
    // via UserDefaults key "api_base_url"(e.g. launch argument: -api_base_url http://localhost:8000/api)
    var baseURL = UserDefaults.standard.string(forKey: "api_base_url") ?? "https://stock.wbilly.com/api"
    
    private init() {}
    
    func request<T: Codable>(_ endpoint: String, method: String = "GET", body: Data? = nil) async throws -> T {
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
                // Session token rejected (expired / secret rotated) — drop it so
                // the next launch re-registers instead of failing forever.
                KeychainStore.shared.sessionToken = nil
            }
            throw APIError.invalidResponse(endpoint: endpoint, statusCode: statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Handle Python's ISO dates or customized datetime parses.
        // en_US_POSIX + UTC:沒鎖 locale 的 DateFormatter 會跟著裝置的
        // 12/24 小時制與曆法設定走,部分用戶會解析失敗。
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"

        let secondaryFormatter = DateFormatter()
        secondaryFormatter.locale = Locale(identifier: "en_US_POSIX")
        secondaryFormatter.timeZone = TimeZone(identifier: "UTC")
        secondaryFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = TimeZone(identifier: "UTC")
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        
        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            
            if let date = formatter.date(from: dateStr) {
                return date
            }
            if let date = secondaryFormatter.date(from: dateStr) {
                return date
            }
            if let date = dateOnlyFormatter.date(from: dateStr) {
                return date
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
    }

    /// Like request() but accepts an Encodable body and encodes it as JSON automatically.
    func requestBody<T: Codable, B: Encodable>(_ endpoint: String, method: String = "POST", body: B) async throws -> T {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(body)
        return try await request(endpoint, method: method, body: bodyData)
    }
}
