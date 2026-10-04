import AppKit
import SwiftUI
import CompanionCore

@main struct DSHAlwaysOnMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--validate-character") {
            do {
                let result = try CharacterArtwork.shared.validate()
                let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } catch { fputs("Character validation failed: \(error)\n", stderr); exit(EXIT_FAILURE) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--export-brand"), CommandLine.arguments.count > index + 1 {
            do { try CompanionBrand.export(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)) }
            catch { fputs("Brand export failed: \(error)\n", stderr); exit(EXIT_FAILURE) }
            return
        }
        if CommandLine.arguments.contains("--export-art"), let index = CommandLine.arguments.firstIndex(of: "--export-art"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            do { try CharacterArtwork.shared.export(to: directory) }
            catch { fputs("Character export failed: \(error)\n", stderr); exit(EXIT_FAILURE) }
            let icon = ImageRenderer(content: CompanionAppIcon())
            icon.scale = 2
            if let image = icon.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: directory.appendingPathComponent("app-icon.png")) }
            return
        }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--validate-reminder-preview"), CommandLine.arguments.count > index + 1 {
            _ = NSApplication.shared
            do { try ReminderPreviewValidation.run(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)) }
            catch { fputs("Reminder preview validation failed: \(error)\n", stderr); exit(EXIT_FAILURE) }
            return
        }
        if CommandLine.arguments.contains("--preview-retention") {
            let app = NSApplication.shared
            let delegate = RetentionPreviewDelegate()
            app.delegate = delegate; app.run(); withExtendedLifetime(delegate) {}; return
        }
        if CommandLine.arguments.contains("--preview-character") {
            let app = NSApplication.shared
            let delegate = CharacterPreviewDelegate()
            app.delegate = delegate
            app.run()
            withExtendedLifetime(delegate) {}
            return
        }
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

#if DEBUG
@MainActor enum ReminderPreviewValidation {
    static func run(to directory: URL) throws {
        let suite = "DSHAlwaysOn.Validation.\(UUID().uuidString)", preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("pet", forKey: "notificationMode")
        let model = Coordinator(preferences: preferences, previewOnly: true)
        defer { model.stop() }
        func check(_ result: Bool, _ message: String) throws { if !result { throw AppFailure.message(message) } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func render<V: View>(_ content: V, name: String) throws {
            let renderer = ImageRenderer(content: content); renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw AppFailure.message("预览导出失败") }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
        }
        model.previewRetention(state: .waiting, session: "preview-b")
        let boundary = model.store.unreadIDs(sessionId: "preview-b")
        for style in BubbleStyle.allCases {
            model.bubbleStyle = style
            for kind in BubblePreviewKind.allCases {
                model.bubblePreviewKind = kind; model.beginBubblePreview()
                try check(model.visibleBubble?.id == kind.notice.id && model.displayedTaskState == kind.state, "预览状态错误")
                try check(model.store.unreadIDs(sessionId: "preview-b") == boundary, "预览更改了未读")
                for dark in [false, true] {
                    try render(BubbleView(model: model, notice: kind.notice, isPreview: true).environment(\.colorScheme, dark ? .dark : .light), name: "\(style.rawValue)-\(kind.rawValue)-\(dark ? "dark" : "light")")
                }
                model.endBubblePreview(); try check(!model.bubblePreviewEnabled, "预览没有结束")
            }
        }
        model.beginBubblePreview(); model.previewRetention()
        try check(!model.bubblePreviewEnabled && model.bubble?.instanceId == "retention-preview" && model.store.notices.last?.state == .success, "真实提醒未接管预览")
        let unread = model.store.unreadCount
        model.setPetSpaceVisible(false)
        try check(model.bubble == nil && model.store.unreadCount == unread, "隐藏更改未读")
        model.previewRetention(state: .error)
        try check(model.bubble == nil && model.store.unreadCount > 0, "隐藏时新提醒丢失或弹出")
        model.setPetSpaceVisible(true); try check(model.bubble == nil, "返回补弹了旧提醒")
        model.showInFullScreen = true; model.bubbleStyle = .glass
        let restored = Coordinator(preferences: preferences, previewOnly: true)
        defer { restored.stop() }
        try check(restored.showInFullScreen && restored.bubbleStyle == .glass && !restored.bubblePreviewEnabled, "设置或预览恢复错误")
        model.openSession("preview-b")
        try check(model.store.sessions["preview-b"]?.state == .waiting && model.store.unreadIDs(sessionId: "preview-b").isEmpty, "查看误处理了等待")
        model.beginBubblePreview(); model.mode = .native
        try check(!model.bubblePreviewEnabled, "模式切换保留了测试")
        model.mode = .pet
        for dark in [false, true] {
            if let image = CompanionBrand.menuImage() {
                try check(image.isTemplate && image.size == NSSize(width: 18, height: 18), "菜单图标不是 18 pt 模板")
                try render(Image(nsImage: image).frame(width: 18, height: 18).padding(8).background(dark ? Color.black : Color.white).environment(\.colorScheme, dark ? .dark : .light), name: "menu-\(dark ? "dark" : "light")")
            }
        }
        print("{\"isolatedPreviewChecks\":\"passed\",\"bubbleSamples\":20,\"settingsPersistence\":\"passed\",\"realReminderPriority\":\"passed\",\"unreadAndWaiting\":\"preserved\",\"hiddenQueueReplay\":false,\"realFullscreen\":\"requiresUnlockedMac\"}")
    }
}

