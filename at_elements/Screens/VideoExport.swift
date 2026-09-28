import Combine
import UIKit
import UserNotifications

final class VideoExport: ObservableObject {
    enum Phase: Equatable {
        case idle
        case saving
        case saved
        case failed
    }

    @Published private(set) var phase: Phase = .idle

    private var current: ExportJob?

    func start(scene: StickmanScene, assets: UnitAssets, backgrounds: BackgroundAssets) {
        if phase == .saving {
            return
        }
        let snapshot = scene
        let active = JpegWriteStop()
        let job = ExportJob()
        current = job
        phase = .saving
        Task {
            let allowed = await VideoExportNotifier.prepare()
            job.alerts = allowed
            if self.current !== job {
                return
            }
            self.beginBackgroundTask(job: job, stop: active)
            if job.isExpired {
                return
            }
            JpegSequenceWriter.write(
                scene: snapshot,
                assets: assets,
                backgrounds: backgrounds,
                stop: active,
                progress: { _ in },
                completion: { result in
                    Task { @MainActor in
                        switch result {
                        case .failure(let error):
                            if error is JpegWriteError {
                                return
                            }
                            self.finish(job: job, next: .failed)
                        case .success(let count):
                            if active.isCancelled {
                                return
                            }
                            if count < 1 {
                                fatalError("VideoExport write produced \(count) files")
                            }
                            JpegVideoAssembler.assemble(frameCount: count) { assembleResult in
                                Task { @MainActor in
                                    if active.isCancelled {
                                        return
                                    }
                                    switch assembleResult {
                                    case .success:
                                        self.finish(job: job, next: .saved)
                                    case .failure:
                                        self.finish(job: job, next: .failed)
                                    }
                                }
                            }
                        }
                    }
                }
            )
        }
    }

    private func finish(job: ExportJob, next: Phase) {
        if current !== job || job.isExpired || !job.takeOutcome() {
            return
        }
        phase = next
        if job.alerts == true {
            if next == .saved {
                VideoExportNotifier.postReady { self.endJobTask(job) }
            } else {
                VideoExportNotifier.postFailed { self.endJobTask(job) }
            }
        } else {
            endJobTask(job)
        }
        scheduleIdleReset(job: job)
    }

    private func showExpired(job: ExportJob) {
        if current !== job || phase != .saving {
            return
        }
        phase = .failed
        scheduleIdleReset(job: job)
    }

    private func scheduleIdleReset(job: ExportJob) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.current === job {
                self.phase = .idle
            }
        }
    }

    private func beginBackgroundTask(job: ExportJob, stop: JpegWriteStop) {
        let id = UIApplication.shared.beginBackgroundTask(withName: "video-export") { [weak self, job] in
            stop.cancel()
            JpegVideoAssembler.cancel()
            job.markExpired()
            if job.takeOutcome(), job.alerts == true {
                VideoExportNotifier.postFailed { }
            }
            if let task = job.finishHandlerRun() {
                UIApplication.shared.endBackgroundTask(task)
            }
            Task { @MainActor [weak self] in
                self?.showExpired(job: job)
            }
        }
        job.setTask(id)
        if job.didHandlerRun, let task = job.takeTask() {
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    private func endJobTask(_ job: ExportJob) {
        if let task = job.takeTask() {
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}

/// One export's background-task state. Everything behind one lock; the
/// expiration handler (any thread) and the MainActor code share it.
private final class ExportJob: @unchecked Sendable {
    private let lock = NSLock()
    private var task = UIBackgroundTaskIdentifier.invalid
    private var expired = false
    private var outcomeTaken = false
    private var handlerDone = false
    private var storedAlerts: Bool?

    var alerts: Bool? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedAlerts
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedAlerts = newValue
        }
    }

    var isExpired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return expired
    }

    var didHandlerRun: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handlerDone
    }

    func markExpired() {
        lock.lock()
        defer { lock.unlock() }
        expired = true
    }

    /// Single post-once flag: exactly one of expiration / finish / cancel wins.
    @discardableResult
    func takeOutcome() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if outcomeTaken {
            return false
        }
        outcomeTaken = true
        return true
    }

    func setTask(_ id: UIBackgroundTaskIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        task = id
    }

    func takeTask() -> UIBackgroundTaskIdentifier? {
        lock.lock()
        defer { lock.unlock() }
        if task == .invalid {
            return nil
        }
        let id = task
        task = .invalid
        return id
    }

    /// Marks the handler as done and takes the task id in one lock hold.
    func finishHandlerRun() -> UIBackgroundTaskIdentifier? {
        lock.lock()
        defer { lock.unlock() }
        handlerDone = true
        if task == .invalid {
            return nil
        }
        let id = task
        task = .invalid
        return id
    }
}

enum VideoExportNotifier {
    nonisolated static let readyCategory = "video-export"
    nonisolated static let failedCategory = "video-export-failed"

    static func prepare() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    nonisolated static func postReady(_ done: @escaping () -> Void) {
        post(
            title: "Video ready",
            body: "Saved to Photos",
            category: readyCategory,
            done: done
        )
    }

    nonisolated static func postFailed(_ done: @escaping () -> Void) {
        post(
            title: "Export failed",
            body: "The video was not saved",
            category: failedCategory,
            done: done
        )
    }

    nonisolated private static func post(title: String, body: String, category: String, done: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title 
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in
            Task { @MainActor in
                done()
            }
        }
    }
}

final class ExportNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ExportNotificationCenter()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let category = notification.request.content.categoryIdentifier
        if category != VideoExportNotifier.readyCategory && category != VideoExportNotifier.failedCategory {
            return []
        }
        let active = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        if active {
            return []
        }
        return [.banner, .sound]
    }
}
