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
    case invalidResponse
    case decodingError(Error)
    case serverError(code: String, detail: str)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無效的 API 連線網址。"
        case .requestFailed(let err):
            return "網路連線失敗：\(err.localizedDescription)"
        case .invalidResponse:
            return "伺服器回傳無效的格式。"
        case .decodingError(let err):
            return "資料解析失敗：\(err.localizedDescription)"
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
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                // Session token rejected (expired / secret rotated) — drop it so
                // the next launch re-registers instead of failing forever.
                KeychainStore.shared.sessionToken = nil
            }
            throw APIError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Handle Python's ISO dates or customized datetime parses
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        
        let secondaryFormatter = DateFormatter()
        secondaryFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let dateOnlyFormatter = DateFormatter()
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
            throw APIError.decodingError(error)
        }
        
        if !apiResponse.success {
            let err = apiResponse.error ?? ApiErrorDetail(code: "UNKNOWN_ERROR", detail: "發生未知的伺服器錯誤")
            throw APIError.serverError(code: err.code, detail: err.detail)
        }
        
        guard let responseData = apiResponse.data else {
            throw APIError.invalidResponse
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
