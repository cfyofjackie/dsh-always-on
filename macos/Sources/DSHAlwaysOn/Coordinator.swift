import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement
import CompanionCore

struct Endpoint: Codable {
    var protocolVersion: String
    var port: Int
    var token: String
    var sourceEpoch: String
    var instanceId: String
}

@MainActor final class Coordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DSH Always On", isDirectory: true)
    @Published var store = SessionStore()
    @Published var connected = false
    @Published var clientConnected = false
    @Published var connectionLabel = "正在检查连接…"
    @Published var feedback: String?
    @Published var mode: NotificationMode? {
        didSet {
            preferences.set(mode?.rawValue, forKey: "notificationMode")
            if !previewOnly {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            }
            bubbleTask?.cancel(); reminderQueue.clear(); bubble = nil
            preferences.removeObject(forKey: "retainedBubbleID")
            animationPreview.end(); bubblePreviewEnabled = false
            applyMode()
        }
    }
    @Published var alwaysOnTop: Bool { didSet { preferences.set(alwaysOnTop, forKey: "alwaysOnTop"); petController?.update() } }
    @Published var reminderRetention: ReminderRetention {
        didSet {
            preferences.set(reminderRetention.rawValue, forKey: "reminderRetention")
            reminderQueue.restartTimer(now: now)
            syncBubble(); updatePresentation(); scheduleFeedbackExpiration()
        }
    }
    @Published var bubbleStyle: BubbleStyle { didSet { preferences.set(bubbleStyle.rawValue, forKey: "bubbleStyle") } }
    @Published var showInFullScreen: Bool { didSet { preferences.set(showInFullScreen, forKey: "showInFullScreen"); petController?.update() } }
    @Published var bubblePreviewKind: BubblePreviewKind = .success { didSet { petController?.update() } }
    @Published private(set) var bubblePreviewEnabled = false
    @Published private(set) var petSpaceVisible = true
    @Published var launchAtLogin = false
    @Published var notificationPermission = "未请求"
    @Published var bubble: Notice?
    @Published private(set) var animationPreview = AnimationPreview()
    @Published var bubbleTailSide: BubbleTailSide = .right
    @Published var bubbleTailOffset: CGFloat = 118
    @Published var integrationEnabled = false
    @Published var dshHome: String {
        didSet { preferences.set(dshHome, forKey: "dshHome"); if !previewOnly { refreshIntegration() } }
    }
    var petController: PetController?
    var showMain: () -> Void = {}
    private var pollTask: Task<Void, Never>?
    private var expireTask: Task<Void, Never>?
    private var bubbleTask: Task<Void, Never>?
    private var reminderQueue = PetReminderQueue()
    private var dismissedFeedbackIDs: Set<String>
    private let preferences: UserDefaults
    private let previewOnly: Bool
    private var now: Double { Date().timeIntervalSince1970 * 1000 }
    private let network: URLSession
    private var endpoint: Endpoint?
    private var cursorEpoch = ""
    private var cursor = -1
    private var viewStatus: ViewStatus?
    private var foregroundGeneration = 0
    private var activeViews = Set<String>()
    private var pendingNotices: [String: Notice] = [:]
    private var pendingFeedbackIDs = Set<String>()
    private var unconfirmedViewIDs = Set<String>()
    private var retryViewedAfter: [String: Double] = [:]
    private var workspaceObserver: NSObjectProtocol?
    private var attentionTimer: Task<Void, Never>?
    private var dshForeground: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.deepseek.dsh" }
    private func watchAttention() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.foregroundGeneration += 1; self.unconfirmedViewIDs.removeAll(); self.retryViewedAfter.removeAll()
                if self.dshForeground { self.closePetFeedback(); await self.refreshViewedSession() }
            }
        }
        attentionTimer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshViewedSession()
                try? await Task.sleep(for: .milliseconds(900))
            }
        }
    }
    private func refreshViewedSession() async {
        guard !previewOnly, dshForeground, connected, let endpoint else { return }
        do {
            var request = try authorizedRequest(endpoint, path: "/view-state"); request.timeoutInterval = 2
            let (data, response) = try await network.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, self.endpoint?.sourceEpoch == endpoint.sourceEpoch else { return }
            struct State: Decodable { var viewStatus: ViewStatus? }
            let nextView = try JSONDecoder().decode(State.self, from: data).viewStatus
            if viewStatus?.sessionId != nextView?.sessionId { unconfirmedViewIDs.removeAll(); retryViewedAfter.removeAll() }
            viewStatus = nextView
            if let id = viewStatus?.sessionId, !store.unreadIDs(sessionId: id).isEmpty { confirmViewing(id) }
        } catch { /* Older bridge: never infer viewed from activation alone. */ }
    }
    private func route(_ notice: Notice) {
        animationPreview.end(); bubblePreviewEnabled = false
        if viewStatus?.eligible(sessionId: notice.sessionId, foreground: dshForeground, now: now) == true {
            pendingNotices[notice.id] = notice; pendingFeedbackIDs.insert(notice.id)
            confirmViewing(notice.sessionId)
        } else { present(notice) }
    }
    private func confirmViewing(_ id: String) {
        guard !activeViews.contains(id), let endpoint,
              viewStatus?.eligible(sessionId: id, foreground: dshForeground, now: now) == true else { return }
        let boundary = store.unreadIDs(sessionId: id), epoch = store.sourceEpoch, instance = store.instanceId,
            sequence = store.sequence, generation = foregroundGeneration, requestID = UUID().uuidString
        guard !boundary.isEmpty else { return }
        if boundary.isSubset(of: unconfirmedViewIDs), now < (retryViewedAfter[id] ?? 0) { return }
        activeViews.insert(id)
        // Retrying a delayed projection must not repeatedly hide an already presented reminder.
        pendingFeedbackIDs.formUnion(boundary.subtracting(unconfirmedViewIDs)); updatePresentation()
        Task {
            var confirmed = false
            do {
                var request = try authorizedRequest(endpoint, path: "/view"); request.httpMethod = "POST"; request.timeoutInterval = 4
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["requestId": requestID, "sessionId": id,
                    "instanceId": instance, "sourceEpoch": epoch, "throughSequence": sequence])
                let (data, response) = try await network.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    let receipt = try JSONDecoder().decode(ViewReceipt.self, from: data)
                    confirmed = receipt.confirms(requestId: requestID, sessionId: id, instanceId: instance, sourceEpoch: epoch,
                        throughSequence: sequence, foregroundUnchanged: dshForeground && generation == foregroundGeneration && store.sourceEpoch == epoch && self.endpoint?.sourceEpoch == epoch)
                }
            } catch { /* An unconfirmed view retains unread and normal reminder behavior. */ }
            activeViews.remove(id); pendingFeedbackIDs.subtract(boundary)
            if !confirmed { unconfirmedViewIDs.formUnion(boundary); retryViewedAfter[id] = now + 5000 }
            if confirmed {
                unconfirmedViewIDs.subtract(boundary); retryViewedAfter.removeValue(forKey: id)
                store.markRead(sessionId: id, ids: boundary)
                dismissedFeedbackIDs.formUnion(boundary)
                if !previewOnly { persist() }
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(boundary))
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(boundary))
                removeBubbles(ids: boundary)
            }
            for noticeID in boundary {
                if let notice = pendingNotices.removeValue(forKey: noticeID), !confirmed,
                   store.notices.contains(where: { $0.id == noticeID && !$0.read && !$0.resolved }) { present(notice) }
            }
            updatePresentation()
            let remaining = pendingNotices.values.filter { $0.sessionId == id }
            if !remaining.isEmpty {
                if viewStatus?.eligible(sessionId: id, foreground: dshForeground, now: now) == true { confirmViewing(id) }
                else { for notice in remaining { pendingNotices.removeValue(forKey: notice.id); pendingFeedbackIDs.remove(notice.id); present(notice) } }
            }
        }
    }

    init(preferences: UserDefaults = .standard, previewOnly: Bool = false) {
        self.preferences = preferences; self.previewOnly = previewOnly
        mode = preferences.string(forKey: "notificationMode").flatMap(NotificationMode.init(rawValue:))
        alwaysOnTop = preferences.object(forKey: "alwaysOnTop") as? Bool ?? true
        reminderRetention = ReminderRetention.saved(preferences.string(forKey: "reminderRetention"))
        bubbleStyle = BubbleStyle.saved(preferences.string(forKey: "bubbleStyle"))
        showInFullScreen = preferences.bool(forKey: "showInFullScreen")
        dismissedFeedbackIDs = Set(preferences.stringArray(forKey: "dismissedFeedbackIDs") ?? [])
        dshHome = preferences.string(forKey: "dshHome") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh").path
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 27; config.timeoutIntervalForResource = 30
        // This session talks only to 127.0.0.1. Never forward the local bearer token through a system proxy.
        config.connectionProxyDictionary = [:]
        network = URLSession(configuration: config)
        super.init()
        guard !previewOnly else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? Data(contentsOf: Self.directory.appendingPathComponent("state.json")), let value = try? JSONDecoder().decode(SessionStore.self, from: data) { store = value }
        if mode == .pet, reminderRetention == .untilOpened,
           let id = preferences.string(forKey: "retainedBubbleID"),
           let notice = store.notices.first(where: { $0.id == id && !$0.read && !$0.resolved }) {
            reminderQueue.enqueue(notice, retention: reminderRetention, now: now); bubble = notice
        }
        cursor = store.sequence; cursorEpoch = store.sourceEpoch
        launchAtLogin = SMAppService.mainApp.status == .enabled
        UNUserNotificationCenter.current().delegate = self
        refreshIntegration()
    }
    var portrait: SessionRecord? { store.portrait(connected: connected, retention: reminderRetention, dismissedFeedbackIDs: dismissedFeedbackIDs.union(pendingFeedbackIDs)) }
    var taskState: TaskState { portrait?.state ?? .idle }
    var displayedTaskState: TaskState { bubblePreviewEnabled ? bubblePreviewKind.state : animationPreview.displayedState(live: taskState) }
    var visibleBubble: Notice? { bubblePreviewEnabled ? bubblePreviewKind.notice : animationPreview.enabled ? nil : bubble }
    func beginBubblePreview() {
        guard mode == .pet else { return }
        animationPreview.end(); bubblePreviewEnabled = true; petController?.update()
    }
    func endBubblePreview() { bubblePreviewEnabled = false; petController?.update() }
    func setPetSpaceVisible(_ visible: Bool) {
        guard petSpaceVisible != visible else { return }
        petSpaceVisible = visible
        if !visible { closePetFeedback() } else { petController?.update() }
    }
    private func closePetFeedback() {
        let ids = Set(store.notices.filter { !$0.read && !$0.resolved }.map(\.id))
        dismissedFeedbackIDs.formUnion(ids)
        preferences.set(Array(dismissedFeedbackIDs), forKey: "dismissedFeedbackIDs")
        bubbleTask?.cancel(); reminderQueue.clear(); bubble = nil
        preferences.removeObject(forKey: "retainedBubbleID")
        animationPreview.end(); bubblePreviewEnabled = false; updatePresentation()
    }
    var usesIsolatedPreview: Bool { previewOnly }
    func setAnimationPreview(_ enabled: Bool) {
        if enabled && mode == .pet { bubblePreviewEnabled = false; animationPreview.begin(state: taskState) }
        else { animationPreview.end() }
        petController?.update()
    }
    func selectPreviewState(_ state: TaskState) { animationPreview.select(state) }
    func setPreviewPlaying(_ playing: Bool) { animationPreview.setPlaying(playing) }
    var pendingSessions: [SessionRecord] { store.orderedSessions.filter { $0.state == .waiting || !store.unreadIDs(sessionId: $0.id).isEmpty } }
    private var patchURL: URL { URL(fileURLWithPath: dshHome).appendingPathComponent("profiles/desktop/cordis.patch.yml") }
    var dshInstalled: Bool { FileManager.default.fileExists(atPath: "/Applications/DeepSeek Harness.app") }
    var dshVersion: String? { Bundle(path: "/Applications/DeepSeek Harness.app")?.infoDictionary?["CFBundleShortVersionString"] as? String }

    func start() {
        applyMode()
        if !previewOnly { watchAttention() }
        pollTask = Task { [weak self] in await self?.poll() }
        Task { await refreshPermission() }
    }
    func stop() { if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }; attentionTimer?.cancel(); pollTask?.cancel(); expireTask?.cancel(); bubbleTask?.cancel(); network.invalidateAndCancel() }
    func applyMode() {
        NSApp.setActivationPolicy(mode == .native || mode == nil ? .regular : .accessory)
        NSApp.dockTile.badgeLabel = mode == .native && store.unreadCount > 0 ? String(store.unreadCount) : nil
        petController?.update()
        if mode == .native && !previewOnly { Task { await requestPermission() } }
    }
    func refreshIntegration() {
        integrationEnabled = (try? String(contentsOf: patchURL, encoding: .utf8).contains(IntegrationPatch.begin)) ?? false
    }
    func chooseHome() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "选择 DSH 配置目录"
        if panel.runModal() == .OK, let url = panel.url { dshHome = url.path }
    }
    func enableIntegration() {
        guard !previewOnly else { return }
        do {
            guard dshVersion == "0.2.0-rc.2" else { throw AppFailure.message("当前试用版已验证 DeepSeek Harness 0.2.0-rc.2。未找到这个版本，请检查 DSH 安装；其他版本尚待兼容验证。") }
            guard FileManager.default.fileExists(atPath: patchURL.deletingLastPathComponent().appendingPathComponent("package.json").path) else { throw AppFailure.message("尚未找到桌面版 DSH 配置。请先启动 DSH 一次，或选择正确的配置目录。") }
            guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("plugin"), FileManager.default.fileExists(atPath: bundled.appendingPathComponent("lib/index.js").path) else { throw AppFailure.message("安装包缺少内置集成，请使用构建完成的 App。") }
            let destination = Self.directory.appendingPathComponent("plugin-v0.1.0", isDirectory: true)
            let old = FileManager.default.fileExists(atPath: patchURL.path) ? try String(contentsOf: patchURL, encoding: .utf8) : ""
            let new = try IntegrationPatch.installing(into: old, pluginEntry: destination.appendingPathComponent("lib/index.js").path)
            let staged = Self.directory.appendingPathComponent("plugin-staging-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.copyItem(at: bundled, to: staged)
            if FileManager.default.fileExists(atPath: destination.path) {
                // Only an application-owned directory bearing our exact manifest may be updated.
                let data = try Data(contentsOf: destination.appendingPathComponent("package.json"))
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard object?["name"] as? String == "dsh-always-on" else { throw AppFailure.message("集成目录存在同名内容，已保留原文件，请检查后重试。") }
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw AppFailure.message("集成目录是符号链接，已保留原文件，请检查后重试。") }
                // Retain the previous owned plugin so an update remains recoverable.
                try FileManager.default.moveItem(at: destination, to: Self.directory.appendingPathComponent("plugin-backup-\(UUID().uuidString)", isDirectory: true))
            }
            try FileManager.default.moveItem(at: staged, to: destination)
            if new != old {
                if !old.isEmpty { try old.write(to: patchURL.appendingPathExtension("always-on-backup-\(UUID().uuidString)"), atomically: true, encoding: .utf8) }
                try new.write(to: patchURL, atomically: true, encoding: .utf8)
            }
            refreshIntegration(); feedback = "集成已启用，无需单独安装插件。若本次更新了集成，请在方便时重新打开 DSH，使新版本生效。"
        } catch { feedback = readable(error) }
    }
    func disableIntegration() {
        guard !previewOnly else { return }
        do {
            let old = try String(contentsOf: patchURL, encoding: .utf8)
            var new = try IntegrationPatch.removing(from: old)
            if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { new = "[]\n" }
            if new == old { return }
            try old.write(to: patchURL.appendingPathExtension("always-on-backup-\(UUID().uuidString)"), atomically: true, encoding: .utf8)
            try new.write(to: patchURL, atomically: true, encoding: .utf8)
            refreshIntegration(); feedback = "集成已移除，其他 DSH 配置已保留。"
        } catch { feedback = readable(error) }
    }
    func setLogin(_ enabled: Bool) {
        guard !previewOnly else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { feedback = "请在系统设置的登录项中允许 DSH Always On。" }
        } catch { feedback = "开机启动设置失败：\(readable(error))" }
    }
    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .badge, .sound]) }
            catch { feedback = "系统通知权限申请失败：\(error.localizedDescription)" }
        }
        await refreshPermission()
    }
    func refreshPermission() async {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationPermission = "已允许"
        case .denied: notificationPermission = "已关闭，可在系统设置中开启"
        default: notificationPermission = "未请求"
        }
    }
    func openNotificationSettings() { if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) } }
    func readSession(_ id: String) {
        let ids = store.unreadIDs(sessionId: id)
        store.markRead(sessionId: id, ids: ids); if !previewOnly { persist() }
        if !previewOnly {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(ids))
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(ids))
        }
        removeBubbles(ids: ids); updatePresentation()
    }
    func clickCharacter() {
        if bubblePreviewEnabled { endBubblePreview(); showMain() }
        else if animationPreview.enabled { showMain() }
        else if let bubble { openSession(bubble.sessionId) }
        else if pendingSessions.count == 1 { openSession(pendingSessions[0].id) }
        else if pendingSessions.isEmpty, let record = portrait { openSession(record.id) }
        else { showMain() }
    }
    func openSession(_ id: String) {
        let readBoundary = store.unreadIDs(sessionId: id)
        let displayedID = bubble?.sessionId == id ? bubble?.id : nil
        if previewOnly {
            store.markRead(sessionId: id, ids: readBoundary)
            removeBubbles(ids: readBoundary.union(displayedID.map { [$0] } ?? [])); updatePresentation(); return
        }
        guard connected, let endpoint else { feedback = "DSH 尚未连接。请启动 DSH 后重试。"; showMain(); return }
        // Focus is separate from navigation; the bridge still waits for exact selection.
        if let url = URL(string: "dsh://open") { NSWorkspace.shared.open(url) }
        Task {
            do {
                var request = try authorizedRequest(endpoint, path: "/open")
                request.httpMethod = "POST"; request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let requestId = UUID().uuidString
                request.httpBody = try JSONSerialization.data(withJSONObject: ["requestId": requestId, "sessionId": id])
                let (data, response) = try await network.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppFailure.message("会话跳转请求失败，请重试。") }
                let result = try JSONSerialization.jsonObject(with: data) as? [String: String]
                guard result?["requestId"] == requestId else { throw AppFailure.message("会话跳转未收到有效确认，请重试。") }
                if result?["status"] == "opened" {
                    store.markRead(sessionId: id, ids: readBoundary); persist()
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(readBoundary))
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(readBoundary))
                    removeBubbles(ids: readBoundary.union(displayedID.map { [$0] } ?? [])); updatePresentation()
                } else {
                    switch result?["status"] {
                    case "not_found": feedback = "这个会话已不存在，或当前 DSH 界面无法找到它。"
                    case "disconnected": feedback = "DSH 界面尚未连接。重新打开 DSH 后再试。"
                    default: feedback = "尚未确认打开目标会话，提醒仍保留。请重试或在 DSH 中查看。"
                    }
                    showMain()
                }
            } catch { feedback = readable(error); showMain() }
        }
    }
    private func authorizedRequest(_ endpoint: Endpoint, path: String) throws -> URLRequest {
        guard endpoint.protocolVersion.hasPrefix("1."), endpoint.port > 0, endpoint.port <= 65535, endpoint.token.count == 64,
              let url = URL(string: "http://127.0.0.1:\(endpoint.port)\(path)") else { throw AppFailure.message("集成协议不兼容，请重新启用集成。") }
        var request = URLRequest(url: url); request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization"); return request
    }
    private func poll() async {
        while !Task.isCancelled {
            do {
                let data = try Data(contentsOf: Self.directory.appendingPathComponent("endpoint.json"))
                let discovered = try JSONDecoder().decode(Endpoint.self, from: data)
                if cursorEpoch != discovered.sourceEpoch { cursor = -1; cursorEpoch = "" }
                endpoint = discovered
                let request = try authorizedRequest(discovered, path: "/poll?after=\(cursor)&epoch=\(cursorEpoch)")
                let (body, response) = try await network.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, body.count <= 4_000_000 else { throw AppFailure.message("连接校验失败，请重新启用集成。") }
                let feed = try JSONDecoder().decode(BridgeFeed.self, from: body)
                var candidate = store
                let new = try candidate.apply(feed)
                try save(candidate)
                store = candidate
                if viewStatus?.sessionId != feed.viewStatus?.sessionId { unconfirmedViewIDs.removeAll(); retryViewedAfter.removeAll() }
                viewStatus = feed.viewStatus
                dismissedFeedbackIDs.formIntersection(Set(store.notices.map(\.id)))
                preferences.set(Array(dismissedFeedbackIDs), forKey: "dismissedFeedbackIDs")
                cursor = feed.throughSequence; cursorEpoch = feed.sourceEpoch
                connected = true; clientConnected = feed.clientConnected
                connectionLabel = clientConnected ? "DSH 已连接" : "任务连接正常，等待 DSH 界面"
                for notice in new where viewStatus?.eligible(sessionId: notice.sessionId, foreground: dshForeground, now: now) == true {
                    pendingFeedbackIDs.insert(notice.id)
                }
                reconcileResolved(); updatePresentation()
                for notice in new { route(notice) }
                if let id = viewStatus?.sessionId, !store.unreadIDs(sessionId: id).isEmpty { confirmViewing(id) }
                scheduleFeedbackExpiration()
            } catch {
                if Task.isCancelled { break }
                if error is StoreError { cursor = -1; cursorEpoch = "" }
                connected = false; clientConnected = false
                connectionLabel = integrationEnabled ? "等待 DSH 连接" : "集成尚未启用"
                if case AppFailure.message(let message) = error { connectionLabel = message }
                if error is StoreError { connectionLabel = "状态正在重新同步" }
                if reminderRetention != .untilOpened {
                    bubbleTask?.cancel(); reminderQueue.clear(); bubble = nil
                }
                updatePresentation()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    private func save(_ value: SessionStore) throws {
        let data = try JSONEncoder().encode(value)
        let file = Self.directory.appendingPathComponent("state.json")
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private func persist() {
        do { try save(store) }
        catch { feedback = "提醒记录保存失败，重启后的恢复可能受影响。" }
    }
    private func updatePresentation() {
        NSApp.dockTile.badgeLabel = mode == .native && store.unreadCount > 0 ? String(store.unreadCount) : nil
        objectWillChange.send(); petController?.update()
    }
    private func present(_ notice: Notice) {
        guard let mode else { return }
        // A genuine reminder always takes presentation priority over an animation test.
        animationPreview.end(); bubblePreviewEnabled = false
        if mode == .pet && dismissedFeedbackIDs.contains(notice.id) { return }
        if mode == .pet && !petSpaceVisible {
            dismissedFeedbackIDs.insert(notice.id); preferences.set(Array(dismissedFeedbackIDs), forKey: "dismissedFeedbackIDs"); updatePresentation(); return
        }
        if mode == .native {
            guard !previewOnly else { return }
            let content = UNMutableNotificationContent(); content.title = notice.title; content.body = notice.summary; content.sound = .default
            content.userInfo = ["sessionId": notice.sessionId, "instanceId": notice.instanceId]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: notice.id, content: content, trigger: nil))
        } else {
            reminderQueue.enqueue(notice, retention: reminderRetention, now: now)
            syncBubble()
        }
    }
    private func reconcileResolved() {
        let resolved = Set(store.notices.filter(\.resolved).map(\.id))
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(resolved))
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Array(resolved))
        removeBubbles(ids: resolved)
    }
    private func syncBubble() {
        bubble = reminderQueue.current; petController?.update()
        if reminderRetention == .untilOpened && mode == .pet {
            preferences.set(bubble?.id, forKey: "retainedBubbleID")
        } else { preferences.removeObject(forKey: "retainedBubbleID") }
        bubbleTask?.cancel()
        guard let id = bubble?.id, let delay = reminderQueue.remaining(retention: reminderRetention, now: now) else { return }
        bubbleTask = Task {
            try? await Task.sleep(for: .seconds(delay + 0.02))
            guard !Task.isCancelled else { return }
            reminderQueue.expire(id: id, retention: reminderRetention, now: now); syncBubble()
        }
    }
    private func removeBubbles(ids: Set<String>) {
        reminderQueue.remove(ids: ids, now: now); syncBubble()
    }
    func dismissBubble(id: String) {
        dismissedFeedbackIDs.insert(id)
        preferences.set(Array(dismissedFeedbackIDs), forKey: "dismissedFeedbackIDs")
        removeBubbles(ids: [id]); updatePresentation()
    }
    private func scheduleFeedbackExpiration() {
        expireTask?.cancel()
        guard let seconds = reminderRetention.seconds else { return }
        let deadlines = store.sessions.values.filter { [.success, .error].contains($0.state) }
            .map { $0.updatedAt + seconds * 1000 }.filter { $0 > now }
        guard let deadline = deadlines.min() else { return }
        let delay = max(0, (deadline - now) / 1000) + 0.02
        expireTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            updatePresentation(); scheduleFeedbackExpiration()
        }
    }
    #if DEBUG
    var showFullScreenFixture: () -> Void = {}
    func previewRetention(state: TaskState = .success, session: String = "preview-a") {
        guard previewOnly else { return }
        let timestamp = now, next = max(0, store.sequence) + 1
        let run = UUID().uuidString, waits = state == .waiting ? [["actionId": run, "reason": "approval"]] : []
        let record: [String: Any] = ["sessionId": session, "title": "停留时间演示", "runId": run,
                                   "state": state.rawValue, "activeWaits": waits, "updatedAt": timestamp]
        let event: [String: Any] = ["protocolVersion": "1.0", "eventId": run, "source": "deepseek-harness",
            "instanceId": "retention-preview", "sourceEpoch": "preview", "sequence": next,
            "sessionId": session, "title": "停留时间演示", "runId": run, "state": state.rawValue,
            "activeWaits": waits, "updatedAt": timestamp,
            "type": state == .waiting ? "session.waiting" : state == .error ? "task.failed" : "task.succeeded",
            "occurredAt": "preview", "summary": state.label + " · 点击可模拟成功打开", "notify": true]
        do {
            if store.sequence < 0 {
                let baseline: [String: Any] = ["protocolVersion": "1.0", "instanceId": "retention-preview", "sourceEpoch": "preview",
                    "throughSequence": 0, "reset": true, "clientConnected": true, "sessions": [], "events": []]
                _ = try store.apply(JSONDecoder().decode(BridgeFeed.self, from: JSONSerialization.data(withJSONObject: baseline)))
            }
            let records: [[String: Any]] = store.sessions.values.filter { $0.id != session }.map {
                ["sessionId": $0.id, "title": $0.title, "runId": $0.runId, "state": $0.state.rawValue,
                 "activeWaits": $0.activeWaits.map { ["actionId": $0.actionId, "reason": $0.reason] }, "updatedAt": $0.updatedAt]
            }
            let feed: [String: Any] = ["protocolVersion": "1.0", "instanceId": "retention-preview", "sourceEpoch": "preview",
                "throughSequence": next, "reset": false, "clientConnected": true, "sessions": records + [record], "events": [event]]
            let notices = try store.apply(JSONDecoder().decode(BridgeFeed.self, from: JSONSerialization.data(withJSONObject: feed)))
            connected = true; clientConnected = true; connectionLabel = "独立预览 · 未连接 DSH"
            for notice in notices { present(notice) }
            updatePresentation(); scheduleFeedbackExpiration()
        } catch { feedback = "预览数据加载失败" }
    }

    // Preview an existing reminder without creating a task or inserting fake unread history.
    func previewBubble(_ kind: Int) {
        guard mode == .pet, var notice = store.notices.last(where: {
            guard let session = store.sessions[$0.sessionId] else { return false }
            return session.available != false
        }) else {
            feedback = "请在桌面伙伴模式下，连接有提醒记录的 DSH 后再预览。"; showMain(); return
        }
        let labels = ["需要回答问题", "需要确认操作", "需要审阅计划", "任务已完成", "任务执行失败"]
        guard labels.indices.contains(kind) else { return }
        notice.id = "preview-\(UUID().uuidString)"
        notice.title = "[预览] \(labels[kind])"
        notice.summary = "这是气泡交互测试。点击气泡回到原提醒对应的会话，不会启动任务。"
        notice.state = kind < 3 ? .waiting : (kind == 3 ? .success : .error)
        reminderQueue.clear(); reminderQueue.enqueue(notice, retention: reminderRetention, now: now)
        syncBubble(); petController?.focusPreview()
    }
    #endif
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { self.mode == .native ? [.banner, .sound] : [] }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["sessionId"] as? String,
              let instance = response.notification.request.content.userInfo["instanceId"] as? String else { return }
        await MainActor.run { if instance == self.store.instanceId { self.openSession(id) } }
    }
    private func readable(_ error: Error) -> String {
        if case AppFailure.message(let message) = error { return message }
        if error is IntegrationPatch.PatchError { return "DSH 配置格式或集成标记存在冲突，原配置已保留。请检查后重试。" }
        return error.localizedDescription
    }
}
enum AppFailure: Error { case message(String) }
