import SwiftUI

/// 动态表单：按表格设计的 schema.fields 顺序渲染全部字段类型，保存只写本机。
struct DynamicFormView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    let formId: String
    let taskId: Int64?
    let editUuid: String?

    @State private var data: JSONDict = [:]
    @State private var isEdit = false
    @State private var saving = false
    @State private var toast = ""
    @State private var showCameraFor: String? = nil
    @State private var showSignatureFor: String? = nil
    @State private var locatingKey: String? = nil

    private var template: TemplateDto? { store.template(formId: formId) }
    private var fields: [FieldDto] { template?.schema.fields ?? [] }

    var body: some View {
        Group {
            if let t = template {
                Form {
                    Section {
                        Text("点「保存」只存本机，不会联网；联网后到「我的 → 提交上报」一次性上传。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(fields) { field in
                        Section {
                            if ["image", "signature", "location"].contains(field.type) {
                                fieldView(field)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 2) {
                                        Text(field.label).font(.subheadline)
                                        if field.required { Text("*").foregroundColor(.red) }
                                    }
                                    fieldView(field)
                                }
                            }
                        }
                    }
                    if isEdit {
                        Section {
                            Button("删除", role: .destructive) { deleteRecord() }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("模板未下载，请联网后同步").foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(template?.title ?? "填报")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") { save() }.disabled(saving || template == nil)
            }
        }
        .sheet(item: $showCameraFor) { key in
            CameraView { base64 in
                var arr = (data[key]?.arrayValue ?? []).map { $0 }
                arr.append(.string(base64))
                data[key] = .array(arr)
            }
        }
        .sheet(item: $showSignatureFor) { key in
            SignatureView { base64 in data[key] = .string(base64) }
        }
        .overlay(alignment: .bottom) {
            if !toast.isEmpty {
                Text(toast).font(.caption).padding(10)
                    .background(Color.black.opacity(0.8)).foregroundColor(.white).cornerRadius(8)
                    .padding(.bottom, 20)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { toast = "" }
                    }
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - 字段渲染
    @ViewBuilder
    private func fieldView(_ f: FieldDto) -> some View {
        switch f.type {
        case "textarea":
            TextEditor(text: bindingString(f.key))
                .frame(minHeight: 80)
        case "number":
            HStack {
                TextField(f.placeholder ?? "", text: bindingString(f.key)).keyboardType(.decimalPad)
                if let u = f.unit { Text(u).foregroundColor(.secondary) }
            }
        case "select":
            Picker(f.label, selection: bindingString(f.key)) {
                Text("请选择").tag("")
                ForEach(f.options ?? [], id: \.self) { Text($0).tag($0) }
            }
        case "radio":
            ForEach(f.options ?? [], id: \.self) { opt in
                Button {
                    data[f.key] = .string(opt)
                } label: {
                    HStack {
                        Image(systemName: data[f.key]?.stringValue == opt ? "checkmark.circle.fill" : "circle")
                        Text(opt).foregroundColor(.primary)
                    }
                }
            }
        case "checkbox":
            ForEach(f.options ?? [], id: \.self) { opt in
                Button {
                    var arr = (data[f.key]?.arrayValue ?? []).filter { $0.stringValue != nil }
                    if let i = arr.firstIndex(where: { $0.stringValue == opt }) {
                        arr.remove(at: i)
                    } else {
                        arr.append(.string(opt))
                    }
                    data[f.key] = .array(arr)
                } label: {
                    HStack {
                        Image(systemName: isChecked(f.key, opt) ? "checkmark.square.fill" : "square")
                        Text(opt).foregroundColor(.primary)
                    }
                }
            }
        case "image":
            imageField(f)
        case "signature":
            signatureField(f)
        case "location":
            locationField(f)
        case "date":
            DateField(label: f.label, text: bindingString(f.key))
        case "time":
            TimeField(label: f.label, text: bindingString(f.key))
        default:
            TextField(f.placeholder ?? "", text: bindingString(f.key))
        }
    }

    private func label(_ f: FieldDto) -> some View {
        HStack(spacing: 2) {
            Text(f.label)
            if f.required { Text("*").foregroundColor(.red) }
        }.font(.subheadline)
    }

    // 普通字段需要显示 label 的，包一层
    private func fieldViewWithLabel(_ f: FieldDto) -> some View {
        VStack(alignment: .leading) { label(f); fieldView(f) }
    }

    @ViewBuilder
    private func imageField(_ f: FieldDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(f)
            let maxSlots = min(max(f.max ?? 3, 1), 6)
            let photos = data[f.key]?.arrayValue ?? []
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(photos.indices, id: \.self) { i in
                    if let b64 = photos[i].stringValue, let d = Data(base64Encoded: b64), let img = UIImage(data: d) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(height: 80).clipped().cornerRadius(6)
                            Button {
                                var arr = photos; arr.remove(at: i); data[f.key] = .array(arr)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.white)
                            }
                        }
                    }
                }
                if photos.count < maxSlots {
                    Button {
                        // 拍照前先取一次坐标
                        LocationService.shared.reportOnceNow()
                        showCameraFor = f.key
                    } label: {
                        VStack {
                            Image(systemName: "camera.fill").font(.title2)
                            Text("拍照").font(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .background(Color.gray.opacity(0.12)).cornerRadius(6)
                    }
                }
            }
            Text("仅支持现场拍照，照片左下角自动叠加经纬度与时间").font(.caption2).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func signatureField(_ f: FieldDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(f)
            if let b64 = data[f.key]?.stringValue, !b64.isEmpty,
               let d = Data(base64Encoded: b64), let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFit().frame(height: 90)
                    .background(Color.gray.opacity(0.1)).cornerRadius(6)
                Button("重新签名") { showSignatureFor = f.key }.font(.caption)
            } else {
                Button("手写签名") { showSignatureFor = f.key }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color.gray.opacity(0.12)).cornerRadius(8)
            }
        }
    }

    @ViewBuilder
    private func locationField(_ f: FieldDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(f.label).font(.subheadline); if f.required { Text("*").foregroundColor(.red) } }
            HStack {
                Text("经度").frame(width: 60, alignment: .leading).font(.caption)
                TextField("", value: bindingSub(f.key, "lng"), formatter: NumberFormatter.decimal6)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    .disabled(f.coordEditable == false)
            }
            HStack {
                Text("纬度").frame(width: 60, alignment: .leading).font(.caption)
                TextField("", value: bindingSub(f.key, "lat"), formatter: NumberFormatter.decimal6)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    .disabled(f.coordEditable == false)
            }
            HStack {
                Text("海拔(m)").frame(width: 60, alignment: .leading).font(.caption)
                TextField("", value: bindingSub(f.key, "alt"), formatter: NumberFormatter.decimal1)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("坡度(°)*").frame(width: 62, alignment: .leading).font(.caption)
                TextField("", value: bindingSub(f.key, "slope"), formatter: NumberFormatter.decimal1)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                Text("坡向(°)*").frame(width: 62, alignment: .leading).font(.caption)
                TextField("", value: bindingSub(f.key, "aspect"), formatter: NumberFormatter.decimal1)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            }
            Button(locatingKey == f.key ? "定位中…" : "重新定位") { relocate(f.key) }
                .disabled(locatingKey != nil).font(.caption)
            if f.coordEditable == false { Text("🔒 经纬度已锁定：由定位自动填入").font(.caption2).foregroundColor(.secondary) }
        }
    }

    // MARK: - 定位
    private func relocate(_ key: String) {
        locatingKey = key
        Task {
            var lat = 0.0, lng = 0.0, alt = 0.0
            if let loc = LocationService.shared.latestLocation {
                lat = loc.coordinate.latitude; lng = loc.coordinate.longitude; alt = loc.altitude
            } else {
                // 触发一次定位并短暂等待
                LocationService.shared.startTracking()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let loc = LocationService.shared.latestLocation {
                    lat = loc.coordinate.latitude; lng = loc.coordinate.longitude; alt = loc.altitude
                }
            }
            var obj = data[key]?.objectValue ?? [:]
            if lat != 0 || lng != 0 {
                obj["lat"] = .double(lat); obj["lng"] = .double(lng); obj["alt"] = .double(alt)
            }
            if let e = await API.shared.elevation(lat: lat, lng: lng) {
                obj["alt"] = .double(e.alt)
                if let s = e.slope { obj["slope"] = .double(s) }
                if let a = e.aspect { obj["aspect"] = .double(a) }
                if let al = e.aspectLabel { obj["aspectLabel"] = .string(al) }
            }
            await MainActor.run { data[key] = .object(obj); locatingKey = nil }
        }
    }

    // MARK: - 绑定工具
    private func bindingString(_ key: String) -> Binding<String> {
        Binding(get: { data[key]?.stringValue ?? "" }, set: { data[key] = .string($0) })
    }
    /// 直接读写 data[key] 对象的子字段（值类型需整体写回）
    private func bindingSub(_ key: String, _ sub: String) -> Binding<Double> {
        Binding(
            get: { data[key]?.objectValue?[sub]?.doubleValue ?? 0 },
            set: { value in
                var obj = data[key]?.objectValue ?? [:]
                obj[sub] = .double(value)
                data[key] = .object(obj)
            }
        )
    }
    private func isChecked(_ key: String, _ opt: String) -> Bool {
        data[key]?.arrayValue?.contains { $0.stringValue == opt } ?? false
    }

    // MARK: - 加载 / 保存 / 删除
    private func load() {
        if let uuid = editUuid, let rec = store.record(uuid: uuid) {
            isEdit = true
            data = rec.data
        } else {
            // 新建：定位字段自动定位一次
            for f in fields where f.type == "location" { relocate(f.key) }
        }
    }

    private func save() {
        if let msg = FormValidator.validate(fields: fields, data: data) {
            toast = "\(msg)（必填项，填写后才能保存）"
            return
        }
        saving = true
        let uuid = editUuid ?? UUID().uuidString
        let existing = store.record(uuid: uuid)
        var rec = existing ?? RecordDto()
        rec.clientUuid = uuid
        rec.taskId = taskId
        rec.runId = taskId.flatMap { store.currentRun(taskId: $0)?.runId }
        rec.userId = Session.shared.user.id
        rec.formId = formId
        rec.formVersion = template?.version ?? 1
        rec.data = data
        rec.status = "SUBMITTED"
        rec.submittedAt = existing?.submittedAt ?? displayNow()
        rec.updatedAt = displayNow()
        rec.pendingUpdate = (existing?.pendingUpdate ?? false) || (existing?.status == "ACCEPTED")
        store.saveRecord(rec)
        saving = false
        toast = "已保存到本机，请到「我的 → 提交上报」联网上传"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }

    private func deleteRecord() {
        guard let uuid = editUuid, let rec = store.record(uuid: uuid) else { return }
        if rec.status == "ACCEPTED" { Task { _ = await API.shared.deleteRecord(uuid: uuid) } }
        store.deleteRecord(uuid: uuid)
        dismiss()
    }

    private func displayNow() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: Date())
    }
}

// MARK: - 日期/时间字段
struct DateField: View {
    let label: String
    @Binding var text: String
    @State private var date = Date()
    var body: some View {
        HStack {
            TextField("yyyy-MM-dd", text: $text)
                .onChange(of: text) { newValue in
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                    if let d = f.date(from: newValue) { date = d }
                }
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: date) { newDate in
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                    text = f.string(from: newDate)
                }
        }
    }
}

struct TimeField: View {
    let label: String
    @Binding var text: String
    @State private var date = Date()
    var body: some View {
        HStack {
            TextField("HH:mm", text: $text)
            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .onChange(of: date) { newDate in
                    let f = DateFormatter(); f.dateFormat = "HH:mm"
                    text = f.string(from: newDate)
                }
        }
    }
}

extension NumberFormatter {
    static let decimal6: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.maximumFractionDigits = 6; f.minimumFractionDigits = 0; return f
    }()
    static let decimal1: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.maximumFractionDigits = 1; f.minimumFractionDigits = 0; return f
    }()
}
