import SwiftUI

/// 我的：提交上报（唯一上报出口）+ 设置项
struct ProfileView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var store: Store
    @State private var syncing = false
    @State private var showConfirm = false
    @State private var resultMsg = ""
    @State private var showAbout = false
    @State private var versionText = "检测中…"

    var body: some View {
        NavigationView {
            List {
                // 用户信息
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill").font(.system(size: 44)).foregroundColor(Color(hex: 0x2E7D32))
                        VStack(alignment: .leading) {
                            Text(session.user.name.isEmpty ? "未登录" : session.user.name).font(.headline)
                            Text("\(session.user.role) · \(session.user.org)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 提交上报
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("待上报记录 \(store.pendingRecords.count) 条").font(.headline)
                        if store.draftCount > 0 { Text("草稿 \(store.draftCount) 条").font(.caption) }
                        if !store.events.isEmpty { Text("待提交任务事件 \(store.events.count) 个").font(.caption) }
                        if !store.locationQueue.isEmpty { Text("待补传位置 \(store.locationQueue.count) 点").font(.caption) }
                        Text("调查表点「保存」后数据只存在本机；联网时点下面按钮，一次性把记录、轨迹、任务事件与位置点全部提交到服务器。")
                            .font(.caption).foregroundColor(.secondary)
                        Button(action: { showConfirm = true }) {
                            HStack {
                                if syncing { ProgressView().tint(.white) }
                                Text(syncing ? "提交中…" : "立即提交上报").fontWeight(.semibold)
                            }.frame(maxWidth: .infinity).padding(10)
                            .background(Color(hex: 0x1B5E20)).foregroundColor(.white).cornerRadius(8)
                        }
                        .disabled(syncing)
                        if !resultMsg.isEmpty { Text(resultMsg).font(.caption).foregroundColor(.secondary) }
                    }
                } header: {
                    Text("提交上报（本机数据上传的唯一入口）")
                }

                // 设置
                Section("同步与地图") {
                    Button("立即检查服务端") { Task { try? await SyncService.shared.refreshConfig() } }
                    NavigationLink {
                        LayerPickerSimple().environmentObject(store)
                    } label: {
                        settingRow("底图与图层", "\(store.layers.filter { $0.visible }.count) 图层")
                    }
                    HStack {
                        Text("位置上报").font(.subheadline)
                        Spacer()
                        Toggle("", isOn: Binding(get: { session.locationReportEnabled },
                                                 set: { session.setLocationReport($0) }))
                    }
                }

                Section("对讲与状态") {
                    HStack {
                        Image(systemName: "radio.fill")
                        Text("对讲机")
                        Spacer()
                        Text(pttStatus).font(.caption).foregroundColor(.secondary)
                    }
                }

                Section {
                    Button("同步服务端配置") { Task { try? await SyncService.shared.refreshConfig() } }
                    HStack { Text("版本更新"); Spacer(); Text(versionText).font(.caption).foregroundColor(.secondary) }
                    Button("关于软件") { showAbout = true }
                    Button("退出登录", role: .destructive) { logout() }
                }
            }
            .navigationTitle("我的")
            .alert("确认上传本机数据？", isPresented: $showConfirm) {
                Button("确认上传") { doSync() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将上传待上报记录 \(store.pendingRecords.count) 条、任务事件 \(store.events.count) 个、位置 \(store.locationQueue.count) 点。")
            }
            .sheet(isPresented: $showAbout) { aboutView }
            .onAppear {
                Task {
                    if let v = await API.shared.appVersion() {
                        await MainActor.run { versionText = v.versionCode > 188 ? "有新版本 v\(v.versionName)" : "当前 v1.0.188" }
                    } else {
                        await MainActor.run { versionText = "当前 v1.0.188" }
                    }
                }
            }
        }
    }

    private var pttStatus: String { PttService.shared.status.rawValue }

    private func settingRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).font(.caption).foregroundColor(.secondary) }
    }

    private func doSync() {
        syncing = true; resultMsg = ""
        Task {
            let s = await SyncService.shared.pushAll()
            await MainActor.run {
                syncing = false
                if !s.configOk && s.message.contains("连不上") {
                    resultMsg = "提交失败：无法连接服务器（数据已保存在本机，联网后再试）"
                } else if !s.hasData {
                    resultMsg = "没有待上报的数据"
                } else if s.skippedRecords > 0 {
                    resultMsg = "有 \(s.skippedRecords) 条记录的所属任务仍在记录航迹——结束任务后才能上传"
                } else {
                    resultMsg = "提交完成：\(s.text)"
                }
            }
        }
    }

    private func logout() {
        Task { await API.shared.logout() }
        session.logout()
        Store.shared.clearAll()
        PttService.shared.disconnect()
        LocationService.shared.stopTracking()
    }

    private var aboutView: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("保护地巡护 v1.0.188").font(.title2.bold())
                    Text("功能：离线地图与矢量图层、航迹记录、动态表单填报（拍照/签名/定位）、队友协同、对讲、离线存储与联网上报。").font(.body)
                    Divider()
                    Text("数据与隐私").font(.headline)
                    Text("当前服务器：\(session.baseUrl)").font(.caption)
                    Text("位置信息用于地图显示与在线状态判定，就近上报，仅在App授权范围内使用。").font(.caption).foregroundColor(.secondary)
                    Text("注意：iOS 无应用内自更新与悬浮窗能力，更新需重新安装，对讲在 App 内使用。").font(.caption).foregroundColor(.orange)
                }.padding()
            }
            .navigationTitle("关于软件")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { showAbout = false } } }
        }
    }
}

struct LayerPickerSimple: View {
    @EnvironmentObject var store: Store
    var body: some View {
        List {
            ForEach(store.layers) { l in
                HStack {
                    Circle().fill(Color(hex: UInt(l.color.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x2E7D32))
                        .frame(width: 10, height: 10)
                    Text(l.name)
                    Spacer()
                    Text(l.visible ? "显示" : "隐藏").font(.caption).foregroundColor(.secondary)
                }
            }
        }.navigationTitle("底图与图层")
    }
}
