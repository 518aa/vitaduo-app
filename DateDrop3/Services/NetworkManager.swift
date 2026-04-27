//
//  NetworkManager.swift
//  DateDrop3
//
//  网络管理器 - 处理所有API请求
//

import Foundation
import Combine

final class ServerConnectionAlertCenter: ObservableObject {
    static let shared = ServerConnectionAlertCenter()
    @Published var isPresented = false
    private var lastShownAt: Date?
    private let minimumInterval: TimeInterval = 90

    func reportConnectionFailure() {
        let now = Date()
        if let lastShownAt, now.timeIntervalSince(lastShownAt) < minimumInterval {
            return
        }
        lastShownAt = now
        if !isPresented {
            isPresented = true
        }
    }

    func dismiss() {
        isPresented = false
    }
}

class NetworkManager {
    static let shared = NetworkManager()

    // 配置基础URL (支持覆盖)
    #if DEBUG
    private let debugDefaultBaseURL: String = {
        #if targetEnvironment(simulator)
        return "https://dd3.tpr.wales/api"
        #else
        return "https://dd3.tpr.wales/api"
        #endif
    }()
    #endif

    var baseURL: String {
        if let override = UserDefaults.standard.string(forKey: "api_base_url_override"),
           let cleaned = sanitizeBaseURL(override) {
            return cleaned
        }
        #if DEBUG
        return debugDefaultBaseURL
        #else
        return "https://dd3.tpr.wales/api"
        #endif
    }

    func setBaseURLOverride(_ url: String?) {
        let cleaned = sanitizeBaseURL(url ?? "")
        if cleaned == nil {
            UserDefaults.standard.removeObject(forKey: "api_base_url_override")
        } else {
            UserDefaults.standard.set(cleaned!, forKey: "api_base_url_override")
        }
    }

    func getBaseURLOverride() -> String? {
        UserDefaults.standard.string(forKey: "api_base_url_override")
    }

    private init() {}

    private var appLanguage: String {
        UserDefaults.standard.string(forKey: "app_language") ?? "en"
    }

