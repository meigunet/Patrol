import Foundation

/// 网络错误
enum APIError: Error, LocalizedError {
    case http(Int, String)
    case kicked
    case unauthorized
    case offline
    case invalidURL
    var errorDescription: String? {
        switch self {
        case .http(let code, let m): return "HTTP \(code): \(m)"
        case .kicked: return "KICKED：该账号已在另一台设备登录"
        case .unauthorized: return "登录已过期"
        case .offline: return "连不上服务器"
        case .invalidURL: return "服务器地址格式错误"
        }
    }
}

/// 网络层（对应 RetrofitClient）：Bearer token、401 自动刷新、被顶下线检测。
final class API {
    static let shared = API()
    private init() {}

    private let session = Session.shared
    private let decoder: JSONDecoder = JSONDecoder()
    private let encoder: JSONEncoder = JSONEncoder()

    private func url(_ path: String) -> URL? {
        let base = session.baseUrl
        let clean = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: clean + "/" + path)
    }

    /// 发起请求，带 token；401 时刷新一次并重试
    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         auth: Bool = true, retry: Bool = true) async throws -> Data {
        guard var u = url(path) else { throw APIError.invalidURL }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let b = body { req.httpBody = b }
        if auth, !session.token.isEmpty {
            req.setValue("Bearer " + session.token, forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.offline
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0

        if code == 401 {
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.contains("其他设备登录") || text.contains("KICKED") {
                session.logout()
                session.reportKicked("该账号已在另一台设备登录，本机已退出。如非本人操作，请尽快修改密码。")
                throw APIError.kicked
            }
            if retry, await refreshToken() {
                return try await request(path, method: method, body: body, auth: auth, retry: false)
            }
            session.logout()
            throw APIError.unauthorized
        }
        guard (200..<300).contains(code) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(code, String(msg.prefix(200)))
        }
        return data
    }

    /// 刷新 token（并发去重）
    private var refreshingTask: Task<Bool, Never>?
    private func refreshToken() async -> Bool {
        if let t = refreshingTask { return await t.value }
        let task = Task<Bool, Never> {
            guard !session.refresh.isEmpty, let u = url("auth/refresh") else { return false }
            var req = URLRequest(url: u)
            req.httpMethod = "POST"
            req.timeoutInterval = 20
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["refreshToken": session.refresh])
            do {
                let (d, r) = try await URLSession.shared.data(for: req)
                guard (200..<300).contains((r as? HTTPURLResponse)?.statusCode ?? 0),
                      let pair = try? decoder.decode(TokenPair.self, from: d), !pair.accessToken.isEmpty else { return false }
                session.setTokens(access: pair.accessToken, refresh: pair.refreshToken.isEmpty ? session.refresh : pair.refreshToken)
                return true
            } catch { return false }
        }
        refreshingTask = task
        let ok = await task.value
        refreshingTask = nil
        return ok
    }

    private func send<T: Decodable>(_ path: String, method: String = "GET",
                                    body: Any? = nil, auth: Bool = true) async throws -> T {
        var bodyData: Data? = nil
        if let b = body { bodyData = try JSONSerialization.data(withJSONObject: b) }
        let d = try await request(path, method: method, body: bodyData, auth: auth)
        do { return try decoder.decode(T.self, from: d) }
        catch {
            // 兼容部分接口 {data: ...} 信封
            if let env = try? decoder.decode(ListEnvelope<T>.self, from: d), let first = env.data.first { return first }
            throw error
        }
    }

    // MARK: - 登录 / 公告 / 版本
    func login(account: String, password: String) async throws -> LoginResponse {
        try await send("auth/login", method: "POST", body: [
            "account": account, "password": password,
            "deviceId": session.deviceId, "platform": "ios"
        ], auth: false)
    }

    func logout() async {
        guard let body = try? JSONSerialization.data(withJSONObject: ["deviceId": session.deviceId]) else { return }
        _ = try? await request("auth/logout", method: "POST", body: body)
    }

    func announcement() async -> AnnouncementDto? {
        try? await send("announcement", auth: false)
    }

    func appVersion() async -> AppVersionInfo? {
        try? await send("app/version", auth: false)
    }

    // MARK: - 同步
    func syncPull() async throws -> SyncPullResponse {
        try await send("sync/pull")
    }

    func syncPush(_ req: SyncPushRequest) async throws -> SyncPushResponse {
        let d = try encoder.encode(req)
        let raw = try await request("sync/push", method: "POST", body: d)
        return try decoder.decode(SyncPushResponse.self, from: raw)
    }

    // MARK: - 位置
    func heartbeat() async -> Bool {
        let d = (try? encoder.encode(HeartbeatRequest())) ?? Data()
        do { _ = try await request("locations/heartbeat", method: "POST", body: d); return true }
        catch { return false }
    }

    func ping(lat: Double, lng: Double, accuracy: Float?, at: String) async -> Bool {
        let p = LocationPingRequest(lat: lat, lng: lng, accuracy: accuracy, at: at)
        guard let body = try? encoder.encode(p) else { return false }
        do { _ = try await request("locations/ping", method: "POST", body: body); return true }
        catch { return false }
    }

    func uploadLocations(_ points: [LocationPointDto]) async -> LocationUploadResponse? {
        guard let body = try? encoder.encode(LocationUploadRequest(points: points)) else { return nil }
        return try? await send("locations/upload", method: "POST", body: body)
    }

    func onlineLocations() async -> OnlineLocationsResponse? {
        try? await send("locations/online")
    }

    func elevation(lat: Double, lng: Double) async -> ElevationDto? {
        try? await send("geo/elevation?lat=\(lat)&lng=\(lng)")
    }

    func recordSyncInfo(uuid: String) async -> RecordSyncInfo? {
        let raw = (try? await request("records/by-uuid/\(uuid)/sync-info")) ?? Data()
        return try? decoder.decode(RecordSyncInfo.self, from: raw)
    }

    func deleteRecord(uuid: String) async -> Bool {
        do { _ = try await request("records/by-uuid/\(uuid)", method: "DELETE"); return true }
        catch { return false }
    }

    func deleteUser(id: Int64) async -> Bool {
        do { _ = try await request("users/\(id)", method: "DELETE"); return true }
        catch { return false }
    }
}
