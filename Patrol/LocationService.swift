import Foundation
import CoreLocation
import UIKit
import Combine

/// 定位 + 位置上报服务（对应安卓 LocationReporter + LocationReportService + PresenceHeartbeat）
/// iOS 无常驻前台服务：用「始终授权 + 后台定位」持续拿点，位置变化时节流到每 60 秒上报一次，
/// 另有独立的 60 秒心跳定时器（前台可靠；后台靠后台定位回调顺带触发）。
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private let api = API.shared
    private let store = Store.shared
    private var lastReportAt: Date = .distantPast
    private var lastBeatAt: Date = .distantPast
    private let reportInterval: TimeInterval = 60
    private var lastFix: CLLocation?

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var latestLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 10
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
    }

    /// 请求「始终」授权（弹「使用 App 期间」后，用户需在系统设置选「始终」才能后台记录）
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            // iOS 13+ 需在设置中升级到 Always；这里引导
            if let u = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(u)
            }
        }
    }

    /// 开始持续定位（进入 App / 开始任务时调用）
    func startTracking() {
        guard Session.shared.isLoggedIn else { return }
        let st = manager.authorizationStatus
        if st == .authorizedAlways || st == .authorizedWhenInUse {
            manager.startUpdatingLocation()
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            startTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // 过滤异常时间
        let fixDate = loc.timestamp
        let now = Date()
        let valid = fixDate.timeIntervalSince1970 > 1_577_836_800 && fixDate <= now.addingTimeInterval(60)
        let fixMs = valid ? fixDate : now
        self.lastFix = loc
        latestLocation = loc

        // 记录任务航迹（每 15 秒或 20 米一个点）
        appendToTrackIfNeeded(loc, at: fixMs)

        // 位置上报节流
        if now.timeIntervalSince(lastReportAt) >= reportInterval {
            lastReportAt = now
            reportOnce(loc, at: fixMs)
        }
        // 后台定位回调顺带补心跳
        if now.timeIntervalSince(lastBeatAt) >= reportInterval {
            lastBeatAt = now
            beat()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { /* 忽略瞬时失败 */ }

    /// 立即上报一次（登录 / 心跳兜底）
    func reportOnceNow() {
        guard let loc = lastFix ?? manager.location else { return }
        let now = Date()
        if now.timeIntervalSince(lastReportAt) >= 30 {
            lastReportAt = now
            reportOnce(loc, at: loc.timestamp)
        }
    }

    private func reportOnce(_ loc: CLLocation, at: Date) {
        let atStr = TimeUtil.iso(at)
        Task {
            let ok = await api.ping(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
                                    accuracy: Float(loc.horizontalAccuracy), at: atStr)
            if !ok {
                // 入队待补传
                store.enqueueLocation(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
                                      accuracy: Float(loc.horizontalAccuracy), at: atStr)
            }
        }
    }

    /// 心跳（独立调用，前台定时器 + 后台定位回调）
    func beat() {
        guard Session.shared.isLoggedIn else { return }
        Task { _ = await api.heartbeat() }
    }

    // 记录级 / 任务级航迹
    private var lastTrackPoint: CLLocation?
    private var lastTrackTime: Date = .distantPast
    private func appendToTrackIfNeeded(_ loc: CLLocation, at: Date) {
        guard !store.recordingTaskIds.isEmpty else { return }
        if let last = lastTrackPoint, at.timeIntervalSince(lastTrackTime) < 15,
           last.distance(from: loc) < 20 { return }
        lastTrackPoint = loc; lastTrackTime = at
        for tid in store.recordingTaskIds {
            guard let run = store.currentRun(taskId: tid) else { continue }
            store.appendPoint(runId: run.runId, lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
                              alt: loc.altitude, accuracy: Float(loc.horizontalAccuracy), speed: Float(loc.speed))
        }
    }
}
