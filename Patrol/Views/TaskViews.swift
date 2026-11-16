import SwiftUI

// MARK: - 任务列表
struct TaskListView: View {
    @EnvironmentObject var store: Store
    @State private var subFilter = 0
    @State private var refreshing = false

    private let filters = ["全部", "巡护", "调查监测"]

    private var filtered: [TaskDto] {
        var list = store.tasks
        if subFilter == 1 { list = list.filter { $0.category.contains("patrol") || $0.category.isEmpty } }
        if subFilter == 2 { list = list.filter { $0.category.contains("survey") } }
        return list.sorted { a, b in
            let ra = store.recordingTaskIds.contains(a.id) ? 2 : 0
            let rb = store.recordingTaskIds.contains(b.id) ? 2 : 0
            if ra != rb { return ra > rb }
            return a.id > b.id
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $subFilter) {
                    ForEach(0..<filters.count, id: \.self) { Text(filters[$0]).tag($0) }
                }.pickerStyle(.segmented).padding()

                List {
                    if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Text("暂无任务").font(.headline)
                            Text("新建任务请在网页端「任务管理」创建（可关联多个表单）").font(.caption).foregroundColor(.secondary)
                            Text("流程：点任务 → 开始任务 → 填报").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding()
                    }
                    ForEach(filtered) { task in
                        NavigationLink { TaskDetailView(task: task) } label: { TaskCard(task: task) }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle(subFilter == 1 ? "巡护任务" : subFilter == 2 ? "调查监测" : "巡护监测")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { refresh() } label: {
                        if refreshing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                }
            }
            .refreshable { await refreshAsync() }
        }
    }

    private func refresh() { Task { await refreshAsync() } }
    private func refreshAsync() async {
        await MainActor.run { refreshing = true }
        try? await SyncService.shared.refreshConfig()
        await MainActor.run { refreshing = false }
    }
}

struct TaskCard: View {
    @EnvironmentObject var store: Store
    let task: TaskDto