@MainActor final class RetentionPreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var model: Coordinator!
    private var fullScreenWindow: NSWindow?
    private var previewStatusItem: NSStatusItem?
    private let suite = "DSHAlwaysOn.RetentionPreview.\(UUID().uuidString)"
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let preferences = UserDefaults(suiteName: suite)!
        preferences.set("pet", forKey: "notificationMode")
        model = Coordinator(preferences: preferences, previewOnly: true)
        model.petController = PetController(model: model)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 820), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "提醒停留时间 · 独立预览"; window.isReleasedWhenClosed = false
        let model = model!
        window.contentView = NSHostingView(rootView: RetentionPreviewView(model: model, preferences: preferences))
        model.showMain = { [weak self] in self?.window.makeKeyAndOrderFront(nil) }
        model.showFullScreenFixture = { [weak self] in self?.showFullScreen() }
        previewStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        previewStatusItem?.button?.image = CompanionBrand.menuImage()
        let menu = NSMenu(); menu.addItem(withTitle: "独立预览 · 设置", action: #selector(showPreview), keyEquivalent: ""); menu.items.first?.target = self
        menu.addItem(withTitle: "退出独立预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        previewStatusItem?.menu = menu
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showPreview() { window.makeKeyAndOrderFront(nil) }
    private func showFullScreen() {
        let fixture = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        fixture.title = "全屏隔离测试"; fixture.isReleasedWhenClosed = false; fixture.collectionBehavior = [.fullScreenPrimary]
        fixture.contentView = NSHostingView(rootView: FullScreenPreviewView(model: model))
        fullScreenWindow = fixture; fixture.center(); fixture.makeKeyAndOrderFront(nil); fixture.toggleFullScreen(nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.stop(); UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RetentionPreviewView: View {
    @ObservedObject var model: Coordinator
    let preferences: UserDefaults
    @State private var darkPreview = false
    var body: some View {
        VStack {
            HStack {
                Button("演示完成") { model.previewRetention() }
                Button("演示失败") { model.previewRetention(state: .error) }
                Button("另一会话等待") { model.previewRetention(state: .waiting, session: "preview-b") }
                Button("检查设置恢复") {
                    let restored = Coordinator(preferences: preferences, previewOnly: true)
                    model.feedback = "重载设置：\(restored.reminderRetention.label) · \(restored.bubbleStyle.label) · 全屏\(restored.showInFullScreen ? "显示" : "隐藏") · 动画测试\(restored.animationPreview.enabled ? "开启" : "关闭")"
                }
                Button("全屏隔离测试") { model.showFullScreenFixture() }
                Toggle("深色预览", isOn: $darkPreview)
            }.padding(.top, 12)
            Text("当前动作：\(model.displayedTaskState.label) · 当前气泡：\(model.visibleBubble?.summary ?? "已收起")")
                .font(.caption)
            if let notice = model.visibleBubble {
                BubbleView(model: model, notice: notice, isPreview: model.bubblePreviewEnabled).environment(\.colorScheme, darkPreview ? .dark : .light)
            }
            MainView(model: model)
        }
    }
}

struct FullScreenPreviewView: View {
    @ObservedObject var model: Coordinator
    var body: some View {
        VStack(spacing: 24) {
            Text("全屏隔离测试").font(.largeTitle)
            Text("桌宠在当前空间：\(model.petSpaceVisible ? "显示" : "隐藏") · 未读：\(model.store.unreadCount)")
            Toggle("全屏时显示桌宠", isOn: $model.showInFullScreen).frame(width: 240)
            Button("生成全屏提醒") { model.previewRetention() }
            Text("通过窗口的绿色按钮退出全屏；回到设置后，旧提醒不应补弹。")
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.blue.opacity(0.08))
    }
}

@MainActor final class CharacterPreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1190, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "均衡 Q 版 · 原生形象预览"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CharacterPreviewView())
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct CharacterPreviewView: View {
    @State private var playing = true
    @State private var reduced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("均衡 Q 版 · 原生动作").font(.title2.bold()); Text("同一套 App 素材与播放器；独立预览，不连接任务。").font(.caption).foregroundStyle(.secondary) }
                Spacer(); Toggle("播放动作", isOn: $playing); Toggle("减少动态效果", isOn: $reduced)
            }
            HStack(spacing: 16) {
                ForEach(TaskState.allCases, id: \.self) { state in
                    VStack(spacing: 8) {
                        CharacterView(state: state, animated: playing && !reduced)
                            .background(Color.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        Text(state.label).font(.caption)
                    }
                }
            }
        }.padding(24)
    }
}
#endif

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: Coordinator!
    private var mainWindow: NSWindow!
    private var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = Coordinator()
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        mainWindow.title = "DSH Always On"; mainWindow.isReleasedWhenClosed = false; mainWindow.center()
        mainWindow.contentView = NSHostingView(rootView: MainView(model: model))
        model.showMain = { [weak self] in self?.showWindow() }
        model.petController = PetController(model: model)
        let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(title: "DSH Always On")
        appMenu.addItem(withTitle: "DSH Always On 设置…", action: #selector(showWindow), keyEquivalent: ",")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "退出 DSH Always On", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); edit.submenu = NSMenu(title: "编辑")
        edit.submenu?.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.submenu?.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu?.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(edit); NSApp.mainMenu = menu
        #if DEBUG
        let preview = NSMenuItem(title: "开发预览", action: nil, keyEquivalent: "")
        preview.submenu = NSMenu(title: "开发预览")
        for (index, title) in ["问题气泡", "批准气泡", "计划审阅气泡", "完成气泡", "失败气泡"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(previewBubble(_:)), keyEquivalent: "")
            item.tag = index; item.target = self; preview.submenu?.addItem(item)
        }
        menu.addItem(preview)
        #endif
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = CompanionBrand.menuImage()
        let statusMenu = NSMenu()
        statusMenu.addItem(withTitle: "会话与设置…", action: #selector(showWindow), keyEquivalent: "")
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "原生通知", action: #selector(nativeMode), keyEquivalent: "")
        statusMenu.addItem(withTitle: "桌面伙伴", action: #selector(petMode), keyEquivalent: "")
        statusMenu.addItem(.separator()); statusMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = statusMenu
        model.start()
        #if DEBUG
        showWindow()
        #else
        if model.mode == nil || !model.integrationEnabled { showWindow() }
        #endif
    }
    @objc func showWindow() { mainWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func nativeMode() { model.mode = .native }
    @objc func petMode() { model.mode = .pet }
    @objc func toggleTop() { model.alwaysOnTop.toggle() }
    #if DEBUG
    @objc func previewBubble(_ sender: NSMenuItem) { model.previewBubble(sender.tag) }
    #endif
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}

@MainActor enum CompanionBrand {
    static func menuImage() -> NSImage? {
        let image = NSImage(named: "DSMenuIcon") ?? ImageRenderer(content: CompanionMenuIcon()).nsImage
        image?.size = NSSize(width: 18, height: 18); image?.isTemplate = true
        image?.accessibilityDescription = "DS 娘 · 会话与设置"
        return image
    }
    static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let icon = directory.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
        let menu = directory.appendingPathComponent("DSMenuIcon.imageset", isDirectory: true)
        try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: menu, withIntermediateDirectories: true)
        func write<V: View>(_ view: V, scale: CGFloat, to url: URL) throws {
            let renderer = ImageRenderer(content: view); renderer.scale = scale
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw AppFailure.message("图标导出失败") }
            try png.write(to: url)
        }
        var entries: [[String: String]] = []
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let file = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try write(CompanionAppIcon(), scale: CGFloat(size * scale) / 512, to: icon.appendingPathComponent(file))
                entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": file])
            }
        }
        try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: icon.appendingPathComponent("Contents.json"))
        for scale in [1, 2] { try write(CompanionMenuIcon(), scale: CGFloat(scale), to: menu.appendingPathComponent("menu\(scale)x.png")) }
        try JSONSerialization.data(withJSONObject: ["images": [["idiom": "universal", "scale": "1x", "filename": "menu1x.png"], ["idiom": "universal", "scale": "2x", "filename": "menu2x.png"]], "properties": ["template-rendering-intent": "template"], "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys]).write(to: menu.appendingPathComponent("Contents.json"))
    }
}
