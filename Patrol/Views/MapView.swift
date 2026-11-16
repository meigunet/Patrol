import SwiftUI
import WebKit
import Combine
import CoreLocation
import UIKit

/// 地图页：WKWebView 加载本地 HTTP 服务托管的 map.html，复用安卓端全部地图能力。
struct MapView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: Session
    @State private var online = OnlineLocationsResponse()
    @State private var showLayerPicker = false
    @State private var pickedLayers: Set<Int64> = []
    @State private var layerTouched = false
    @State private var myLocation: CLLocationCoordinate2D? = nil
    @State private var altitudeText = "--"

    var body: some View {
        ZStack {
            MapWebView(online: online, pickedLayers: pickedLayers, layerTouched: layerTouched,
                       myLocation: $myLocation)
            .ignoresSafeArea()

            // 顶部信息条
            VStack {
                HStack {
                    Image(systemName: "person.2.fill")
                    Text("在线 \(online.onlineCount) 人").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        showLayerPicker = true
                    } label: {
                        Image(systemName: "layers.circle.fill").font(.title2)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.92)).cornerRadius(10)
                .padding(.horizontal, 12).padding(.top, 8)
                Spacer()

                // 底部经纬度 + 海拔
                if let c = myLocation {
                    Text(String(format: "纬度 %.5f · 经度 %.5f · 海拔 %@", c.latitude, c.longitude, altitudeText))
                        .font(.caption).padding(8)
                        .background(Color.white.opacity(0.9)).cornerRadius(8)
                        .padding(.bottom, 8)
                }
            }
        }
        .sheet(isPresented: $showLayerPicker) {
            LayerPicker(picked: $pickedLayers, touched: $layerTouched).environmentObject(store)
        }
        .onAppear {
            if !layerTouched {
                pickedLayers = Set(store.layers.filter { $0.visible }.map { $0.id })
            }
            refreshOnline()
            LocationService.shared.startTracking()
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            refreshOnline()
        }
        .onReceive(LocationService.shared.$latestLocation) { loc in
            guard let loc = loc else { return }
            myLocation = loc.coordinate
            Task {
                if let e = await API.shared.elevation(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude) {
                    await MainActor.run { altitudeText = String(format: "%.0f m", e.alt) }
                } else if loc.altitude.isFinite {
                    await MainActor.run { altitudeText = String(format: "%.0f m", loc.altitude) }
                }
            }
        }
    }

    private func refreshOnline() {
        Task {
            if let r = await API.shared.onlineLocations() {
                await MainActor.run { online = r }
            }
        }
    }
}

// MARK: - WKWebView 封装 + 桥接
struct MapWebView: UIViewRepresentable {
    var online: OnlineLocationsResponse
    var pickedLayers: Set<Int64>
    var layerTouched: Bool
    @Binding var myLocation: CLLocationCoordinate2D?

