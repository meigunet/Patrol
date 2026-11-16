import SwiftUI

/// 上报记录：按流水号分组 + 展开折叠 + 删除
struct RecordsView: View {
    @EnvironmentObject var store: Store
    @State private var expanded: Set<Int64> = []
    @State private var syncInfo: RecordSyncInfo? = nil
    @State private var syncInfoLoading = false

    private var grouped: [(Int64, [RecordDto])] {
        let groups = Dictionary(grouping: store.records) { $0.runId ?? -1 }
        return groups.map { ($0.key, $0.value) }.sorted { $0.0 > $1.0 }
    }

    private var pendingCount: Int { store.pendingRecords.count }

    var body: some View {
        NavigationView {
            List {
                if pendingCount > 0 || store.draftCount > 0 || !store.events.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("待上报 \(pendingCount) 条").font(.headline)
                            if store.draftCount > 0 { Text("草稿 \(store.draftCount) 条（补全后才会上传）").font(.caption) }
                            if !store.events.isEmpty { Text("待提交任务事件 \(store.events.count) 个").font(.caption) }
                            if !store.locationQueue.isEmpty { Text("待补传位置 \(store.locationQueue.count) 点").font(.caption) }
                            Text("调查表点「保存」只存本机，联网后到「我的 → 提交上报」一次性上传。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                if store.records.isEmpty {
                    VStack(spacing: 8) {
                        Text("暂无填报记录").font(.headline)
                        Text("在「巡护监测」页进入任务，开始后填报").font(.caption).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity).padding()
                }

                ForEach(grouped, id: \.0) { runId, recs in
                    Section {
                        if expanded.contains(runId) || runId == -1 && expanded.isEmpty {
                            ForEach(recs.sorted { ($0.submittedAt ?? "") > ($1.submittedAt ?? "") }) { rec in
                                RecordRow(rec: rec) {
                                    if rec.status == "ACCEPTED" { loadSyncInfo(rec.clientUuid) }
                                }
                            }
                            // 整条流水删除（仅当无 ACCEPTED）
                            if runId >= 0 && !recs.contains(where: { $0.status == "ACCEPTED" }) {
                                Button("删除整条流水", role: .destructive) { store.deleteRun(runId) }
                                    .font(.caption)
                            }
                        }
                    } header: {
                        Button {
                            if expanded.contains(runId) { expanded.remove(runId) } else { expanded.insert(runId) }
                        } label: {
                            HStack {
                                Text(runId < 0 ? "未归档记录" : "流水号 \(shortRun(runId, recs))")
                                Text("\(recs.count) 条填报 · 点击展开/收起").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Image(systemName: expanded.contains(runId) ? "chevron.up" : "chevron.down")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("上报记录")
            .sheet(item: $syncInfo) { info in SyncInfoView(info: info) }
            .overlay {
                if syncInfoLoading { ProgressView().padding().background(.regularMaterial).cornerRadius(8) }
            }
            .onAppear {
                if expanded.isEmpty, let first = grouped.first { expanded.insert(first.0) }
            }
        }
    }

    private func shortRun(_ runId: Int64, _ recs: [RecordDto]) -> String {
        // 流水号短号存在 run 里；这里从 runId 反查
        if let run = store.runs.first(where: { $0.runId == runId }) { return TimeUtil.shortSerial(run.serialNo) }
        return String(runId)
    }

    private func loadSyncInfo(_ uuid: String) {
        syncInfoLoading = true
        Task {
            let info = await API.shared.recordSyncInfo(uuid: uuid)
            await MainActor.run { syncInfoLoading = false; syncInfo = info }
        }
    }
}

struct RecordRow: View {
    @EnvironmentObject var store: Store
    let rec: RecordDto
    let onTap: () -> Void

    private var formTitle: String { store.template(formId: rec.formId)?.title ?? rec.formId }
    private var statusText: String {
        rec.status == "DRAFT" ? "草稿" : rec.status == "SUBMITTED" ? "待上报" : "已同步"
    }
    private var statusColor: Color {
        rec.status == "DRAFT" ? .orange : rec.status == "SUBMITTED" ? Color(hex: 0x2E7D32) : .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formTitle).font(.subheadline.bold())
                Spacer()
                Text(statusText).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(statusColor.opacity(0.15)).foregroundColor(statusColor).cornerRadius(4)
            }
            if let tid = rec.taskId, let task = store.task(id: tid) {
                Text("任务：\(task.title) · \(TimeUtil.display(rec.submittedAt))").font(.caption).foregroundColor(.secondary)
            } else {
                Text("提交：\(TimeUtil.display(rec.submittedAt))").font(.caption).foregroundColor(.secondary)
            }
            if rec.distanceM > 0 { Text("里程 \(String(format: "%.2f", Double(rec.distanceM)/1000)) km").font(.caption2).foregroundColor(.secondary) }

            if rec.status == "ACCEPTED" {
                Text("已上报到服务端，手机端不可修改或删除；点击卡片可查看同步信息")
                    .font(.caption2).foregroundColor(.secondary)
                    .onTapGesture { onTap() }
            } else {
                NavigationLink("编辑") {
                    DynamicFormView(formId: rec.formId, taskId: rec.taskId, editUuid: rec.clientUuid)
                        .environmentObject(store)
                }
                .font(.caption)
                Button("删除", role: .destructive) { store.deleteRecord(uuid: rec.clientUuid) }.font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SyncInfoView: View {
    let info: RecordSyncInfo
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            List {
                row("同步状态", info.synced ? "✓ 已同步到服务器" : "未同步")
                if let id = info.serverId { row("服务端记录号", String(id)) }
                row("同步时间", TimeUtil.display(info.syncedAt))
                row("最近更新", TimeUtil.display(info.updatedAt))
                row("服务端状态", info.status)
                row("所属表单", "\(info.formTitle)（v\(info.formVersion)）")
                if let t = info.taskTitle { row("所属任务", t) }
                row("上报人", "\(info.userName)（\(info.userAccount)）")
                row("轨迹", "\(info.trackCount) 条 / \(info.trackPointCount) 个点")
                row("里程", String(format: "%.2f km", Double(info.distanceM)/1000))
                row("时长", TimeUtil.durationText(info.durationS))
                if let lat = info.lat, let lng = info.lng {
                    row("采集点", "\(lat),\(lng) · 海拔 \(String(format: "%.0f", info.alt ?? 0)) m")
                }
                row("本机编号", info.clientUuid)
            }
            .navigationTitle("服务端同步信息")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).frame(width: 100, alignment: .leading).font(.caption).foregroundColor(.secondary); Text(v).font(.caption) }
    }
}

extension RecordSyncInfo: Identifiable {
    var id: String { clientUuid.isEmpty ? UUID().uuidString : clientUuid }
}
