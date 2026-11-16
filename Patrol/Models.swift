import Foundation

// MARK: - 通用 JSON 值（表单 data 是任意结构的对象）
indirect enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var stringValue: String? {
        switch self { case .string(let v): return v; default: return nil }
    }
    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
    var boolValue: Bool? {
        switch self { case .bool(let v): return v; default: return nil }
    }
    var arrayValue: [JSONValue]? {
        switch self { case .array(let v): return v; default: return nil }
    }
    var objectValue: [String: JSONValue]? {
        switch self { case .object(let v): return v; default: return nil }
    }
    var isEmpty: Bool {
        switch self {
        case .null: return true
        case .string(let v): return v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let v): return v.isEmpty
        default: return false
        }
    }
}

typealias JSONDict = [String: JSONValue]

// MARK: - 登录
struct TokenPair: Codable {
    var accessToken: String = ""
    var refreshToken: String = ""
    var expiresIn: Int = 0
}

struct UserDto: Codable {
    var id: Int64 = 0
    var name: String = ""
    var account: String = ""
    var role: String = ""
    var org: String = ""
    var tel: String = ""
    var state: String = "正常"
}

struct LoginResponse: Codable {
    var token: TokenPair = TokenPair()
    var user: UserDto = UserDto()
}

// MARK: - 地图配置
struct OnlineMapDto: Codable {
    var enabled: Bool = false
    var name: String = "在线地图"
    var type: String = "xyz"
    var provider: String = "custom"
    var url: String = ""
    var key: String = ""
    var subdomains: String = ""
    var attribution: String = ""
    var maxZoom: Int = 18
    var layer: String = ""
    var style: String = "default"
    var tileMatrixSet: String = ""
    var format: String = "image/png"
    var proxy: Bool = false
}

struct BaseMap: Codable {
    var id: String = ""
    var kind: String = "builtin"
    var key: String = "satellite"
    var name: String = "卫星地图"
    var enabled: Bool = true
    var isDefault: Bool = false
    var online: OnlineMapDto? = nil
    var packageId: Int64? = nil
    var stableId: String { id.isEmpty ? key : id }
}

struct MapConfigDto: Codable {
    var id: Int64 = 1
    var baseMaps: [BaseMap] = []
    var longPressCoord: Bool = true
    var compass: Bool = true
    var measureLength: Bool = true
    var measureArea: Bool = true
    var announcement: String = ""
    var announcementEnabled: Bool = true
    var online: OnlineMapDto? = nil

    enum CodingKeys: String, CodingKey {
        case id, baseMaps, online
        case longPressCoord, compass, measureLength, measureArea
        case announcement, announcementEnabled
    }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 1
        baseMaps = try c.decodeIfPresent([BaseMap].self, forKey: .baseMaps) ?? []
        longPressCoord = try c.decodeIfPresent(Bool.self, forKey: .longPressCoord) ?? true
        compass = try c.decodeIfPresent(Bool.self, forKey: .compass) ?? true
        measureLength = try c.decodeIfPresent(Bool.self, forKey: .measureLength) ?? true
        measureArea = try c.decodeIfPresent(Bool.self, forKey: .measureArea) ?? true
        announcement = try c.decodeIfPresent(String.self, forKey: .announcement) ?? ""
        announcementEnabled = try c.decodeIfPresent(Bool.self, forKey: .announcementEnabled) ?? true
        online = try c.decodeIfPresent(OnlineMapDto.self, forKey: .online)
    }
}

struct AnnouncementDto: Codable {
    var enabled: Bool = true
    var text: String = ""
    var updatedAt: String? = nil
}

