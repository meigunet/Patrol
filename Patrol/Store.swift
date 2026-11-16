import Foundation
import Combine

/// 本地离线数据仓（对应安卓 Room）。Codable 落 JSON 文件。
/// 注意：iOS 无 CursorWindow 单行 2MB 限制，照片 base64 直接随记录存，无需安卓那套外置 blob。
final class Store: ObservableObject {
    static let shared = Store()

    @Published var templates: [TemplateDto] = []
    @Published var layers: [LayerDto] = []
    @Published var tasks: [TaskDto] = []
    @Published var records: [RecordDto] = []
    @Published var mapConfig: MapConfigDto?
    @Published var announcement: AnnouncementDto?
    @Published var configRevision: String = ""
    @Published var packages: [PackageDto] = []

    // 本机运行态
    @Published var runs: [TaskRunLocal] = []
    @Published var events: [TaskEventLocal] = []
    @Published var locationQueue: [LocationQueueItem] = []
    @Published var trackPoints: [Int64: [TrackPointDto]] = [:]   // runId -> points
    @Published var recordingTaskIds: Set<Int64> = []

    private let fm = FileManager.default
    private let dir: URL
    private let queue = DispatchQueue(label: "patrol.store.write", qos: .background)

    private init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("patrol_data", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        loadAll()
    }

    // MARK: - 文件
    private func file(_ name: String) -> URL { dir.appendingPathComponent(name + ".json") }

    private func load<T: Decodable>(_ name: String, fallback: T) -> T {
        guard let d = try? Data(contentsOf: file(name)),
              let v = try? JSONDecoder().decode(T.self, from: d) else { return fallback }
        return v
    }

    func save<T: Encodable>(_ value: T, _ name: String) {
        queue.async {
            guard let d = try? JSONEncoder().encode(value) else { return }
            let tmp = self.file(name).appendingPathExtension("tmp")
            try? d.write(to: tmp, options: .atomic)
            try? self.fm.replaceItemAt(self.file(name), withItemAt: tmp)
        }
    }

    private func loadAll() {
        templates = load("templates", fallback: [TemplateDto]())
        layers = load("layers", fallback: [LayerDto]())
        tasks = load("tasks", fallback: [TaskDto]())
        records = load("records", fallback: [RecordDto]())
        mapConfig = load("mapconfig", fallback: Optional<MapConfigDto>.none)
        announcement = load("announcement", fallback: Optional<AnnouncementDto>.none)
        configRevision = load("revision", fallback: "")
        packages = load("packages", fallback: [PackageDto]())
        runs = load("runs", fallback: [TaskRunLocal]())
        events = load("events", fallback: [TaskEventLocal]())
        locationQueue = load("locqueue", fallback: [LocationQueueItem]())
        trackPoints = load("trackpoints", fallback: [Int64: [TrackPointDto]]())
        recordingTaskIds = load("recording", fallback: Set<Int64>())
    }

    // MARK: - 写入配置
    func applyPull(_ pull: SyncPullResponse) {
        if !pull.templates.isEmpty { templates = latestPerForm(pull.templates); save(templates, "templates") }
        if !pull.layers.isEmpty { layers = pull.layers; save(layers, "layers") }
        if let mc = pull.mapConfig { mapConfig = mc; save(mc, "mapconfig") }
        if !pull.tasks.isEmpty || !tasks.isEmpty {
            tasks = pull.tasks; save(tasks, "tasks")
        }
        if !pull.packages.isEmpty { packages = pull.packages; save(packages, "packages") }
        if let rev = pull.revision, !rev.isEmpty { configRevision = rev; save(rev, "revision") }
    }

    /// 同 formId 只留 published 且版本最大者
    private func latestPerForm(_ all: [TemplateDto]) -> [TemplateDto] {
        var best: [String: TemplateDto] = [:]
        for t in all where t.published {
            if let cur = best[t.formId], cur.version >= t.version { continue }
            best[t.formId] = t
        }
        return Array(best.values)
    }

    func template(formId: String) -> TemplateDto? { templates.first { $0.formId == formId } }
    func task(id: Int64) -> TaskDto? { tasks.first { $0.id == id } }

    // MARK: - 记录
    func saveRecord(_ r: RecordDto) {
        if let i = records.firstIndex(where: { $0.clientUuid == r.clientUuid }) {
            records[i] = r
        } else {
            records.insert(r, at: 0)
        }
        save(records, "records")
    }

    func record(uuid: String) -> RecordDto? { records.first { $0.clientUuid == uuid } }
    func records(taskId: Int64) -> [RecordDto] { records.filter { $0.taskId == taskId } }
    func records(runId: Int64) -> [RecordDto] { records.filter { $0.runId == runId } }

    func deleteRecord(uuid: String) {
        records.removeAll { $0.clientUuid == uuid }
        save(records, "records")
    }

