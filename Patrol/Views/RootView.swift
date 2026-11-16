import SwiftUI

/// 启动门：SYNC（同步）→ 放行 / 登录
struct RootView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var store: Store
    @State private var phase: Phase = .loading
    @State private var syncText = "正在准备…"
    @State private var showLogin = false

    enum Phase { case loading, syncing, done }

    var body: some View {
        ZStack {
            if phase == .done {
                if session.isLoggedIn {
                    MainTabView()
                } else {
                    LoginView(onOk: { withAnimation { showLogin = false } })
                }
            } else {
                gateView
            }
        }
        .onAppear(perform: startup)
    }

    private var gateView: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x2E7D32), Color(hex: 0x1B5E20)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "leaf.fill").font(.system(size: 56)).foregroundColor(.white)
                Text("保护地巡护").font(.title.bold()).foregroundColor(.white)
                if phase == .loading {
                    ProgressView().tint(.white)
                    Text("正在验证版本…").foregroundColor(.white.opacity(0.85)).font(.subheadline)
                } else {
                    ProgressView().tint(.white)
                    Text(syncText).foregroundColor(.white.opacity(0.9)).font(.subheadline)
                    Text("数据同步完成后自动进入 App").foregroundColor(.white.opacity(0.7)).font(.caption)
                }
            }
        }
    }

    private func startup() {
        Task {
            // 启动门只做配置同步（含图层本地化），失败也不阻塞进入（离线可用本机数据）
            if session.isLoggedIn {
                await MainActor.run { phase = .syncing; syncText = "正在同步服务端数据（任务/表格/底图/图层）…" }
                await SyncService.shared.refreshConfig()
                await MainActor.run { syncText = "正在下载图层数据到本地…" }
                // syncLayers 已在 refreshConfig 内完成
            }
            // 启动定位与心跳
            LocationService.shared.startTracking()
            LocationService.shared.beat()
            await MainActor.run { withAnimation { phase = .done } }
        }
    }
}

// MARK: - 底部 Tab 导航
struct MainTabView: View {
    @State private var selection: Int = 0
    @State private var showPtt = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                MapView().tag(0).tabItem { Label("地图", systemImage: "map.fill") }
                TaskListView().tag(1).tabItem { Label("巡护监测", systemImage: "figure.walk") }
                Color.clear.tag(2).tabItem { Label("", systemImage: "") }
                RecordsView().tag(3).tabItem { Label("上报记录", systemImage: "doc.text.fill") }
                ProfileView().tag(4).tabItem { Label("我的", systemImage: "person.fill") }
            }

            // 中间对讲按钮（iOS 无悬浮窗，固定在 Tab 上方）
            Button(action: { showPtt = true }) {
                ZStack {
                    Circle().fill(Color(hex: 0x1B5E20)).frame(width: 54, height: 54)
                    Image(systemName: "radio.fill").foregroundColor(.white).font(.title3)
                }
                .shadow(radius: 3)
            }
            .offset(y: -18)
            .sheet(isPresented: $showPtt) { PttView().environmentObject(Session.shared) }
        }
        .onAppear {
            PttService.shared.connect()
            LocationService.shared.beat()
        }
        // 前台定时器：每分钟心跳（后台定位回调也补心跳）
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            LocationService.shared.beat()
        }
    }
}

// 颜色工具
extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}