// MARK: - 图层
struct LayerDto: Codable, Identifiable {
    var id: Int64 = 0
    var name: String = ""
    var format: String = "GEOJSON"
    var type: String = "VECTOR"
    var url: String = ""
    var color: String = "#2e7d32"
    var labelField: String? = nil
    var visible: Bool = true
    var minZoom: Int = 0
    var maxZoom: Int = 18
    var zIndex: Int = 0
    var updatedAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, format, type, url, color, visible, zIndex, updatedAt
        case labelField = "label_field"
        case minZoom = "min_zoom"
        case maxZoom = "max_zoom"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "GEOJSON"
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "VECTOR"
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#2e7d32"
        labelField = try c.decodeIfPresent(String.self, forKey: .labelField)
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        minZoom = try c.decodeIfPresent(Int.self, forKey: .minZoom) ?? 0
        maxZoom = try c.decodeIfPresent(Int.self, forKey: .maxZoom) ?? 18
        zIndex = try c.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

// MARK: - 表单模板
struct FieldDto: Codable, Identifiable {
    var key: String = ""
    var type: String = "text"
    var label: String = ""
    var required: Bool = false
    var options: [String]? = nil
    var placeholder: String? = nil
    var unit: String? = nil
    var max: Int? = nil
    var coordEditable: Bool? = nil
    var id: String { key }
}

struct FormSchema: Codable {
    var fields: [FieldDto] = []
}

struct TemplateDto: Codable, Identifiable {
    var id: Int64 = 0
    var formId: String = ""
    var title: String = ""
    var version: Int = 1
    var category: String = "patrol"
    var published: Bool = true
    var schema: FormSchema = FormSchema()
    var updatedAt: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, version, category, published, schema, updatedAt
        case formId = "form_id"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        formId = try c.decodeIfPresent(String.self, forKey: .formId) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "patrol"
        published = try c.decodeIfPresent(Bool.self, forKey: .published) ?? true
        schema = try c.decodeIfPresent(FormSchema.self, forKey: .schema) ?? FormSchema()
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

// MARK: - 任务
struct TaskDto: Codable, Identifiable {
    var id: Int64 = 0
    var code: String = ""
    var title: String = ""
    var formId: String = ""
    var formVersion: Int = 1
    var formIds: [String] = []
    var category: String = ""
    var assigneeId: Int64 = 0
    var areaName: String = ""
    var planStart: String = ""
    var planEnd: String = ""
    var recordTrack: Bool = true
    var status: String = "PENDING"

    enum CodingKeys: String, CodingKey {
        case id, code, title, category, areaName, status
        case formId = "form_id"
        case formVersion = "form_version"
        case formIds = "form_ids"
        case assigneeId = "assignee_id"
        case planStart = "plan_start"
        case planEnd = "plan_end"
        case recordTrack = "record_track"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        formId = try c.decodeIfPresent(String.self, forKey: .formId) ?? ""
        formVersion = try c.decodeIfPresent(Int.self, forKey: .formVersion) ?? 1
        formIds = try c.decodeIfPresent([String].self, forKey: .formIds) ?? []
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        assigneeId = try c.decodeIfPresent(Int64.self, forKey: .assigneeId) ?? 0
        areaName = try c.decodeIfPresent(String.self, forKey: .areaName) ?? ""
        planStart = try c.decodeIfPresent(String.self, forKey: .planStart) ?? ""
        planEnd = try c.decodeIfPresent(String.self, forKey: .planEnd) ?? ""
        recordTrack = try c.decodeIfPresent(Bool.self, forKey: .recordTrack) ?? true
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "PENDING"
    }
    var effectiveFormIds: [String] {
        if !formIds.isEmpty { return formIds }
        return formId.isEmpty ? [] : [formId]
    }
}

// MARK: - 记录
struct RecordDto: Codable, Identifiable {
    var id: Int64? = nil
    var clientUuid: String = UUID().uuidString
    var taskId: Int64? = nil
    var runId: Int64? = nil
    var userId: Int64 = 0
    var formId: String = ""
    var formVersion: Int = 1
    var data: JSONDict = [:]
    var distanceM: Int = 0
    var durationS: Int = 0
    var status: String = "DRAFT"
    var submittedAt: String? = nil
    var updatedAt: String? = nil
    var update: Bool? = nil
    var pendingUpdate: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, status, data, update, submittedAt, updatedAt
        case clientUuid = "client_uuid"
        case taskId = "task_id"
        case runId = "run_id"
        case userId = "user_id"
        case formId = "form_id"
        case formVersion = "form_version"
        case distanceM = "distance_m"
        case durationS = "duration_s"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id)
        clientUuid = try c.decodeIfPresent(String.self, forKey: .clientUuid) ?? UUID().uuidString
        taskId = try c.decodeIfPresent(Int64.self, forKey: .taskId)
        runId = try c.decodeIfPresent(Int64.self, forKey: .runId)
        userId = try c.decodeIfPresent(Int64.self, forKey: .userId) ?? 0
        formId = try c.decodeIfPresent(String.self, forKey: .formId) ?? ""
        formVersion = try c.decodeIfPresent(Int.self, forKey: .formVersion) ?? 1
        data = try c.decodeIfPresent(JSONDict.self, forKey: .data) ?? [:]
        distanceM = try c.decodeIfPresent(Int.self, forKey: .distanceM) ?? 0
        durationS = try c.decodeIfPresent(Int.self, forKey: .durationS) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "DRAFT"
        submittedAt = try c.decodeIfPresent(String.self, forKey: .submittedAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        update = try c.decodeIfPresent(Bool.self, forKey: .update)
        pendingUpdate = false
    }
}

struct RecordSyncInfo: Codable {
    var synced: Bool = false
    var serverId: Int64? = nil
    var clientUuid: String = ""
    var status: String = ""
    var syncedAt: String? = nil
    var formTitle: String = ""
    var formVersion: Int = 0
    var taskTitle: String? = nil
    var userName: String = ""
    var userAccount: String = ""
    var distanceM: Int = 0
    var durationS: Int = 0
    var trackCount: Int = 0
    var trackPointCount: Int = 0
    var lat: Double? = nil
    var lng: Double? = nil
    var alt: Double? = nil
}

// MARK: - 航迹 / 流水号 / 任务事件（上报用）
struct TrackPointDto: Codable {
    var trackId: Int64 = 0
    var seq: Int = 0
    var lat: Double = 0
    var lng: Double = 0
    var alt: Double = 0
    var speed: Float = 0
    var accuracy: Float = 0
    var time: String = ""

