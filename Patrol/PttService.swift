import Foundation
import AVFoundation
import AudioToolbox
import Combine

/// 对讲机（对应 PttClient）：WebSocket 抢麦 + 8kHz PCM 收发。
/// iOS 无悬浮窗：对讲按钮放底部 Tab 中间 + 全屏对讲视图，切后台仅保留音频播放。
final class PttService: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    static let shared = PttService()

    enum Status: String {
        case idle = "未连接", connecting = "连接中", connected = "已连接·频道空闲"
        case pending = "等待话筒", talking = "讲话中"
    }

    @Published var status: Status = .idle
    @Published var speakerName: String = ""
    @Published var message: String = ""

    private var ws: URLSessionWebSocketTask?
    private var session: URLSession?
    private var meId: Int64 = 0
    private var speakerId: Int64? = nil
    private var wantTalk = false
    private var talking = false
    private var retrySec: TimeInterval = 2
    private var reconnectWork: DispatchWorkItem?
    private let sampleRate: Double = 8000
    private let chunkBytes = 640   // 40ms 帧

    private var recordEngine: AVAudioEngine?
    private var playEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var recordConverter: AVAudioConverter?

    // MARK: - 连接
    func connect() {
        guard Session.shared.isLoggedIn, !Session.shared.token.isEmpty else { return }
        let root = URLTool.serverRoot(Session.shared.baseUrl)
        let wsScheme = root.hasPrefix("https") ? "wss://" : "ws://"
        let host = root.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        let token = Session.shared.token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let u = URL(string: "\(wsScheme)\(host)/ws/ptt?token=\(token)") else { return }

        status = .connecting
        let cfg = URLSessionConfiguration.default
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        ws = session?.webSocketTask(with: u)
        ws?.resume()
        receive()
    }

    func disconnect() {
        reconnectWork?.cancel()
        stopTalk()
        ws?.cancel(with: .normalClosure, reason: nil)
        ws = nil
        status = .idle
    }

    private func receive() {
        ws?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let m):
                switch m {
                case .data(let d): self.play(d)
                case .string(let s): self.handleJson(s)
                @unknown default: break
                }
                self.receive()
            case .failure:
                self.scheduleReconnect()
            }
        }
    }

    private func handleJson(_ text: String) {
        guard let d = text.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        switch o["t"] as? String ?? "" {
        case "welcome":
            meId = (o["me"] as? [String: Any])?["id"] as? Int64 ?? 0
            status = .connected
            retrySec = 2
            if wantTalk { sendStart() }
        case "granted":
            talking = true; status = .talking
            startRecording()
        case "busy":
            message = "\(o["name"] as? String ?? "对方") 正在讲话，请稍候"
            wantTalk = false
            status = speakerId == nil ? .connected : status
            beep(320, 0.2)
        case "speaking":
            speakerId = o["id"] as? Int64
            speakerName = o["name"] as? String ?? ""
            if speakerId != meId { status = .connected; beep(1180, 0.07) }
        case "idle":
            speakerId = nil; speakerName = ""
            if !talking { status = .connected }
        case "ended":
            stopTalk()
        case "error":
            message = o["msg"] as? String ?? "对讲出错"
            wantTalk = false
        default: break
        }
    }

    // MARK: - 按住说话
    func startTalk() {
        guard status != .talking else { return }
        wantTalk = true
        if ws?.state == .running {
            sendStart()
        } else {
            connect()
        }
    }

    func stopTalk() {
        wantTalk = false
        sendText("{\"t\":\"stop\"}")
        stopRecording()
        talking = false
        if speakerId == nil { status = .connected }
        beep(760, 0.15)
    }

    private func sendStart() {
        sendText("{\"t\":\"start\"}")
        status = .pending
    }

    private func sendText(_ s: String) {
        ws?.send(.string(s)) { _ in }
    }

    private func sendBytes(_ data: Data) {
        ws?.send(.data(data)) { _ in }
    }

    // MARK: - 音频采集
    private func startRecording() {
        let eng = AVAudioEngine()
        let input = eng.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let conv = AVAudioConverter(from: inFormat, to: target) else { return }
        recordConverter = conv
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buf, _ in
            guard let self = self else { return }
            let capacity = AVAudioFrameCount(self.sampleRate)
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var err: NSError?
            let consumed = conv.convert(to: out, error: &err) { _, outStatus in
                outStatus.pointee = .haveData
                return buf
            }
            guard consumed != .error, err == nil,
                  let ch = out.int16ChannelData else { return }
            let frames = Int(out.frameLength)
            let pcm = ch[0]
            let bytes = Data(bytes: pcm, count: frames * 2)
            // 按 640 字节切片发送
            var offset = 0
            while offset + self.chunkBytes <= bytes.count {
                self.sendBytes(bytes.subdata(in: offset..<(offset + self.chunkBytes)))
                offset += self.chunkBytes
            }
        }
        do { try eng.start(); recordEngine = eng } catch { stopRecording() }
    }

    private func stopRecording() {
        recordEngine?.inputNode.removeTap(onBus: 0)
        recordEngine?.stop()
        recordEngine = nil
    }

    // MARK: - 音频播放
    private func setupPlayer() {
        guard playerNode == nil else { return }
        let eng = AVAudioEngine()
        let node = AVAudioPlayerNode()
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true) else { return }
        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: fmt)
        do { try eng.start(); playEngine = eng; playerNode = node } catch { }
    }

    private func play(_ data: Data) {
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(data.count / 2)) else { return }
        let count = data.count / 2
        _ = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress,
                  let dstPtr = buf.int16ChannelData else { return }
            let dst = dstPtr[0]
            for i in 0..<count { dst[i] = src[i] }
        }
        buf.frameLength = AVAudioFrameCount(count)
        setupPlayer()
        playerNode?.scheduleBuffer(buf, completionHandler: nil)
        if playerNode?.isPlaying == false { playerNode?.play() }
    }

    private func beep(_ freq: Double, _ dur: TimeInterval) {
        // 简化：提示音用系统音效替代，避免与播放引擎冲突
        AudioServicesPlaySystemSound(SystemSoundID(1000 + Int(freq) % 10))
    }

    // MARK: - 重连
    private func scheduleReconnect() {
        guard Session.shared.isLoggedIn else { return }
        status = .idle
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + retrySec, execute: work)
        retrySec = min(retrySec * 2, 30)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        scheduleReconnect()
    }
}
