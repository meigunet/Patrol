import Foundation
import Network

/// 本地 HTTP 服务：托管 map.html / leaflet，并代理图层 GeoJSON。
/// 用 http://127.0.0.1 承载页面，规避 file:// 的混合内容与资源加载问题（与安卓踩坑结论一致）。
final class LocalServer {
    static let shared = LocalServer()

    private var listener: NWListener?
    private var port: UInt16 = 0
    private let queue = DispatchQueue(label: "patrol.httpserver", qos: .utility)
    private(set) var baseUrl: String = ""

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        do {
            listener = try NWListener(using: params)
        } catch { return }

        let ready = DispatchSemaphore(value: 0)
        listener?.newConnectionHandler = { [weak self] conn in
            conn.start(queue: self?.queue ?? .global())
            self?.handle(conn)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                if let p = self.listener?.port {
                    self.port = p.rawValue
                    self.baseUrl = "http://127.0.0.1:\(p.rawValue)"
                }
                ready.signal()
            case .failed, .cancelled:
                ready.signal()
            default:
                break
            }
        }
        listener?.start(queue: queue)
        // 等待就绪，确保调用方读 baseUrl 时已有值
        if ready.wait(timeout: .now() + 3) == .timedOut {
            // 兜底：即使未就绪也给个占位，避免空 URL
            if baseUrl.isEmpty { baseUrl = "http://127.0.0.1:8791" }
        }
    }

    func stop() { listener?.cancel(); listener = nil }

    // MARK: - 请求处理
    private func handle(_ conn: NWConnection) {
        var buffer = Data()
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self = self else { conn.cancel(); return }
            if let d = data { buffer.append(d) }
            guard let head = String(data: buffer, encoding: .utf8),
                  let headerEnd = head.range(of: "\r\n\r\n") else {
                if error == nil { self.handle(conn) } else { conn.cancel() }
                return
            }
            let headerText = String(head[..<headerEnd.lowerBound])
            let firstLine = headerText.split(separator: "\r\n").first.map(String.init) ?? ""
            let parts = firstLine.split(separator: " ")
            let method = parts.first.map(String.init) ?? "GET"
            let target = parts.count >= 2 ? String(parts[1]) : "/"
            self.route(method: method, target: target) { status, contentType, body in
                self.respond(conn, status: status, contentType: contentType, body: body)
            }
        }
    }

    private func route(method: String, target: String, completion: @escaping (String, String, Data) -> Void) {
        let url = URL(string: target) ?? URL(string: "/")!
        let path = url.path
        let query = url.query ?? ""

        // 静态资源
        if path == "/" || path == "/map.html" {
            if let d = bundleData("map.html", sub: "Resources") {
                completion("200 OK", "text/html; charset=utf-8", d)
            } else { completion("404 Not Found", "text/plain", Data("map.html missing".utf8)) }
            return
        }
        if path.hasPrefix("/leaflet/") {
            let rel = String(path.dropFirst("/leaflet/".count))
            if let d = bundleData(rel, sub: "Resources/leaflet") {
                completion("200 OK", mime(rel), d)
            } else { completion("404 Not Found", "text/plain", Data("not found".utf8)) }
            return
        }
        // 本地图层：/l/<id>?u=<upstream>
        if path.hasPrefix("/l/") {
            let idStr = String(path.dropFirst(3))
            if let id = Int64(idStr), let data = LocalMapStore.shared.layerData(id) {
                completion("200 OK", "application/json; charset=utf-8", data)
                return
            }
            // 本地没有 → 回源
            if let u = queryValue(query, "u"), let remote = URL(string: u) {
                URLSession.shared.dataTask(with: remote) { data, resp, _ in
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 502
                    completion("\(code) OK", "application/json; charset=utf-8", data ?? Data())
                }.resume()
                return
            }
            completion("404 Not Found", "text/plain", Data("layer not cached".utf8))
            return
        }
        completion("404 Not Found", "text/plain", Data("not found".utf8))
    }

    private func respond(_ conn: NWConnection, status: String, contentType: String, body: Data) {
        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Cache-Control: no-cache\r\n"
        header += "Connection: close\r\n\r\n"
        var out = Data(header.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func bundleData(_ name: String, sub: String) -> Data? {
        let base = Bundle.main.resourceURL
        var url = base?.appendingPathComponent(sub, isDirectory: true)
        url = url?.appendingPathComponent(name)
        guard let u = url else { return nil }
        return try? Data(contentsOf: u)
    }

    private func mime(_ name: String) -> String {
        if name.hasSuffix(".js") { return "application/javascript; charset=utf-8" }
        if name.hasSuffix(".css") { return "text/css; charset=utf-8" }
        if name.hasSuffix(".png") { return "image/png" }
        return "application/octet-stream"
    }

    private func queryValue(_ query: String, _ key: String) -> String? {
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2, String(kv[0]) == key {
                return String(kv[1]).removingPercentEncoding
            }
        }
        return nil
    }
}