    enum CodingKeys: String, CodingKey {
        case seq, lat, lng, alt, speed, accuracy, time
        case trackId = "track_id"
    }
}

struct TrackDto: Codable {
    var id: Int64? = nil
    var recordId: Int64? = nil
    var recordUuid: String? = nil
    var taskId: Int64? = nil
    var runId: Int64? = nil
    var userId: Int64 = 0
    var startedAt: String = ""
    var endedAt: String = ""
    var points: [TrackPointDto] = []

    enum CodingKeys: String, CodingKey {
        case id, points, userId
        case recordId = "record_id"
        case recordUuid = "record_uuid"
        case taskId = "task_id"
        case runId = "run_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct TaskRunDto: Codable {
    var runId: Int64 = 0
    var taskId: Int64 = 0
    var serialNo: String = ""
    var createdAt: String? = nil
    var trackStartedAt: String? = nil
    var endedAt: String? = nil
    var status: String? = nil

    enum CodingKeys: String, CodingKey {
        case status
        case runId = "run_id"
        case taskId = "task_id"
        case serialNo = "serial_no"
        case createdAt = "created_at"
        case trackStartedAt = "track_started_at"
        case endedAt = "ended_at"
    }
}

struct TaskEventDto: Codable {
    var taskId: Int64 = 0
    var event: String = ""
    enum CodingKeys: String, CodingKey {
        case event
        case taskId = "task_id"
    }
}

struct SyncPushRequest: Codable {
    var records: [RecordDto] = []
    var tracks: [TrackDto] = []
    var taskEvents: [TaskEventDto] = []
    var taskRuns: [TaskRunDto] = []
    enum CodingKeys: String, CodingKey {
        case records, tracks, taskEvents
        case taskRuns = "task_runs"
    }
}

struct PushError: Codable {
    var clientUuid: String? = nil
    var msg: String? = nil
    enum CodingKeys: String, CodingKey { case msg; case clientUuid = "client_uuid" }
}
struct PushRecordsResult: Codable {
    var accepted: Int = 0
    var deduplicated: Int = 0
    var updated: Int = 0
    var errors: [PushError] = []
}
struct SyncPushResponse: Codable {
    var records: PushRecordsResult = PushRecordsResult()
    var tracks: Int = 0
    var taskRuns: Int = 0
    var taskEvents: Int = 0
    enum CodingKeys: String, CodingKey {
        case records, tracks, taskEvents
        case taskRuns = "task_runs"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent(PushRecordsResult.self, forKey: .records) ?? PushRecordsResult()
        tracks = try c.decodeIfPresent(Int.self, forKey: .tracks) ?? 0
        taskRuns = try c.decodeIfPresent(Int.self, forKey: .taskRuns) ?? 0
        taskEvents = try c.decodeIfPresent(Int.self, forKey: .taskEvents) ?? 0
    }
}

struct PackageDto: Codable {
    var id: Int64 = 0
    var name: String = ""
    var type: String = ""
    var region: String = ""
    var sizeMb: Double = 0
    var version: Int = 0
    var url: String = ""
    var status: String = ""
    var updatedAt: String? = nil
    enum CodingKeys: String, CodingKey {
        case id, name, type, region, version, url, status, updatedAt
        case sizeMb = "size_mb"
    }
}

struct SyncPullResponse: Codable {
    var templates: [TemplateDto] = []
    var layers: [LayerDto] = []
    var mapConfig: MapConfigDto? = nil
    var tasks: [TaskDto] = []
    var packages: [PackageDto] = []
    var revision: String? = nil
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templates = try c.decodeIfPresent([TemplateDto].self, forKey: .templates) ?? []
        layers = try c.decodeIfPresent([LayerDto].self, forKey: .layers) ?? []
        mapConfig = try c.decodeIfPresent(MapConfigDto.self, forKey: .mapConfig)
        tasks = try c.decodeIfPresent([TaskDto].self, forKey: .tasks) ?? []
        packages = try c.decodeIfPresent([PackageDto].self, forKey: .packages) ?? []
        revision = try c.decodeIfPresent(String.self, forKey: .revision)
    }
}

// MARK: - 位置 / 在线
struct LocationPingRequest: Codable {
    var lat: Double
    var lng: Double
    var accuracy: Float?
    var at: String
}
struct LocationPingResponse: Codable {
    var ok: Bool = false
    var at: String? = nil
}
struct HeartbeatRequest: Codable {
    var t: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
}
struct LocationPointDto: Codable {
    var clientUuid: String
    var lat: Double
    var lng: Double
    var accuracy: Float?
    var at: String
    enum CodingKeys: String, CodingKey {
        case lat, lng, accuracy, at
        case clientUuid = "client_uuid"
    }
}
struct LocationUploadRequest: Codable { var points: [LocationPointDto] = [] }
struct LocationUploadResponse: Codable {
    var accepted: Int = 0
    var deduplicated: Int = 0
    var errors: [PushError] = []
}
struct OnlineLocationDto: Codable {
    var userId: Int64 = 0
    var name: String = ""
    var role: String = ""
    var org: String = ""
    var lat: Double = 0
    var lng: Double = 0
    var accuracy: Float? = nil
    var at: String? = nil
    var secondsAgo: Int64? = nil
    var online: Bool = false
    var status: String? = nil
    var active: Bool = false
    enum CodingKeys: String, CodingKey {
        case name, role, org, lat, lng, accuracy, at, online, status, active
        case userId = "user_id"
        case secondsAgo = "seconds_ago"
    }
}
struct OnlineLocationsResponse: Codable {
    var onlineCount: Int = 0
    var total: Int = 0
    var list: [OnlineLocationDto] = []
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onlineCount = try c.decodeIfPresent(Int.self, forKey: .onlineCount) ?? 0
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        list = try c.decodeIfPresent([OnlineLocationDto].self, forKey: .list) ?? []
    }
}