    private func sanitizeBaseURL(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "`'\","))
        if s.isEmpty { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        if !s.hasSuffix("/api") { s += "/api" }
        return s
    }

    private func localizedNetworkError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let message: String
            switch URLError.Code(rawValue: nsError.code) {
            case .notConnectedToInternet:
                message = appLanguage == "zh" ? "网络不可用，请检查网络连接" : "No internet connection. Please check your network."
                ServerConnectionAlertCenter.shared.reportConnectionFailure()
            case .timedOut:
                message = appLanguage == "zh" ? "请求超时，请稍后重试" : "Request timed out. Please try again."
                ServerConnectionAlertCenter.shared.reportConnectionFailure()
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
                message = appLanguage == "zh" ? "无法连接服务器，请稍后重试" : "Cannot reach the server. Please try again."
                ServerConnectionAlertCenter.shared.reportConnectionFailure()
            default:
                message = nsError.localizedDescription
            }
            return NSError(domain: nsError.domain, code: nsError.code, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return error
    }

    // MARK: - JWT Token管理
    private var accessToken: String? {
        get {
            UserDefaults.standard.string(forKey: "access_token")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "access_token")
        }
    }

    func saveToken(_ token: String) {
        self.accessToken = token
    }

    func clearToken() {
        self.accessToken = nil
    }

    func hasToken() -> Bool {
        return accessToken != nil
    }

    private func getAuthorizationHeader() -> [String: String] {
        var headers = ["Content-Type": "application/json"]
        if let token = accessToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    private func getNoAuthHeader() -> [String: String] {
        ["Content-Type": "application/json"]
    }

    // MARK: - 通用请求方法

    private func createRequest(endpoint: String, method: String = "GET", body: Data? = nil) -> URLRequest? {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = getAuthorizationHeader()

        if let body = body {
            request.httpBody = body
        }

        return request
    }

    private func createRequestNoAuth(endpoint: String, method: String = "GET", body: Data? = nil) -> URLRequest? {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = getNoAuthHeader()

        if let body = body {
            request.httpBody = body
        }

        return request
    }

    func performRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        responseType: T.Type
    ) -> AnyPublisher<T, Error> {
        // 创建请求
        var request: URLRequest?
        do {
            if let body = body {
                let jsonData = try JSONEncoder().encode(body)
                request = createRequest(endpoint: endpoint, method: method, body: jsonData)
            } else {
                request = createRequest(endpoint: endpoint, method: method)
            }
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }

        guard let urlRequest = request else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        // 执行请求
        return URLSession.shared.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response in
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    if let apiError = try? JSONDecoder().decode(ErrorMessageResponse.self, from: data) {
                        let message = apiError.error ?? apiError.msg ?? "请求失败"
                        throw NSError(domain: "APIError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                    }
                    throw NSError(domain: "APIError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "请求失败"])
                }
                return data
            }
            .decode(type: T.self, decoder: JSONDecoder())
            .mapError { [weak self] error in
                self?.localizedNetworkError(error) ?? error
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    // MARK: - 认证相关API

    func register(user: RegisterRequest) -> AnyPublisher<AuthResponse, Error> {
        return performRequest(endpoint: "/auth/register", method: "POST", body: user, responseType: AuthResponse.self)
    }

    func login(contact: String) -> AnyPublisher<AuthResponse, Error> {
        let request = LoginRequest(contact: contact)
        return performRequest(endpoint: "/auth/login", method: "POST", body: request, responseType: AuthResponse.self)
    }

    func reviewAccount(nickname: String, contact: String) -> AnyPublisher<AuthResponse, Error> {
        let request = ReviewAccountRequest(nickname: nickname, contact: contact)
        guard let body = try? JSONEncoder().encode(request) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        guard let urlRequest = createRequestNoAuth(endpoint: "/review/account", method: "POST", body: body) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        return URLSession.shared.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response in
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    if let apiError = try? JSONDecoder().decode(ErrorMessageResponse.self, from: data) {
                        let message = apiError.error ?? apiError.msg ?? "请求失败"
                        throw NSError(domain: "APIError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
                    }
                    throw NSError(domain: "APIError", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "请求失败"])
                }
                return data
            }
            .decode(type: AuthResponse.self, decoder: JSONDecoder())
            .mapError { [weak self] error in
                self?.localizedNetworkError(error) ?? error
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func getCurrentUser() -> AnyPublisher<UserResponse, Error> {
        return performRequest(endpoint: "/auth/me", method: "GET", responseType: UserResponse.self)
    }

    // MARK: - 问卷相关API

    func getQuestions(lang: String = "zh") -> AnyPublisher<QuestionsResponse, Error> {
        let endpoint = "/questions?lang=\(lang)"
        return performRequest(endpoint: endpoint, method: "GET", responseType: QuestionsResponse.self)
    }

    func getQuestionsBySection(lang: String = "zh") -> AnyPublisher<QuestionsBySection, Error> {
        let endpoint = "/questions/by-section?lang=\(lang)"
        return performRequest(endpoint: endpoint, method: "GET", responseType: QuestionsBySection.self)
    }

    func submitAnswers(answers: [Answer]) -> AnyPublisher<APIResponse<String>, Error> {
        let request = AnswerSubmitRequest(answers: answers)
        return performRequest(endpoint: "/answers/submit", method: "POST", body: request, responseType: APIResponse<String>.self)
    }

    func getAnswerStatus() -> AnyPublisher<AnswerStatusResponse, Error> {
        return performRequest(endpoint: "/answers/status", method: "GET", responseType: AnswerStatusResponse.self)
    }

    func translate(text: String, targetLanguage: String) -> AnyPublisher<TranslateResponse, Error> {
        let request = TranslateRequest(text: text, target_language: targetLanguage)
        return performRequest(endpoint: "/translate", method: "POST", body: request, responseType: TranslateResponse.self)
    }

    // MARK: - 匹配相关API

    func generateMatches() -> AnyPublisher<GenerateMatchesResponse, Error> {
        let request = GenerateMatchesRequest(lang: appLanguage)
        return performRequest(endpoint: "/matching/generate", method: "POST", body: request, responseType: GenerateMatchesResponse.self)
    }

    func getMyMatches() -> AnyPublisher<MatchesResponse, Error> {
        return performRequest(endpoint: "/matching/my-matches", method: "GET", responseType: MatchesResponse.self)
    }

    func getMatchDetail(matchId: Int) -> AnyPublisher<APIResponse<Match>, Error> {
        return performRequest(endpoint: "/matching/\(matchId)", method: "GET", responseType: APIResponse<Match>.self)
    }

    func startChat(matchId: Int) -> AnyPublisher<APIResponse<Match>, Error> {
        return performRequest(endpoint: "/matching/\(matchId)/start-chat", method: "POST", responseType: APIResponse<Match>.self)
    }

    func manualMatchByCode(code: String) -> AnyPublisher<APIResponse<Match>, Error> {
        let request = ManualMatchRequest(match_code: code)
        return performRequest(endpoint: "/matching/manual-by-code", method: "POST", body: request, responseType: APIResponse<Match>.self)
    }

    // MARK: - 聊天相关API

    func getChatMessages(matchId: Int, userId: Int? = nil) -> AnyPublisher<MessagesResponse, Error> {
        let endpoint: String
        if let userId = userId {
            endpoint = "/chat/\(matchId)/messages?user_id=\(userId)"
            guard let request = createRequestNoAuth(endpoint: endpoint, method: "GET") else {
                return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
            }
            return URLSession.shared.dataTaskPublisher(for: request)
                .map(\.data)
                .decode(type: MessagesResponse.self, decoder: JSONDecoder())
                .mapError { [weak self] error in
                    self?.localizedNetworkError(error) ?? error
                }
                .receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
        endpoint = "/chat/\(matchId)/messages"
        return performRequest(endpoint: endpoint, method: "GET", responseType: MessagesResponse.self)
    }

    func sendMessage(matchId: Int, message: String, messageType: String = "text", userId: Int? = nil) -> AnyPublisher<APIResponse<ChatMessage>, Error> {
        var body: [String: Any] = [
            "match_id": matchId,
            "message": message,
            "message_type": messageType
        ]
        if let userId = userId {
            body["user_id"] = userId
        }

        guard let url = URL(string: "\(baseURL)/chat/send") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if userId != nil {
            request.allHTTPHeaderFields = getNoAuthHeader()
        } else {
            request.allHTTPHeaderFields = getAuthorizationHeader()
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: APIResponse<ChatMessage>.self, decoder: JSONDecoder())
            .mapError { [weak self] error in
                self?.localizedNetworkError(error) ?? error
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    // MARK: - 评分相关API

    func submitRating(matchId: Int, score: Int, userId: Int? = nil) -> AnyPublisher<APIResponse<Rating>, Error> {
        let request = RatingSubmitRequest(match_id: matchId, score: score, user_id: userId)
        return performRequest(endpoint: "/ratings/submit", method: "POST", body: request, responseType: APIResponse<Rating>.self)
    }

    func getRatingStatus(matchId: Int, userId: Int? = nil) -> AnyPublisher<RatingStatusResponse, Error> {
        let endpoint: String
        if let userId = userId {
            endpoint = "/ratings/\(matchId)/status?user_id=\(userId)"
        } else {
            endpoint = "/ratings/\(matchId)/status"
        }
        return performRequest(endpoint: endpoint, method: "GET", responseType: RatingStatusResponse.self)
    }

    func getUnlockStatus(matchId: Int, userId: Int? = nil) -> AnyPublisher<UnlockStatusResponse, Error> {
        let endpoint: String
        if let userId = userId {
            endpoint = "/ratings/\(matchId)/unlock-status?user_id=\(userId)"
        } else {
            endpoint = "/ratings/\(matchId)/unlock-status"
        }
        return performRequest(endpoint: endpoint, method: "GET", responseType: UnlockStatusResponse.self)
    }

    func getPartnerProfile(matchId: Int, userId: Int? = nil) -> AnyPublisher<APIResponse<User>, Error> {
        let endpoint: String
        if let userId = userId {
            endpoint = "/matching/\(matchId)/partner-profile?user_id=\(userId)"
        } else {
            endpoint = "/matching/\(matchId)/partner-profile"
        }
        return performRequest(endpoint: endpoint, method: "GET", responseType: APIResponse<User>.self)
    }

    // MARK: - 用户相关API

    func getProfile() -> AnyPublisher<APIResponse<User>, Error> {
        return performRequest(endpoint: "/users/profile", method: "GET", responseType: APIResponse<User>.self)
    }

    func updateProfile(request: UpdateProfileRequest) -> AnyPublisher<UserResponse, Error> {
        return performRequest(endpoint: "/users/profile", method: "PUT", body: request, responseType: UserResponse.self)
    }

    func deleteAccount() -> AnyPublisher<APIResponse<String>, Error> {
        return performRequest(endpoint: "/users/delete", method: "DELETE", responseType: APIResponse<String>.self)
    }

    func getMatchesCount() -> AnyPublisher<MatchesCountResponse, Error> {
        return performRequest(endpoint: "/users/matches-count", method: "GET", responseType: MatchesCountResponse.self)
    }

    func purchaseMatches(matchesAdded: Int, amount: Double) -> AnyPublisher<PurchaseResponse, Error> {
        let request = PurchaseRequest(
            matches_added: matchesAdded,
            amount: amount,
            payment_method: "iap_apple",
            transaction_id: UUID().uuidString
        )
        return performRequest(endpoint: "/users/purchase-matches", method: "POST", body: request, responseType: PurchaseResponse.self)
    }

    func getMatchCode() -> AnyPublisher<MatchCodeResponse, Error> {
        return performRequest(endpoint: "/users/match-code", method: "GET", responseType: MatchCodeResponse.self)
    }

    func debugUsers() -> AnyPublisher<DebugUsersResponse, Error> {
        guard let request = createRequest(endpoint: "/debug/users", method: "GET") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .tryMap { data in
                if data.isEmpty {
                    return DebugUsersResponse(users: nil, error: "服务返回空响应")
                }
                if let decoded = try? JSONDecoder().decode(DebugUsersResponse.self, from: data) {
                    return decoded
                }
                if let errorResponse = try? JSONDecoder().decode(ErrorMessageResponse.self, from: data) {
                    return DebugUsersResponse(users: nil, error: errorResponse.error ?? errorResponse.msg ?? "无法解析响应")
                }
                throw URLError(.cannotParseResponse)
            }
            .mapError { [weak self] error in
                self?.localizedNetworkError(error) ?? error
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func debugSimulateMatch(userId: Int, partnerId: Int, status: String, messageCount: Int, unlock: Bool, forceNew: Bool = false) -> AnyPublisher<DebugMatchSimulateResponse, Error> {
        let request = DebugMatchSimulateRequest(
            user_id: userId,
            partner_id: partnerId,
            status: status,
            message_count: messageCount,
            unlock: unlock,
            force_new: forceNew
        )
        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(request)
        } catch {
            return Fail(error: error).eraseToAnyPublisher()
        }
        guard let urlRequest = createRequest(
            endpoint: "/debug/matches/simulate",
            method: "POST",
            body: bodyData
        ) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: urlRequest)
            .map(\.data)
            .tryMap { data in
                if data.isEmpty {
                    return DebugMatchSimulateResponse(match: nil, error: "服务返回空响应")
                }
                if let decoded = try? JSONDecoder().decode(DebugMatchSimulateResponse.self, from: data) {
                    return decoded
                }
                if let errorResponse = try? JSONDecoder().decode(ErrorMessageResponse.self, from: data) {
                    return DebugMatchSimulateResponse(match: nil, error: errorResponse.error ?? errorResponse.msg ?? "无法解析响应")
                }
                throw URLError(.cannotParseResponse)
            }
            .mapError { [weak self] error in
                self?.localizedNetworkError(error) ?? error
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    // MARK: - Moderation (Apple Guideline 1.2)

    func reportUser(reportedUserId: Int, matchId: Int, reason: String) -> AnyPublisher<APIResponse<String>, Error> {
        let body: [String: Any] = [
            "reported_user_id": reportedUserId,
            "match_id": matchId,
            "reason": reason
        ]
        return postRequest(endpoint: "/users/report", body: body)
    }

    func blockUser(blockedUserId: Int) -> AnyPublisher<APIResponse<String>, Error> {
        let body: [String: Any] = ["blocked_user_id": blockedUserId]
        return postRequest(endpoint: "/users/block", body: body)
    }

    func deleteMessage(messageId: Int) -> AnyPublisher<APIResponse<String>, Error> {
        guard let url = URL(string: "\(baseURL)/chat/messages/\(messageId)") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: APIResponse<String>.self, decoder: JSONDecoder())
            .mapError { [weak self] error in self?.localizedNetworkError(error) ?? error }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    // MARK: - Values Profile (Radar Chart)

    func fetchValuesProfile(userId: Int, completion: @escaping (Result<ValuesProfile, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/values/profile") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let payload = json?["data"] as? [String: Any]
                let sections = payload?["sections"] as? [String: Double] ?? [:]
                let totalQuestions = payload?["total_questions"] as? Int ?? 0
                let completedAt = payload?["completed_at"] as? String
                let profile = ValuesProfile(sections: sections, totalQuestions: totalQuestions, completedAt: completedAt)
                completion(.success(profile))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Values Insights

    func fetchValuesInsights(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/values/insights") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let payload = json?["data"] as? [String: Any] ?? [:]
                completion(.success(payload))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Daily Values Card

    func fetchDailyCard(completion: @escaping (Result<[String: String], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/values/daily-card") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let payload = json?["data"] as? [String: String] ?? [:]
                completion(.success(payload))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func postRequest(endpoint: String, body: [String: Any]) -> AnyPublisher<APIResponse<String>, Error> {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: APIResponse<String>.self, decoder: JSONDecoder())
            .mapError { [weak self] error in self?.localizedNetworkError(error) ?? error }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