    /// 删除整条流水（记录 + 航迹）
    func deleteRun(_ runId: Int64) {
        records.removeAll { $0.runId == runId }
        trackPoints.removeValue(forKey: runId)
        runs.removeAll { $0.runId == runId }
        save(records, "records"); save(trackPoints, "trackpoints"); save(runs, "runs")
    }

    func markAccepted(uuids: [String]) {
        for u in uuids {
            if let i = records.firstIndex(where: { $0.clientUuid == u }) {
                records[i].status = "ACCEPTED"
                records[i].pendingUpdate = false
            }
        }
        save(records, "records")
    }

    var pendingRecords: [RecordDto] { records.filter { $0.status == "SUBMITTED" } }
    var draftCount: Int { records.filter { $0.status == "DRAFT" }.count }

    // MARK: - 流水号 / 任务事件
    @discardableResult
    func ensureRun(taskId: Int64) -> TaskRunLocal {
        if let r = runs.first(where: { $0.taskId == taskId && $0.status != "DONE" }) { return r }
        let code = task(id: taskId)?.code ?? "T"
        let serial = "\(code)-\(TimeUtil.nowCompact())" + String(format: "%03d", Int.random(in: 0..<1000))
        let r = TaskRunLocal(runId: Int64(Date().timeIntervalSince1970 * 1000), taskId: taskId,
                             serialNo: serial, createdAt: TimeUtil.iso(), status: "PENDING")
        runs.insert(r, at: 0); save(runs, "runs")
        return r
    }

    func currentRun(taskId: Int64) -> TaskRunLocal? { runs.first { $0.taskId == taskId && $0.status != "DONE" } }
    func recentDoneRuns(taskId: Int64, limit: Int = 5) -> [TaskRunLocal] {
        Array(runs.filter { $0.taskId == taskId && $0.status == "DONE" }.prefix(limit))
    }

    func startTask(taskId: Int64) {
        let r = ensureRun(taskId: taskId)
        if let i = runs.firstIndex(where: { $0.runId == r.runId }) {
            runs[i].trackStartedAt = TimeUtil.iso(); runs[i].status = "DOING"
        }
        recordingTaskIds.insert(taskId)
        addEvent(taskId: taskId, event: "START")
        save(runs, "runs"); save(recordingTaskIds, "recording")
    }

    func finishTask(taskId: Int64) {
        var removedRun: Int64? = nil
        if let r = currentRun(taskId: taskId) {
            let count = records(taskId: taskId).filter { $0.runId == r.runId }.count
            if count == 0 {
                // 只有航迹没填表 → 删除整条流水与航迹
                records.removeAll { $0.runId == r.runId }
                trackPoints.removeValue(forKey: r.runId)
                runs.removeAll { $0.runId == r.runId }
                removedRun = r.runId
                save(records, "records"); save(trackPoints, "trackpoints")
            } else if let i = runs.firstIndex(where: { $0.runId == r.runId }) {
                runs[i].endedAt = TimeUtil.iso(); runs[i].status = "DONE"
                addEvent(taskId: taskId, event: "DONE")
            }
        }
        recordingTaskIds.remove(taskId)
        // 移除本任务重复的 START 事件（本轮没填表时）
        if removedRun != nil {
            events.removeAll { $0.taskId == taskId && $0.event == "START" }
            save(events, "events")
        }
        save(runs, "runs"); save(recordingTaskIds, "recording")
    }

    func addEvent(taskId: Int64, event: String) {
        events.append(TaskEventLocal(taskId: taskId, event: event, createdAt: TimeUtil.iso()))
        save(events, "events")
    }

    // MARK: - 航迹点
    func points(runId: Int64) -> [TrackPointDto] { trackPoints[runId] ?? [] }
    func appendPoint(runId: Int64, lat: Double, lng: Double, alt: Double, accuracy: Float, speed: Float) {
        let pts = trackPoints[runId] ?? []
        let p = TrackPointDto(trackId: runId, seq: pts.count, lat: lat, lng: lng, alt: alt,
                              speed: speed, accuracy: accuracy, time: TimeUtil.iso())
        var arr = pts; arr.append(p)
        trackPoints[runId] = arr
        save(trackPoints, "trackpoints")
    }

    // MARK: - 位置补传队列
    func enqueueLocation(lat: Double, lng: Double, accuracy: Float?, at: String) {
        locationQueue.append(LocationQueueItem(lat: lat, lng: lng, accuracy: accuracy, at: at))
        save(locationQueue, "locqueue")
    }
    func clearLocations(uuids: [String]) {
        locationQueue.removeAll { uuids.contains($0.clientUuid) }
        save(locationQueue, "locqueue")
    }

    // MARK: - 清空（注销）
    func clearAll() {
        templates = []; layers = []; tasks = []; records = []; mapConfig = nil
        announcement = nil; configRevision = ""; packages = []
        runs = []; events = []; locationQueue = []; trackPoints = [:]; recordingTaskIds = []
        let names = ["templates","layers","tasks","records","mapconfig","announcement","revision","packages","runs","events","locqueue","trackpoints","recording"]
        for n in names { try? fm.removeItem(at: file(n)) }
    }
}
