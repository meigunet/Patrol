import SwiftUI

@main
struct PatrolApp: App {
    @StateObject private var session = Session.shared
    @StateObject private var store = Store.shared
    @State private var kickedMessage: String? = nil

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(store)
                .onAppear {
                    LocalServer.shared.start()
                    UIApplication.shared.registerForRemoteNotifications()
                }
                .onReceive(session.kicked) { msg in
                    kickedMessage = msg
                }
                .alert("已退出登录", isPresented: Binding(get: { kickedMessage != nil },
                                                            set: { if !$0 { kickedMessage = nil } })) {
                    Button("知道了", role: .cancel) { kickedMessage = nil }
                } message: {
                    Text(kickedMessage ?? "")
                }
        }
    }
}
