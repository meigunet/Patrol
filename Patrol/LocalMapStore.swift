import Foundation

/// 图层 GeoJSON 本地缓存（对应安卓 LocalMapStore 的图层部分）
final class LocalMapStore {
    static let shared = LocalMapStore()
    private let fm = FileManager.default
    private let dir: URL
    private var stamps: [String: String] = [:]

    private init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("map_layers", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("stamps.json")),
           let s = (try? JSONDecoder().decode([String:String].self, from: d)) { stamps = s }
    }

    private func file(_ id: Int64) -> URL { dir.appendingPathComponent("\(id).geojson") }

    func hasLayer(_ id: Int64) -> Bool {
        guard let d = try? Data(contentsOf: file(id)), d.count > 2 else { return false }
        let head = String(data: d.prefix(2), encoding: .utf8) ?? ""
        return head == "{" || head == "["
    }

    func layerData(_ id: Int64) -> Data? {
        guard hasLayer(id) else { return nil }
        return try? Data(contentsOf: file(id))
    }

    func downloadLayer(id: Int64, url: String, updatedAt: String?) async {
        if stamps[String(id)] == (updatedAt ?? "") && hasLayer(id) { return }
        guard let u = URL(string: url) else { return }
        var req = URLRequest(url: u)
        req.timeoutInterval = 25
        req.setValue("Mozilla/5.0 (iPhone) PatrolApp", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0), !data.isEmpty else { return }
            let head = String(data: data.prefix(2), encoding: .utf8) ?? ""
            guard head == "{" || head == "[" else { return }   // 不是 GeoJSON 不写
            try data.write(to: file(id), options: .atomic)
            stamps[String(id)] = updatedAt ?? ""
            if let sd = try? JSONEncoder().encode(stamps) {
                try? sd.write(to: dir.appendingPathComponent("stamps.json"), options: .atomic)
            }
        } catch { /* 离线时保留旧缓存 */ }
    }

    func clearAll() {
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files { try? fm.removeItem(at: f) }
        }
        stamps = [:]
    }
}
