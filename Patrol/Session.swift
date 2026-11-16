import Foundation
import Combine

/// 会话与偏好（对应安卓 DataStore）。用 UserDefaults 持久化。
final class Session: ObservableObject {
    static let shared = Session()

    private let defaults = UserDefaults.standard
    private enum K {
        static let access = "access_token"
        static let refresh = "refresh_token"
        static let loggedIn = "logged_in"
        static let baseUrl = "base_url"
        static let userJson = "user_json"
        static let forceWebView = "force_webview"
        static let locationReport = "location_report"
        static let floatWindow = "float_window"
    }

    @Published var isLoggedIn: Bool
    @Published var user: UserDto
    @Published var baseUrl: String
    @Published var forceWebView: Bool
    @Published var locationReportEnabled: Bool
    @Published var floatWindowEnabled: Bool

    /// 被顶下线回调
    let kicked = PassthroughSubject<String, Never>()

    private var accessToken: String
    private var refreshToken: String

    private init() {
        self.isLoggedIn = UserDefaults.standard.bool(forKey: K.loggedIn)
        self.baseUrl = UserDefaults.standard.string(forKey: K.baseUrl) ?? URLTool.defaultBase
        self.forceWebView = UserDefaults.standard.bool(forKey: K.forceWebView)
        self.locationReportEnabled = UserDefaults.standard.object(forKey: K.locationReport) as? Bool ?? true
        self.floatWindowEnabled = UserDefaults.standard.bool(forKey: K.floatWindow)
        self.accessToken = UserDefaults.standard.string(forKey: K.access) ?? ""
        self.refreshToken = UserDefaults.standard.string(forKey: K.refresh) ?? ""
        if let uj = UserDefaults.standard.string(forKey: K.userJson),
           let d = uj.data(using: .utf8), let u = try? JSONDecoder().decode(UserDto.self, from: d) {
            self.user = u
        } else {
            self.user = UserDto()
        }
    }

    var token: String { accessToken }
    var refresh: String { refreshToken }
    var hasToken: Bool { !accessToken.isEmpty }
    var deviceId: String { DeviceId.get() }

    func saveSession(token: TokenPair, user u: UserDto) {
        accessToken = token.accessToken
        refreshToken = token.refreshToken
        defaults.set(accessToken, forKey: K.access)
        defaults.set(refreshToken, forKey: K.refresh)
        if let d = try? JSONEncoder().encode(u), let s = String(data: d, encoding: .utf8) {
            defaults.set(s, forKey: K.userJson)
        }
        self.user = u
        defaults.set(true, forKey: K.loggedIn)
        isLoggedIn = true
    }

    func setTokens(access: String, refresh r: String) {
        accessToken = access
        refreshToken = r
        defaults.set(access, forKey: K.access)
        defaults.set(r, forKey: K.refresh)
    }

    func updateUser(_ u: UserDto) {
        self.user = u
        if let d = try? JSONEncoder().encode(u), let s = String(data: d, encoding: .utf8) {
            defaults.set(s, forKey: K.userJson)
        }
    }

    func logout() {
        accessToken = ""
        refreshToken = ""
        defaults.removeObject(forKey: K.access)
        defaults.removeObject(forKey: K.refresh)
        defaults.removeObject(forKey: K.userJson)
        defaults.set(false, forKey: K.loggedIn)
        isLoggedIn = false
        user = UserDto()
    }

    func setBaseUrl(_ url: String) {
        guard let n = URLTool.normalized(url) else { return }
        baseUrl = n
        defaults.set(n, forKey: K.baseUrl)
    }

    func setForceWebView(_ v: Bool) { forceWebView = v; defaults.set(v, forKey: K.forceWebView) }
    func setLocationReport(_ v: Bool) { locationReportEnabled = v; defaults.set(v, forKey: K.locationReport) }
    func setFloatWindow(_ v: Bool) { floatWindowEnabled = v; defaults.set(v, forKey: K.floatWindow) }

    func reportKicked(_ msg: String) { kicked.send(msg) }
}
