import Foundation

struct SyncSummary {
    var configOk = false
    var pushedRecords = 0
    var pushedTracks = 0
    var pushedEvents = 0
    var pushedLocations = 0
    var skippedRecords = 0
    var message: String = ""

    var hasData: Bool { pushedRecords + pushedTracks + pushedEvents + pushedLocations > 0 }
    var text: String {
        "记录 \(pushedRecords) 条（更新 0）· 轨迹 \(pushedTracks) 条 · 任务事件 \(pushedEvents) 个 · 位置 \(pushedLocations) 点"
    }
}

/// 数据同步：refreshConfig + pushAll（对应 PatrolRepository.syncNow / pushAll）
final class SyncService {
    static let shared = SyncService()
    private init() {}

    private let api = API.shared
    private let store = Store.shared

    /// 拉取服务端配置写入本地
    func refreshConfig() async throws {
        let pull = try await api.syncPull()
        store.applyPull(pull)
        await syncLayersToLocal(pull.layers)
    }

    /// 图层 GeoJSON 下载到本地（离线可用）
    private func syncLayersToLocal(_ layers: [LayerDto]) async {
        let root = URLTool.serverRoot(Session.shared.baseUrl)
        for l in layers where ["GEOJSON","SHP","KMZ","KML"].contains(l.format.uppercased()) && !l.url.isEmpty {
            var u = l.url
            if !u.hasPrefix("http") { u = root + "/" + u.replacingOccurrences(of: "^/", with: "", options: .regularExpression) }
            u = u.replacingOccurrences(of: ".shp", with: ".geojson", options: [.caseInsensitive])
                .replacingOccurrences(of: ".kmz", with: ".geojson", options: [.caseInsensitive])
                .replacingOccurrences(of: ".kml", with: ".geojson", options: [.caseInsensitive])
            await LocalMapStore.shared.downloadLayer(id: l.id, url: u, updatedAt: l.updatedAt)
        }
    }

    /// 上报：把本机 SUBMITTED 记录、航迹、任务事件、位置点一次性推到服务端
    func pushAll() async -> SyncSummary {
        var summary = SyncSummary()

        do { try await refreshConfig(); summary.configOk = true }
        catch { summary.message = ErrorText.friendly(error) }

        let recording = store.recordingTaskIds
        let pending = store.pendingRecords.filter { r in
            guard let tid = r.taskId else { return true }
            return !recording.contains(tid)
        }
        summary.skippedRecords = store.pendingRecords.count - pending.count

        let events = store.events
        let runWithRecords = Set(pending.compactMap { $0.runId })

        // 组装记录级 + 任务级航迹
        var tracks: [TrackDto] = []
        for r in pending {
            let pts = trackPointsForRecord(r)
            if !pts.isEmpty {
                tracks.append(TrackDto(recordUuid: r.clientUuid, taskId: r.taskId, runId: r.runId,
                                       userId: r.userId, startedAt: pts.first?.time ?? "",
                                       endedAt: pts.last?.time ?? "", points: pts))
            }
        }
        for rid in runWithRecords {
            let pts = store.points(runId: rid)
            if !pts.isEmpty, let run = store.runs.first(where: { $0.runId == rid }) {
                tracks.append(TrackDto(taskId: run.taskId, runId: rid, userId: Session.shared.user.id,
                                       startedAt: pts.first?.time ?? "", endedAt: pts.last?.time ?? "", points: pts))
            }
        }
        let runDtos = store.runs.filter { runWithRecords.contains($0.runId) }.map { r in
            TaskRunDto(runId: r.runId, taskId: r.taskId, serialNo: r.serialNo,
                       createdAt: r.createdAt, trackStartedAt: r.trackStartedAt,
                       endedAt: r.endedAt, status: r.status)
        }
        let eventDtos = events.map { TaskEventDto(taskId: $0.taskId, event: $0.event) }

        if !pending.isEmpty || !tracks.isEmpty || !eventDtos.isEmpty {
            let req = SyncPushRequest(records: pending, tracks: tracks, taskEvents: eventDtos, taskRuns: runDtos)
            do {
                let resp = try await api.syncPush(req)
                let failed = Set(resp.records.errors.compactMap { $0.clientUuid })
                let okUuids = pending.map { $0.clientUuid }.filter { !failed.contains($0) }
                store.markAccepted(uuids: okUuids)
                summary.pushedRecords = okUuids.count
                summary.pushedTracks = resp.tracks
                summary.pushedEvents = resp.taskEvents
                if resp.taskEvents > 0 { store.events.removeAll(); store.saveEvents() }
                if !tracks.isEmpty { store.markTracksSynced(ids: runWithRecords) }
            } catch {
                summary.message = ErrorText.friendly(error)
            }
        }

        // 补传位置队列
        if !store.locationQueue.isEmpty {
            let points = store.locationQueue.map {
                LocationPointDto(clientUuid: $0.clientUuid, lat: $0.lat, lng: $0.lng, accuracy: $0.accuracy, at: $0.at)
            }
            if let resp = await api.uploadLocations(points) {
                let failed = Set(resp.errors.compactMap { $0.clientUuid })
                let ok = points.map { $0.clientUuid }.filter { !failed.contains($0) }
                store.clearLocations(uuids: ok)
                summary.pushedLocations = ok.count
            }
        }
        return summary
    }

    /// 记录级轨迹：优先任务航迹中该 runId 的点（记录与任务共用任务航迹）
    private func trackPointsForRecord(_ r: RecordDto) -> [TrackPointDto] {
        guard let rid = r.runId else { return [] }
        return store.points(runId: rid)
    }
}

// Store 的小扩展（避免把 save 细节散落）
extension Store {
    func saveEvents() { save(events, "events") }
    func markTracksSynced(ids: Set<Int64>) { /* iOS 端航迹复用任务航迹，无需单独标记同步态 */ }
}
