import AppKit
import SwiftUI
import CompanionCore

@MainActor final class PetController {
    private let model: Coordinator
    private let pet: NSPanel
    private let speech: NSPanel
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var dragged = false
    private var displayedNoticeID: String?
    private var spaceTask: Task<Void, Never>?
    init(model: Coordinator) {
        self.model = model
        pet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: CharacterArtwork.size, height: 240), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        speech = ActionableBubblePanel(contentRect: NSRect(origin: .zero, size: BubblePlacement.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        speech.title = "任务提醒"
        speech.becomesKeyOnlyIfNeeded = true
        for panel in [pet, speech] {
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
        }
        let hosting = DraggablePetView(rootView: PetView(model: model))
        hosting.onClick = { [weak model] in model?.clickCharacter() }
        hosting.onDrag = { [weak self] in self?.dragged = true; self?.positionBubble() }
        hosting.onEnd = { [weak self] in self?.dragged = false; self?.snapAndSave() }
        hosting.makeMenu = { [weak model] in
            let menu = NSMenu()
            menu.addItem(withTitle: "查看会话与设置…", action: #selector(AppDelegate.showWindow), keyEquivalent: "")
            let top = NSMenuItem(title: "总在最上层", action: #selector(AppDelegate.toggleTop), keyEquivalent: ""); top.state = model?.alwaysOnTop == true ? .on : .off; menu.addItem(top)
            menu.addItem(withTitle: "切换到原生通知", action: #selector(AppDelegate.nativeMode), keyEquivalent: "")
            menu.addItem(.separator()); menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            return menu
        }
        pet.contentView = hosting
        pet.isMovable = true
        restorePosition()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.restorePosition() } }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in Task { @MainActor in self?.updateMouseRegion() } }
        spaceTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkSpace()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in self?.updateMouseRegion(); return event }
    }
    deinit { spaceTask?.cancel(); if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) } }
    #if DEBUG
    func focusPreview() { speech.makeKeyAndOrderFront(nil) }
    #endif
    func update() {
        let level: NSWindow.Level = model.alwaysOnTop ? .floating : .normal
        pet.level = level; speech.level = level
        let behavior: NSWindow.CollectionBehavior = model.showInFullScreen ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.canJoinAllSpaces, .fullScreenNone]
        pet.collectionBehavior = behavior; speech.collectionBehavior = behavior
        if model.mode == .pet {
            pet.orderFrontRegardless()
            if let notice = model.visibleBubble {
                // Keep a displayed notice bound to its own session throughout a click.
                // Polling and portrait updates must not replace the hosting view mid-gesture.
                if displayedNoticeID != notice.id {
                    speech.contentView = FirstClickHostingView(rootView: BubbleView(model: model, notice: notice, isPreview: model.bubblePreviewEnabled))
                    displayedNoticeID = notice.id
                }
                positionBubble(); if model.petSpaceVisible { speech.orderFrontRegardless() } else { speech.orderOut(nil) }
            } else { speech.orderOut(nil); displayedNoticeID = nil }
            updateMouseRegion()
        } else { pet.orderOut(nil); speech.orderOut(nil) }
    }
    private func checkSpace() {
        guard model.mode == .pet else { return }
        // Space membership is local to this pet window, unlike global fullscreen guesses.
        let visible = model.showInFullScreen || pet.isOnActiveSpace
        model.setPetSpaceVisible(visible)
        if !visible { speech.orderOut(nil) }
    }
    private var screen: NSScreen { NSScreen.screens.first(where: { $0.frame.intersects(pet.frame) }) ?? NSScreen.main ?? NSScreen.screens[0] }
    private func restorePosition() {
        guard let main = NSScreen.main ?? NSScreen.screens.first else { return }
        let saved = model.usesIsolatedPreview ? nil : UserDefaults.standard.dictionary(forKey: "petPosition")
        let target = NSScreen.screens.first { String(describing: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "") == saved?["screen"] as? String } ?? main
        let frame = target.visibleFrame
        let x = saved?["x"] as? Double ?? 0.96; let y = saved?["y"] as? Double ?? 0.06
        pet.setFrameOrigin(NSPoint(x: frame.minX + x * max(0, frame.width - pet.frame.width), y: frame.minY + y * max(0, frame.height - pet.frame.height)))
        snapAndSave()
    }
    private func snapAndSave() {
        guard !NSScreen.screens.isEmpty else { return }
        let frame = screen.visibleFrame; var point = pet.frame.origin
        point.x = min(max(point.x, frame.minX), max(frame.minX, frame.maxX - pet.frame.width))
        point.y = min(max(point.y, frame.minY), max(frame.minY, frame.maxY - pet.frame.height))
        if point.x - frame.minX < 16 { point.x = frame.minX }
        if frame.maxX - (point.x + pet.frame.width) < 16 { point.x = frame.maxX - pet.frame.width }
        if point.y - frame.minY < 16 { point.y = frame.minY }
        if frame.maxY - (point.y + pet.frame.height) < 16 { point.y = frame.maxY - pet.frame.height }
        pet.setFrameOrigin(point)
        if !model.usesIsolatedPreview {
            UserDefaults.standard.set(["screen": String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? ""), "x": (point.x - frame.minX) / max(1, frame.width - pet.frame.width), "y": (point.y - frame.minY) / max(1, frame.height - pet.frame.height)], forKey: "petPosition")
        }
        positionBubble()
    }
    private func positionBubble() {
        guard !NSScreen.screens.isEmpty else { return }
        let placement = BubblePlacement.beside(pet: pet.frame, screen: screen.visibleFrame)
        if model.bubbleTailSide != placement.tailSide { model.bubbleTailSide = placement.tailSide }
        if model.bubbleTailOffset != placement.tailOffset { model.bubbleTailOffset = placement.tailOffset }
        speech.setFrame(placement.frame, display: true)
    }
    private func updateMouseRegion() {
        guard !dragged else { return }
        let point = NSEvent.mouseLocation
        let local = NSPoint(x: point.x - pet.frame.minX, y: pet.frame.maxY - point.y)
        let silhouette = CharacterArtwork.shared.contains(local)
        let label = NSRect(x: 30, y: CharacterArtwork.size, width: CharacterArtwork.size - 60, height: 27).contains(local)
        pet.ignoresMouseEvents = !(silhouette || label)
    }
}

@MainActor final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    // A notification is actionable while another application is active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class ActionableBubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor final class DraggablePetView<Content: View>: NSHostingView<Content> {
    var onClick: () -> Void = {}
    var onDrag: () -> Void = {}
    var onEnd: () -> Void = {}
    var makeMenu: () -> NSMenu = { NSMenu() }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let initialOrigin = window.frame.origin
        let initialMouse = window.convertPoint(toScreen: event.locationInWindow)
        var moved = false
        onDrag()
        // Track the complete gesture here so SwiftUI descendants cannot consume it.
        while let tracked = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if tracked.type == .leftMouseUp { break }
            let point = window.convertPoint(toScreen: tracked.locationInWindow)
            let delta = NSPoint(x: point.x - initialMouse.x, y: point.y - initialMouse.y)
            if abs(delta.x) + abs(delta.y) > 3 { moved = true }
            if moved { window.setFrameOrigin(NSPoint(x: initialOrigin.x + delta.x, y: initialOrigin.y + delta.y)); onDrag() }
        }
        onEnd()
        if !moved { onClick() }
    }
    override func mouseUp(with event: NSEvent) { }
    override func rightMouseDown(with event: NSEvent) { NSMenu.popUpContextMenu(makeMenu(), with: event, for: self) }
}