    private var recording: Bool { store.recordingTaskIds.contains(task.id) }
    private var recordCount: Int { store.records(taskId: task.id).count }
    private var pendingCount: Int { store.records(taskId: task.id).filter { $0.status != "ACCEPTED" }.count }
    private var formTitles: String {
        task.effectiveFormIds.compactMap { store.template(formId: $0)?.title }.joined(separator: "、")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.title).font(.headline)
                if recording {
                    Text("● 调查进行中").font(.caption2).foregroundColor(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15)).cornerRadius(4)
                }
            }
            Text("任务号 \(task.code) · \(task.areaName)").font(.caption).foregroundColor(.secondary)
            Text("计划 \(task.planStart) ~ \(task.planEnd)").font(.caption).foregroundColor(.secondary)
            if !formTitles.isEmpty { Text("表单：\(formTitles)").font(.caption).foregroundColor(.secondary) }

            if recording {
                Text("● 调查进行中 · 点此查看 / 填报").font(.caption).foregroundColor(.orange)
            } else if recordCount > 0 {
                Text("已填报 \(recordCount) 条 · 点此查看 / 修改 / 删除").font(.caption).foregroundColor(Color(hex: 0x2E7D32))
            } else {
                Text("点此进入任务：开始任务（记录航迹）后即可填报").font(.caption).foregroundColor(.secondary)
            }
            if pendingCount > 0 {
                Text("本机有 \(pendingCount) 条记录未上报，联网后到「我的 → 提交上报」上传")
                    .font(.caption2).foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 任务详情（开始/结束 + 填报入口）
struct TaskDetailView: View {
    @EnvironmentObject var store: Store
    let task: TaskDto
    @State private var showFinishConfirm = false
    @State private var toast = ""
    @State private var activeFormId: String? = nil

    private var recording: Bool { store.recordingTaskIds.contains(task.id) }
    private var currentRun: TaskRunLocal? { store.currentRun(taskId: task.id) }
    private var points: Int {
        guard let r = currentRun else { return 0 }
        return store.points(runId: r.runId).count
    }
    private var roundRecords: Int {
        guard let r = currentRun else { return 0 }
        return store.records(runId: r.runId).count
    }
    private var pendingCount: Int { store.records(taskId: task.id).filter { $0.status != "ACCEPTED" }.count }

    var body: some View {
        List {
            Section("任务信息") {
                Text("任务号 \(task.code) · \(task.areaName)").font(.caption)
                Text("计划 \(task.planStart) ~ \(task.planEnd)").font(.caption)
                if let run = currentRun {
                    Text("本次作业流水号：\(TimeUtil.shortSerial(run.serialNo)) · \(statusText(run.status))")
                        .font(.caption).foregroundColor(.orange).bold()
                }
                Text("关联表单 \(task.effectiveFormIds.count) 个 · 已填报 \(store.records(taskId: task.id).count) 条（草稿/待上报 \(pendingCount) 条）")
                    .font(.caption)
                if recording && roundRecords == 0 {
                    Text("本次作业还没有填表：只有航迹的作业不能上报，点「完成任务」后这条流水号与航迹会自动删除（不可恢复）")
                        .font(.caption).foregroundColor(.red)
                }
                if recording {
                    Text("● 调查进行中 · 已记录 \(points) 个航迹点")
                        .font(.caption).foregroundColor(.orange)
                }
            }

            if task.recordTrack {
                Section {
                    if recording {
                        Button("完成任务") { showFinishConfirm = true }
                            .foregroundColor(.orange)
                    } else {
                        Button("开始任务") { startTask() }
                    }
                    Text("点「开始任务」即开始记录航迹，之后按下方表格填报；点「完成任务」即停止航迹。航迹未停止前，本任务的记录与表格不会上传。")
                        .font(.caption2).foregroundColor(.secondary)
                }
            } else {
                Section {
                    Text("本条任务未开启「记录任务轨迹」，可直接按下方表格填报。").font(.caption).foregroundColor(.secondary)
                }
            }

            Section(recording || !task.recordTrack ? "调查表格（点此填报，每条记录即采集点）" : "调查表格（开始任务后可填报）") {
                ForEach(task.effectiveFormIds, id: \.self) { fid in
                    Button {
                        if !recording && task.recordTrack {
                            toast = "请先点上方「开始任务」，开始后才能填报"
                        } else {
                            activeFormId = fid
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text(store.template(formId: fid)?.title ?? fid)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
                if task.effectiveFormIds.isEmpty {
                    Text("该任务没有关联表单，请在网页端编辑任务添加。").font(.caption).foregroundColor(.secondary)
                }
            }

            Section {
                NavigationLink("任务航迹地图") {
                    TaskTrackView(task: task).environmentObject(store)
                }
            }
        }
        .navigationTitle(task.title)
        .alert("确认完成任务？", isPresented: $showFinishConfirm) {
            Button("确认完成", role: .destructive) {
                store.finishTask(taskId: task.id)
                toast = roundRecords == 0
                    ? "任务已完成：本次只有航迹没有表格，流水号、航迹与待提交事件已全部清除"
                    : "任务已完成，航迹已停止；未上报的记录到「我的 → 提交上报」上传"
            }
            Button("继续调查", role: .cancel) {}
        } message: {
            if roundRecords == 0 {
                Text("本次只有航迹没有表格：流水号、航迹、开始结束事件将全部清除、不留下任何待提交内容、不可恢复。建议先填表。")
            } else {
                Text("立即停止航迹记录（当前 \(points) 个航迹点，本次已填 \(roundRecords) 条表格），记录与表格停止后才允许提交上报。")
            }
        }
        .sheet(item: $activeFormId) { fid in
            NavigationView {
                DynamicFormView(formId: fid, taskId: task.id, editUuid: nil)
                    .environmentObject(store)
            }
        }
        .overlay(alignment: .bottom) {
            if !toast.isEmpty {
                Text(toast).font(.caption).padding(10)
                    .background(Color.black.opacity(0.75)).foregroundColor(.white).cornerRadius(8)
                    .padding(.bottom, 20)
                    .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { toast = "" } }
            }
        }
    }

    private func statusText(_ s: String) -> String {
        s == "PENDING" ? "待开始" : s == "DOING" ? "进行中" : "已完成"
    }
    private func startTask() {
        let status = LocationService.shared.authorizationStatus
        if status != .authorizedAlways && status != .authorizedWhenInUse {
            LocationService.shared.requestPermission()
            toast = "未授予定位权限，无法开始任务（需要记录航迹）"
            return
        }
        store.startTask(taskId: task.id)
        LocationService.shared.startTracking()
        toast = "任务已开始，调查进行中（航迹后台持续记录）"
    }
}

// MARK: - 任务航迹地图（复用 map.html 的任务模式）
struct TaskTrackView: View {
    @EnvironmentObject var store: Store
    let task: TaskDto
    @State private var selectedRun: Int64? = nil

    private var runs: [TaskRunLocal] { store.recentDoneRuns(taskId: task.id) }
    private var activeRun: TaskRunLocal? {
        runs.first { $0.runId == selectedRun } ?? runs.first
    }
    private var pts: [TrackPointDto] {
        guard let r = activeRun else { return [] }
        return store.points(runId: r.runId)
    }
    private var totalKm: Double {
        var d = 0.0
        if pts.count > 1 {
            for i in 1..<pts.count {
                d += GeoUtil.haversine((pts[i-1].lat, pts[i-1].lng), (pts[i].lat, pts[i].lng))
            }
        }
        return d / 1000
    }

    var body: some View {
        VStack(spacing: 0) {
            if runs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "map").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("该任务暂无已完成的作业——结束任务后，这一趟的航迹才会出现在这里")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker("流水号", selection: $selectedRun) {
                    ForEach(runs) { r in
                        Text("\(TimeUtil.shortSerial(r.serialNo)) · \(r.status == "DONE" ? "已完成" : r.status)").tag(Optional(r.runId))
                    }
                }.pickerStyle(.menu).padding()

                HStack(spacing: 16) {
                    Stat(title: "航迹", value: "\(pts.count) 点 / \(String(format: "%.1f", totalKm)) km")
                    Stat(title: "采集点", value: "\(store.records(runId: activeRun?.runId ?? -1).count) 个")
                    Stat(title: "状态", value: activeRun?.status ?? "-")
                }.padding(.horizontal)

                TrackMapView(points: pts, records: store.records(runId: activeRun?.runId ?? -1), store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("任务航迹")
    }
}

struct Stat: View {
    let title: String; let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption.bold())
        }.frame(maxWidth: .infinity)
    }
}
