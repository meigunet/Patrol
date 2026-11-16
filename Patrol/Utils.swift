import Foundation

// sheet(item:) 需要 Identifiable，让 String 直接可用
extension String: Identifiable {
    public var id: String { self }
}

// MARK: - 时间工具
enum TimeUtil {
    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 与安卓一致的 UTC ISO 字符串 yyyy-MM-dd'T'HH:mm:ss.SSS'Z'
    static func iso(_ date: Date = Date()) -> String {
        isoFormatter.string(from: date)
    }

    static func parse(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        return isoFormatter.date(from: s) ?? isoNoFraction.date(from: s)
    }

    /// yyyy-MM-dd HH:mm
    static func display(_ s: String?) -> String {
        guard let s = s, let d = parse(s) else { return s ?? "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }

    static func shortSerial(_ s: String) -> String {
        if let i = s.lastIndex(of: '-') { return String(s[s.index(after: i)...]) }
        return s
    }

    static func nowCompact() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        return f.string(from: Date())
    }

    static func durationText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)秒" }
        if seconds < 3600 { return "\(seconds / 60)分\(seconds % 60)秒" }
        return "\(seconds / 3600)小时\(seconds % 3600 / 60)分"
    }

    static func agoText(_ seconds: Int64?) -> String {
        guard let s = seconds, s >= 0 else { return "" }
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(s / 60)分钟前" }
        if s < 86400 { return "\(s / 3600)小时前" }
        return "\(s / 86400)天前"
    }
}

// MARK: - 经纬度 / 里程
enum GeoUtil {
    static func haversine(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let r = 6371000.0
        let dLat = (b.0 - a.0) * .pi / 180
        let dLng = (b.1 - a.1) * .pi / 180
        let la1 = a.0 * .pi / 180, la2 = b.0 * .pi / 180
        let h = sin(dLat/2)*sin(dLat/2) + cos(la1)*cos(la2)*sin(dLng/2)*sin(dLng/2)
        return 2 * r * atan2(sqrt(h), sqrt(1-h))
    }

    /// 从表单 data 中找第一个含 lat/lng 的定位对象
    static func firstPoint(in data: JSONDict) -> (lat: Double, lng: Double, alt: Double)? {
        for (_, v) in data {
            if let obj = v.objectValue,
               let lat = obj["lat"]?.doubleValue, let lng = obj["lng"]?.doubleValue {
                return (lat, lng, obj["alt"]?.doubleValue ?? 0)
            }
        }
        return nil
    }
}

// MARK: - 友好错误
enum ErrorText {
    static func friendly(_ error: Error) -> String {
        let msg = error.localizedDescription
        return friendly(msg)
    }
    static func friendly(_ msg: String) -> String {
        if msg.contains("Could not connect") || msg.contains("The Internet connection") || msg.contains("连接") || msg.contains("offline") {
            return "连不上服务器，请检查网络或服务器地址（数据已保存在本机）"
        }
        if msg.contains("其他设备登录") || msg.contains("KICKED") {
            return "该账号已在另一台设备登录，本机已退出。"
        }
        if msg.contains("timed out") || msg.contains("超时") { return "请求超时，请稍后重试" }
        return msg
    }
}

// MARK: - 设备号
enum DeviceId {
    static func get() -> String {
        let key = "patrol_device_id"
        if let v = UserDefaults.standard.string(forKey: key), !v.isEmpty { return v }
        let v = "ios-" + UUID().uuidString
        UserDefaults.standard.set(v, forKey: key)
        return v
    }
}

// MARK: - 基础 URL 工具
enum URLTool {
    static let defaultBase = "http://36.170.114.144:3000/api/"

    /// 将 api base（以 /api/ 结尾）转成站点根（去掉 /api）
    static func serverRoot(_ base: String) -> String {
        var s = base
        if s.hasSuffix("/api/") { s = String(s.dropLast(5)) }
        else if s.hasSuffix("/api") { s = String(s.dropLast(4)) }
        while s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }

    static func normalized(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("http://") || s.hasPrefix("https://") else { return nil }
        if !s.hasSuffix("/") { s += "/" }
        return s
    }
}

// MARK: - 表单校验
enum FormValidator {
    static func isEmpty(_ v: JSONValue?) -> Bool {
        guard let v = v else { return true }
        return v.isEmpty
    }

    static func validate(fields: [FieldDto], data: JSONDict) -> String? {
        for f in fields {
            let v = data[f.key]
            if f.required && isEmpty(v) {
                return "请填写「\(f.label)」"
            }
            if f.type == "location", let obj = v?.objectValue {
                let hasCoord = obj["lat"]?.doubleValue != nil || obj["lng"]?.doubleValue != nil
                if hasCoord && (obj["slope"]?.doubleValue == nil || obj["aspect"]?.doubleValue == nil) {
                    return "「\(f.label)」的坡度、坡向必填：点「重新定位」再取一次，或手动填写数值"
                }
            }
            if f.type == "date", let s = v?.stringValue, !s.isEmpty {
                if !matches(s, pattern: "^\\d{4}-\\d{2}-\\d{2}$") { return "「\(f.label)」格式不对，应为2026-10-24" }
            }
            if f.type == "time", let s = v?.stringValue, !s.isEmpty {
                if !matches(s, pattern: "^\\d{2}:\\d{2}$") { return "「\(f.label)」格式不对，应为13:30" }
            }
        }
        return nil
    }

    private static func matches(_ s: String, pattern: String) -> Bool {
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: s)
    }
}