    func makeCoordinator() -> Coordinator { Coordinator(myLocation: $myLocation) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        let bridge = Bridge()
        bridge.onTraceReady = { [weak c = context.coordinator] in c?.injectAll() }
        config.userContentController.add(bridge, name: "patrol")
        context.coordinator.bridge = bridge

        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = false
        web.backgroundColor = .clear
        context.coordinator.web = web

        // 注入 window.Android 兼容对象（map.html 判空调用，无需改页面）
        let shim = """
        window.Android = {
          mapReady: function(){ try{ window.webkit.messageHandlers.patrol.postMessage('mapReady'); }catch(e){} },
          measureResult: function(t){ try{ window.webkit.messageHandlers.patrol.postMessage('measure:'+t); }catch(e){} },
          tileProblem: function(u){ },
          tilesNeeded: function(j){ }
        };
        """
        config.userContentController.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        loadURL(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        c.online = online
        c.pickedLayers = pickedLayers
        c.layerTouched = layerTouched
        if c.webReady { c.injectAll() }
    }

    private func loadURL(_ web: WKWebView) {
        LocalServer.shared.start()
        var comps = URLComponents(string: LocalServer.shared.baseUrl + "/map.html")!
        let root = URLTool.serverRoot(Session.shared.baseUrl)
        let layerMeta = layerMetaJSON()
        var items: [URLQueryItem] = [
            .init(name: "server", value: Session.shared.baseUrl),
            .init(name: "token", value: Session.shared.token),
            .init(name: "me", value: String(Session.shared.user.id)),
            .init(name: "chrome", value: "0"),
            .init(name: "longpress", value: "0")
        ]
        if !layerMeta.isEmpty { items.append(.init(name: "layerMeta", value: layerMeta)) }
        if !pickedLayers.isEmpty { items.append(.init(name: "layers", value: pickedLayers.map(String.init).joined(separator: ","))) }
        let localIds = Store.shared.layers.filter { LocalMapStore.shared.hasLayer($0.id) }.map(String.init)
        if !localIds.isEmpty {
            items.append(.init(name: "localLayers", value: localIds.joined(separator: ",")))
            items.append(.init(name: "proxy", value: LocalServer.shared.baseUrl))
        }
        _ = root
        comps.queryItems = items
        if let u = comps.url { web.load(URLRequest(url: u)) }
    }

    private func layerMetaJSON() -> String {
        let arr: [[String: Any]] = Store.shared.layers.map { l in
            ["id": l.id, "name": l.name, "format": l.format, "url": l.url,
             "color": l.color, "label_field": l.labelField ?? "", "visible": l.visible]
        }
        guard let d = try? JSONSerialization.data(withJSONObject: arr),
              let s = String(data: d, encoding: .utf8) else { return "" }
        return s.count > 6000 ? "" : s   // 太长不塞 URL
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var web: WKWebView?
        var bridge: Bridge?
        var online: OnlineLocationsResponse = OnlineLocationsResponse()
        var pickedLayers: Set<Int64> = []
        var layerTouched = false
        var webReady = false
        var myLocation: Binding<CLLocationCoordinate2D?>

        init(myLocation: Binding<CLLocationCoordinate2D?>) { self.myLocation = myLocation }

        func injectAll() {
            guard let web = web else { return }
            // 图层勾选
            let csv = pickedLayers.map(String.init).joined(separator: ",")
            web.evaluateJavaScript("window.setLayerSelection && window.setLayerSelection('\(csv)')") { _ in
                self.webReady = true
            }
            // 在线人员点 + 航迹（由页面自己拉 online，这里只注入航迹）
            injectTrace(web)
        }

        private func injectTrace(_ web: WKWebView) {
            let store = Store.shared
            var points: [[String: Any]] = []
            var records: [[String: Any]] = []
            for rid in store.recordingTaskIds {
                if let run = store.currentRun(taskId: rid) {
                    for p in store.points(runId: run.runId) {
                        points.append(["lat": p.lat, "lng": p.lng, "time": p.time, "trackId": p.trackId])
                    }
                }
            }
            for r in store.records where r.status != "DRAFT" {
                if let pt = GeoUtil.firstPoint(in: r.data) {
                    records.append(["lat": pt.lat, "lng": pt.lng, "alt": pt.alt,
                                    "time": r.submittedAt ?? "", "title": store.template(formId: r.formId)?.title ?? r.formId])
                }
            }
            let pj = (try? JSONSerialization.data(withJSONObject: points)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let rj = (try? JSONSerialization.data(withJSONObject: records)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            web.evaluateJavaScript("window.setMyTrace && window.setMyTrace(\(pj),\(rj),{finished:false})") { _ in }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let s = message.body as? String else { return }
            if s == "mapReady" { webReady = true; injectAll() }
            if s.hasPrefix("measure:") { /* 测量结果可在需要时展示 */ }
        }
    }

    final class Bridge: NSObject, WKScriptMessageHandler {
        var onTraceReady: (() -> Void)?
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let s = message.body as? String, s == "mapReady" { onTraceReady?() }
        }
    }
}

// MARK: - 任务航迹地图（map.html 任务模式 + 注入航迹/采集点）
struct TrackMapView: View {
    let points: [TrackPointDto]
    let records: [RecordDto]
    let store: Store

    var body: some View {
        TrackMapWebView(points: points, records: records, store: store)
    }
}

struct TrackMapWebView: UIViewRepresentable {
    let points: [TrackPointDto]
    let records: [RecordDto]
    let store: Store

    func makeCoordinator() -> Bridge { Bridge() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        let bridge = context.coordinator
        bridge.onReady = { [weak self] in
            guard let self = self else { return }
            self.inject(bridge.web)
        }
        config.userContentController.add(bridge, name: "patrol")
        let shim = """
        window.Android = {
          mapReady: function(){ try{ window.webkit.messageHandlers.patrol.postMessage('mapReady'); }catch(e){} },
          measureResult: function(t){ },
          tileProblem: function(u){ },
          tilesNeeded: function(j){ }
        };
        """
        config.userContentController.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.scrollView.isScrollEnabled = true
        bridge.web = web

        LocalServer.shared.start()
        var comps = URLComponents(string: LocalServer.shared.baseUrl + "/map.html")!
        comps.queryItems = [
            .init(name: "server", value: Session.shared.baseUrl),
            .init(name: "token", value: Session.shared.token),
            .init(name: "chrome", value: "0"),
            .init(name: "task", value: "1"),
            .init(name: "longpress", value: "0")
        ]
        if let u = comps.url { web.load(URLRequest(url: u)) }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.onReady?()
    }

    private func inject(_ web: WKWebView?) {
        guard let web = web else { return }
        var pts: [[String: Any]] = []
        for p in points {
            pts.append(["lat": p.lat, "lng": p.lng, "time": p.time, "trackId": p.trackId])
        }
        var recs: [[String: Any]] = []
        for r in records {
            if let pt = GeoUtil.firstPoint(in: r.data) {
                recs.append(["lat": pt.lat, "lng": pt.lng, "alt": pt.alt,
                             "time": r.submittedAt ?? "", "title": store.template(formId: r.formId)?.title ?? r.formId])
            }
        }
        let pj = (try? JSONSerialization.data(withJSONObject: pts)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let rj = (try? JSONSerialization.data(withJSONObject: recs)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        web.evaluateJavaScript("window.setMyTrace && window.setMyTrace(\(pj),\(rj),{finished:true})") { _ in }
    }

    final class Bridge: NSObject, WKScriptMessageHandler {
        weak var web: WKWebView?
        var onReady: (() -> Void)?
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let s = message.body as? String, s == "mapReady" { onReady?() }
        }
    }
}

// MARK: - 图层选择
struct LayerPicker: View {
    @EnvironmentObject var store: Store
    @Binding var picked: Set<Int64>
    @Binding var touched: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button("全部显示") { picked = Set(store.layers.map { $0.id }); touched = true }
                    Button("全部隐藏") { picked = []; touched = true }
                }
                Section("图层") {
                    ForEach(store.layers) { l in
                        HStack {
                            Image(systemName: picked.contains(l.id) ? "checkmark.square.fill" : "square")
                                .foregroundColor(Color(hex: 0x2E7D32))
                            Text(l.name)
                            Spacer()
                            Circle().fill(Color(hex: hexColor(l.color))).frame(width: 12, height: 12)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if picked.contains(l.id) { picked.remove(l.id) } else { picked.insert(l.id) }
                            touched = true
                        }
                    }
                }
            }
            .navigationTitle("图层").toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    func hexColor(_ s: String) -> UInt {
        let h = s.replacingOccurrences(of: "#", with: "")
        return UInt(h, radix: 16) ?? 0x2E7D32
    }
}
