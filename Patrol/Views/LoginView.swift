import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var store: Store
    var onOk: () -> Void

    @State private var account = ""
    @State private var password = ""
    @State private var serverUrl = Session.shared.baseUrl
    @State private var showServer = false
    @State private var error = ""
    @State private var serverMsg = ""
    @State private var loading = false
    @State private var announcement: AnnouncementDto?
    @State private var showAnnouncement = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 22) {
                    Spacer().frame(height: 40)
                    Image(systemName: "leaf.circle.fill").font(.system(size: 64)).foregroundColor(.white)
                    Text("保护地巡护").font(.largeTitle.bold()).foregroundColor(.white)
                    Text("移动巡护 · 离线可巡 · 在线可报").font(.subheadline).foregroundColor(.white.opacity(0.8))

                    if let a = announcement, a.enabled, !a.text.isEmpty {
                        Button { showAnnouncement = true } label: {
                            HStack {
                                Text("📢 \(a.text)").font(.footnote).lineLimit(2).foregroundColor(.white)
                                Spacer()
                            }
                            .padding(10).background(Color.white.opacity(0.15)).cornerRadius(8)
                        }
                    }

                    VStack(spacing: 14) {
                        Text("账号登录").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        TextField("账号", text: $account)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none).disableAutocorrection(true)
                        SecureField("密码", text: $password).textFieldStyle(.roundedBorder)

                        if !error.isEmpty {
                            Text(error).font(.footnote).foregroundColor(.yellow).frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: doLogin) {
                            HStack {
                                if loading { ProgressView().tint(.white) }
                                Text(loading ? "登录中…" : "登 录").fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity).padding(12)
                            .background(Color(hex: 0x1B5E20)).foregroundColor(.white).cornerRadius(10)
                        }
                        .disabled(loading || account.isEmpty || password.isEmpty)

                        Button("服务器设置") { showServer.toggle() }
                            .font(.footnote).foregroundColor(.white.opacity(0.85))

                        if showServer {
                            VStack(spacing: 8) {
                                TextField("http://host:3000/api/", text: $serverUrl)
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.none).disableAutocorrection(true)
                                    .keyboardType(.URL)
                                HStack {
                                    Button("保存并同步") { saveServer() }
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.white.opacity(0.2)).foregroundColor(.white).cornerRadius(8)
                                    Button("恢复默认") {
                                        serverUrl = URLTool.defaultBase
                                        session.setBaseUrl(URLTool.defaultBase)
                                        serverMsg = "已恢复默认：\(URLTool.defaultBase)"
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.white.opacity(0.2)).foregroundColor(.white).cornerRadius(8)
                                }
                                if !serverMsg.isEmpty {
                                    Text(serverMsg).font(.caption).foregroundColor(.white.opacity(0.9))
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(16)
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .background(LinearGradient(colors: [Color(hex: 0x2E7D32), Color(hex: 0x1B5E20)],
                                       startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }
        .sheet(isPresented: $showAnnouncement) {
            VStack(alignment: .leading, spacing: 12) {
                Text("公告").font(.title2.bold())
                ScrollView { Text(announcement?.text ?? "").frame(maxWidth: .infinity, alignment: .leading) }
                Spacer()
                Button("关闭") { showAnnouncement = false }.frame(maxWidth: .infinity).padding().buttonStyle(.borderedProminent)
            }.padding()
        }
        .onAppear {
            Task { announcement = await API.shared.announcement() }
        }
    }

    private func saveServer() {
        guard let n = URLTool.normalized(serverUrl) else {
            serverMsg = "格式错误：需以 http:// 或 https:// 开头"
            return
        }
        session.setBaseUrl(n)
        serverUrl = n
        serverMsg = "已保存：\(n)（登录后自动同步服务端数据）"
        Task {
            let ok = await API.shared.heartbeat() // 轻量探测连通性
            await MainActor.run { serverMsg = ok ? "已保存并连通：\(n)" : "已保存：\(n)（暂时连不上，联网后自动同步）" }
        }
    }

    private func doLogin() {
        loading = true; error = ""
        Task {
            do {
                let resp = try await API.shared.login(account: account.trimmingCharacters(in: .whitespaces), password: password)
                await MainActor.run {
                    session.saveSession(token: resp.token, user: resp.user)
                    LocationService.shared.beat()
                }
                // 登录预同步
                try? await SyncService.shared.refreshConfig()
                LocationService.shared.startTracking()
                await MainActor.run {
                    loading = false
                    onOk()
                }
            } catch {
                await MainActor.run {
                    loading = false
                    let m = ErrorText.friendly(error)
                    self.error = m.hasPrefix("连不上") ? "登录失败：\(m)" : m
                }
            }
        }
    }
}