struct ElevationDto: Codable {
    var alt: Double = 0
    var slope: Double? = nil
    var aspect: Double? = nil
    var aspectLabel: String? = nil
}

struct AppVersionInfo: Codable {
    var versionCode: Int = 0
    var versionName: String = ""
    var url: String = ""
    var size: Int64 = 0
    var notes: String = ""
    var force: Bool = false
}

struct TaskStatusRequest: Codable {
    var event: String? = nil
    var status: String? = nil
}

// MARK: - 本地运行态（不上传）
struct TaskRunLocal: Codable, Identifiable {
    var runId: Int64 = 0
    var taskId: Int64 = 0
    var serialNo: String = ""
    var createdAt: String = ""
    var trackStartedAt: String? = nil
    var endedAt: String? = nil
    var status: String = "PENDING"
    var id: Int64 { runId }
    enum CodingKeys: String, CodingKey {
        case runId, taskId, serialNo, createdAt, trackStartedAt, endedAt, status
    }
}

struct TaskEventLocal: Codable, Identifiable {
    var id: String = UUID().uuidString
    var taskId: Int64 = 0
    var event: String = ""
    var createdAt: String = ""
}

struct LocationQueueItem: Codable, Identifiable {
    var clientUuid: String = UUID().uuidString
    var lat: Double = 0
    var lng: Double = 0
    var accuracy: Float? = nil
    var at: String = ""
    var id: String { clientUuid }
}

// MARK: - 通用信封
struct ListEnvelope<T: Decodable>: Decodable { var data: [T] = [] }
