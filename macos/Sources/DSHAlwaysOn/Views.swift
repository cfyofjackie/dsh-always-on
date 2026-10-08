import SwiftUI
import CompanionCore

struct MainView: View {
    @ObservedObject var model: Coordinator
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill").font(.system(size: 28)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) { Text("DSH Always On").font(.title2.bold()); Text("让后台任务的进展，及时来到你身边。").foregroundStyle(.secondary) }
                Spacer()
                Label(model.mode == .companion ? "陪伴中" : model.connected ? "已连接" : "正在连接", systemImage: model.mode == .companion ? "heart.fill" : model.connected ? "checkmark.circle.fill" : "circle.dotted").foregroundStyle(model.mode == .companion || model.connected ? .green : .secondary)
            }
            HStack(spacing: 12) {
                modeCard(.companion, symbol: "heart.fill", subtitle: "全部动作随机表演，无需连接 DSH")
                modeCard(.pet, symbol: "sparkles", subtitle: "任务动作、气泡和会话跳转")
            }
            if model.mode == .pet {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("DeepSeek Harness 集成").font(.headline); Spacer(); Text(model.connectionLabel).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Text(model.integrationEnabled ? "内置集成已启用" : "启用后，无需单独下载插件。").foregroundStyle(.secondary)
                        Spacer()
                        if model.integrationEnabled {
                            Button("更新集成") { model.enableIntegration() }
                            Button("移除集成", role: .destructive) { model.disableIntegration() }
                        }
                        else { Button("启用集成") { model.enableIntegration() }.buttonStyle(.borderedProminent) }
                    }
                    HStack { Text("配置目录：\(model.dshHome)").font(.caption).foregroundStyle(.secondary).lineLimit(1); Spacer(); Button("选择目录…") { model.chooseHome() }.font(.caption) }
                    if model.connected && !model.clientConnected { Text("等待 DSH 界面连接后，才能准确跳回会话。").font(.caption).foregroundStyle(.orange) }
                }.padding(5)
            }
            }
            if model.mode == .companion {
                GroupBox("陪伴动作") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("播放方式", selection: $model.companionFixedAnimation) {
                            Text("随机切换全部动作").tag(nil as PetAnimation?)
                            ForEach(PetAnimation.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                        }
                        Text("工作、等待和失败也是角色表演，不代表真实任务，不产生未读或任务气泡。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(5)
                }
            }
            HStack {
                Toggle("开机启动", isOn: Binding(get: { model.launchAtLogin }, set: model.setLogin))
                Spacer()
                Toggle("桌宠置顶", isOn: $model.alwaysOnTop)
            }
            Picker("全屏显示", selection: $model.fullScreenPolicy) {
                ForEach(FullScreenPolicy.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text("全屏完全隐藏时，没有系统横幅兜底；未读保留在会话列表。返回桌面不补弹旧队列。")
                .font(.caption).foregroundStyle(.secondary)
            if model.mode == .pet {
            Picker("当前前台会话提醒", selection: $model.foregroundStyle) {
                ForEach(ForegroundReminderStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text("默认完成只播放动作；失败、提问、批准和计划审阅仍显示气泡。其他会话正常提醒。")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Picker("桌宠提醒停留时间", selection: $model.reminderRetention) {
                    ForEach(ReminderRetention.allCases, id: \.self) { option in Text(option.label).tag(option) }
                }.frame(maxWidth: 440).disabled(model.mode != .pet)
                Text("控制完成、失败动作与所有气泡；一直保留时，成功打开会话或点 × 后收起。工作和等待状态随任务变化。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
            GroupBox("气泡外观与测试") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("气泡外观", selection: $model.bubbleStyle) {
                        ForEach(BubbleStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("测试内容", selection: $model.bubblePreviewKind) {
                        ForEach(BubblePreviewKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack(spacing: 16) {
                        BubbleView(model: model, notice: model.bubblePreviewKind.notice, isPreview: true)
                        VStack(alignment: .leading, spacing: 10) {
                            Button(model.bubblePreviewEnabled ? "结束桌面气泡测试" : "在桌面测试气泡") {
                                if model.bubblePreviewEnabled { model.endBubblePreview() } else { model.beginBubblePreview() }
                            }
                            Text("样例不产生未读，也不跳转真实会话。桌面测试持续到关闭；新提醒到来时自动结束。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(5)
            }
            if model.mode == .pet {
            GroupBox("待机小生活") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("摸鱼开始时间", selection: $model.petIdleDelay) {
                        ForEach(PetIdleDelay.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).disabled(model.mode != .pet)
                    Text("待机后随机吃饭、扔小鲸鱼、摸头开心或摸小鲸鱼，演完一轮再回待机。你继续操作电脑也可以触发；工作、等待和提醒期间不摸鱼。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(5)
            }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("动作与气泡预览", isOn: Binding(get: { model.animationPreview.enabled }, set: model.setAnimationPreview))
                    if model.animationPreview.enabled {
                        HStack(spacing: 16) {
                            CharacterView(state: model.animationPreview.selectedState, animated: model.animationPreview.playing, animation: model.animationPreview.selectedAnimation, revision: model.animationPreview.revision)
                                .scaleEffect(0.62).frame(width: 130, height: 130)
                                .background(Color.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("预览动作", selection: Binding(get: { model.animationPreview.selectedAnimation }, set: model.selectPreviewAnimation)) {
                                    ForEach(PetAnimation.allCases, id: \.self) { Text($0.label).tag($0) }
                                }.pickerStyle(.menu)
                                Toggle("同时显示样例气泡", isOn: $model.previewShowsBubble)
                                if let kind = model.previewBubbleKind {
                                    BubbleView(model: model, notice: kind.notice, isPreview: true)
                                } else {
                                    Text("此动作没有对应任务气泡。等待动作可在上方选择提问、批准或计划审阅。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Toggle("播放动作", isOn: Binding(get: { model.animationPreview.playing }, set: model.setPreviewPlaying))
                                    Spacer()
                                    Button("从头播放") { model.restartPreviewAnimation() }
                                    Button("恢复真实状态") { model.setAnimationPreview(false) }
                                }
                                Text("动画测试中：所选动作持续展示，方便截图。新任务提醒到来时会自动恢复真实状态。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("预览五种状态和四种小生活动作，并暂停截图；测试时长与上方真实提醒的停留时间分开。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(5).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let feedback = model.feedback {
                HStack(alignment: .top) { Image(systemName: "info.circle"); Text(feedback).font(.callout); Spacer(); Button { model.feedback = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                    .padding(10).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.mode == .pet {
            HStack { Text("会话").font(.headline); Spacer(); Text(model.store.unreadCount > 0 ? "\(model.store.unreadCount) 个会话有未读提醒" : "没有未读提醒").font(.caption).foregroundStyle(.secondary) }
            if model.store.orderedSessions.isEmpty {
                ContentUnavailableView("等待第一个任务", systemImage: "tray", description: Text("在 DSH 中运行任务后，这里会显示状态和提醒。"))
                    .frame(maxWidth: .infinity).frame(height: 160)
            } else {
                    LazyVStack(spacing: 8) {
                        ForEach(model.store.orderedSessions) { session in
                            HStack(spacing: 12) {
                                Circle().fill(session.state == .waiting ? Color.orange : session.state == .error ? Color.red : Color.blue).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title).font(.body.weight(.medium)).lineLimit(1)
                                    Text(model.store.latestNotice(sessionId: session.id).map { $0.summary + ($0.resolved ? " · 已处理" : "") } ?? session.state.label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Text(session.available == false ? "会话未加载" : model.connected ? session.state.label : "最近状态").font(.caption).foregroundStyle(.secondary)
                                if !model.store.unreadIDs(sessionId: session.id).isEmpty {
                                    Button("标为已读") { model.readSession(session.id) }.font(.caption)
                                }
                                Button("打开会话") { model.openSession(session.id) }.disabled(!model.connected)
                            }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
            }
            HStack { Text("点击提醒回到 DSH；回答、批准和审阅仍在 DSH 中完成。").font(.caption).foregroundStyle(.secondary); Spacer() }
            }
            Text(model.versionLabel).font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        }.frame(minWidth: 640, minHeight: 590)
    }
    private func modeCard(_ mode: NotificationMode, symbol: String, subtitle: String) -> some View {
        Button { model.mode = mode } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) { Text(mode.label).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: model.mode == mode ? "checkmark.circle.fill" : "circle").foregroundStyle(model.mode == mode ? Color.blue : Color.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(model.mode == mode ? Color.blue.opacity(0.10) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.mode == mode ? Color.blue.opacity(0.5) : .clear))
        }.buttonStyle(.plain)
    }
}

struct PetView: View {
    @ObservedObject var model: Coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var awake = true
    @State private var loaf = PetLoafPlayback()
    @State private var companion = CompanionPlayback()
    private var eligible: Bool {
        model.mode == .pet && model.petSpaceVisible && awake && !model.suspended && !reduceMotion &&
        !model.animationPreview.enabled && !model.bubblePreviewEnabled && model.displayedTaskState == .idle &&
        model.visibleBubble == nil && LifeArtwork.shared.manifest != nil
    }
    private var selected: PetAnimation {
        if model.animationPreview.enabled { return model.animationPreview.selectedAnimation }
        if model.bubblePreviewEnabled { return PetAnimation(state: model.displayedTaskState) }
        if model.mode == .companion { return reduceMotion ? model.companionFixedAnimation ?? .idle : companion.animation }
        return eligible ? loaf.animation ?? PetAnimation(state: model.displayedTaskState) : PetAnimation(state: model.displayedTaskState)
    }
    private struct IdleConfiguration: Hashable { var eligible: Bool; var delay: String }
    private struct CompanionConfiguration: Hashable { var enabled: Bool; var fixed: PetAnimation? }
    var body: some View {
        VStack(spacing: 0) {
            CharacterView(state: selected.taskState,
                animated: model.petSpaceVisible && awake && !model.suspended && (!model.animationPreview.enabled || model.animationPreview.playing),
                animation: selected, revision: model.animationPreview.enabled ? model.animationPreview.revision : model.mode == .companion ? companion.revision : 0,
                looping: model.animationPreview.enabled || model.companionFixedAnimation != nil || !selected.isLife)
            Text(model.bubblePreviewEnabled ? "气泡测试" : model.animationPreview.enabled ? "\(selected.label) · 动画测试" :
                 model.mode == .companion ? "陪伴 · " + selected.label : selected.isLife ? selected.label : model.connected ? model.displayedTaskState.label : "正在连接 · 休息中")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4).background(.black.opacity(0.50), in: Capsule())
        }.frame(width: CharacterArtwork.size, height: 240, alignment: .top)
            .task(id: IdleConfiguration(eligible: eligible,delay: model.petIdleDelay.rawValue)) {
                loaf.reset()
                guard eligible else { return }
                while !Task.isCancelled {
                    loaf.advance(eligible: eligible,delay: model.petIdleDelay.seconds,now: ProcessInfo.processInfo.systemUptime,
                        choose: { PetAnimation.lifeAnimations.randomElement()! },cycle: { LifeArtwork.shared.manifest?.motion(for: $0)?.cycle ?? 0 })
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
            .task(id: CompanionConfiguration(enabled: model.mode == .companion && model.petSpaceVisible && awake && !model.suspended && !reduceMotion && !model.animationPreview.enabled && !model.bubblePreviewEnabled,
                                             fixed: model.companionFixedAnimation)) {
                companion.reset()
                guard model.mode == .companion, model.petSpaceVisible, awake, !model.suspended, !reduceMotion,
                      !model.animationPreview.enabled, !model.bubblePreviewEnabled else { return }
                while !Task.isCancelled {
                    companion.advance(now: ProcessInfo.processInfo.systemUptime, fixed: model.companionFixedAnimation,
                        choose: { $0.randomElement()! }, cycle: { animation in
                            LifeArtwork.shared.manifest?.motion(for: animation)?.cycle ?? max(8, CharacterArtwork.shared.manifest?.motion(for: animation.taskState)?.duration ?? 8)
                        })
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in awake = false }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in awake = true }
            .help("点击查看任务；拖动调整位置；右键打开菜单。")
    }
}
struct BubbleView: View {
    @ObservedObject var model: Coordinator
    let notice: Notice
    var isPreview = false
    @Environment(\.colorScheme) private var colorScheme
    private var dark: Bool { colorScheme == .dark }
    private var accent: Color {
        switch notice.state {
        case .success: return dark ? Color(red: 0.42, green: 0.87, blue: 0.77) : Color(red: 0.16, green: 0.48, blue: 0.43)
        case .error: return dark ? Color(red: 1, green: 0.66, blue: 0.71) : Color(red: 0.68, green: 0.28, blue: 0.39)
        case .waiting: return dark ? Color(red: 1, green: 0.81, blue: 0.46) : Color(red: 0.61, green: 0.40, blue: 0.13)
        default: return dark ? .cyan : Color(red: 0.25, green: 0.42, blue: 0.67)
        }
    }
    private var ink: Color { dark ? Color(red: 0.90, green: 0.94, blue: 1) : Color(red: 0.18, green: 0.24, blue: 0.38) }
    var body: some View {
        let size = BubblePlacement.size
        let shape = CompanionBubbleShape(side: model.bubbleTailSide, offset: model.bubbleTailOffset)
        let body = shape.bodyRect(in: CGRect(origin: .zero, size: size))
        Button { if isPreview { if model.animationPreview.enabled { model.setAnimationPreview(false) } else { model.endBubblePreview() } } else { model.openSession(notice.sessionId) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: notice.state.previewSymbol).font(.system(size: 13, weight: .semibold))
                        .frame(width: 25, height: 25).background(accent.opacity(dark ? 0.15 : 0.09), in: Circle())
                    Text("DS 娘").font(.system(size: 12, weight: .bold, design: .rounded))
                    Text(notice.state.label).font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 3).background(accent.opacity(0.10), in: Capsule())
                    Spacer(minLength: 20)
                }.foregroundStyle(accent)
                Text(notice.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(notice.summary).font(.system(size: 12)).lineSpacing(2).lineLimit(3)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(isPreview ? "气泡样例 · 点击结束桌面测试" : "点击回到会话"); Image(systemName: "arrow.up.right")
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
            }
            .foregroundStyle(ink).padding(.horizontal, 16).padding(.vertical, 13)
            .frame(width: body.width, height: body.height, alignment: .topLeading)
            .offset(x: body.minX, y: body.minY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background {
                if model.bubbleStyle == .glass { shape.fill(.ultraThinMaterial).shadow(color: .black.opacity(0.1), radius: 4, y: 2) }
                else { shape.fill(LinearGradient(colors: dark ? [Color(red: 0.14, green: 0.19, blue: 0.30), Color(red: 0.10, green: 0.14, blue: 0.23)] : [Color(red: 1, green: 0.99, blue: 0.97), Color(red: 0.91, green: 0.95, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(dark ? 0.18 : 0.09), radius: 4, y: 2) }
                shape.stroke(dark ? Color.white.opacity(0.20) : Color(red: 0.66, green: 0.75, blue: 0.88), lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPreview ? "气泡样例：\(notice.title)" : "打开会话：\(notice.title)")
        .overlay(alignment: .topLeading) {
            Button { if isPreview { if model.animationPreview.enabled { model.setAnimationPreview(false) } else { model.endBubblePreview() } } else { model.dismissBubble(id: notice.id) } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(ink.opacity(0.55))
                    .frame(width: 28, height: 28).background(ink.opacity(0.045), in: Circle()).contentShape(Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("关闭提醒")
            .offset(x: body.maxX - 34, y: body.minY + 8)
        }
    }
}

private struct CompanionBubbleShape: Shape {
    let side: BubbleTailSide
    let offset: CGFloat
    func bodyRect(in rect: CGRect) -> CGRect {
        var body = rect.insetBy(dx: 6, dy: 6)
        switch side {
        case .left: body.origin.x += 10; body.size.width -= 10
        case .right: body.size.width -= 10
        case .top: body.origin.y += 10; body.size.height -= 10
        case .bottom: body.size.height -= 10
        }
        return body
    }
    func path(in rect: CGRect) -> Path {
        let b = bodyRect(in: rect), r: CGFloat = 22
        var path = Path()
        // A single perimeter keeps the outline seamless where the tail meets the card.
        func tail(_ begin: CGPoint, _ tip: CGPoint, _ end: CGPoint) {
            path.addLine(to: begin)
            path.addQuadCurve(to: tip, control: CGPoint(x: (begin.x + tip.x) / 2, y: (begin.y + tip.y) / 2))
            path.addQuadCurve(to: end, control: CGPoint(x: (tip.x + end.x) / 2, y: (tip.y + end.y) / 2))
        }
        path.move(to: CGPoint(x: b.minX + r, y: b.minY))
        if side == .top {
            tail(CGPoint(x: offset - 10, y: b.minY), CGPoint(x: offset + 2, y: b.minY - 10), CGPoint(x: offset + 10, y: b.minY))
        }
        path.addLine(to: CGPoint(x: b.maxX - r, y: b.minY))
        path.addQuadCurve(to: CGPoint(x: b.maxX, y: b.minY + r), control: CGPoint(x: b.maxX, y: b.minY))
        if side == .right {
            tail(CGPoint(x: b.maxX, y: offset - 10), CGPoint(x: b.maxX + 10, y: offset + 2), CGPoint(x: b.maxX, y: offset + 10))
        }
        path.addLine(to: CGPoint(x: b.maxX, y: b.maxY - r))
        path.addQuadCurve(to: CGPoint(x: b.maxX - r, y: b.maxY), control: CGPoint(x: b.maxX, y: b.maxY))
        if side == .bottom {
            tail(CGPoint(x: offset + 10, y: b.maxY), CGPoint(x: offset + 2, y: b.maxY + 10), CGPoint(x: offset - 10, y: b.maxY))
        }
        path.addLine(to: CGPoint(x: b.minX + r, y: b.maxY))
        path.addQuadCurve(to: CGPoint(x: b.minX, y: b.maxY - r), control: CGPoint(x: b.minX, y: b.maxY))
        if side == .left {
            tail(CGPoint(x: b.minX, y: offset + 10), CGPoint(x: b.minX - 10, y: offset + 2), CGPoint(x: b.minX, y: offset - 10))
        }
        path.addLine(to: CGPoint(x: b.minX, y: b.minY + r))
        path.addQuadCurve(to: CGPoint(x: b.minX + r, y: b.minY), control: CGPoint(x: b.minX, y: b.minY))
        path.closeSubpath()
        return path
    }
}

extension TaskState {
    var previewLabel: String {
        switch self { case .idle: return "待机"; case .working: return "工作"; case .waiting: return "等待"; case .success: return "完成"; case .error: return "失败" }
    }
    var previewSymbol: String {
        switch self { case .idle: return "sparkles"; case .working: return "keyboard"; case .waiting: return "ellipsis.bubble.fill"; case .success: return "checkmark.seal.fill"; case .error: return "exclamationmark.circle.fill" }
    }
}

// Native icon composition uses the selected idle artwork; character frames remain untouched.
struct CompanionAppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 112).fill(LinearGradient(colors: [Color.white, Color(red: 0.69, green: 0.84, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.48)).frame(width: 400, height: 400).offset(y: -28)
            if let image = NSImage(contentsOf: CharacterArtwork.resourceDirectory.appendingPathComponent("idle.png")) ?? CharacterArtwork.shared.image(state: .idle) {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: 630, height: 630).offset(y: 125)
            }
        }.frame(width: 512, height: 512).clipShape(RoundedRectangle(cornerRadius: 112))
            .overlay(RoundedRectangle(cornerRadius: 112).stroke(.white.opacity(0.7), lineWidth: 5).padding(3))
    }
}

struct CompanionHeadMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // A compact maid headband, rounded hair and two side locks remain legible at 18 pt.
        p.move(to: CGPoint(x: 4, y: 8))
        p.addCurve(to: CGPoint(x: 7, y: 2.5), control1: CGPoint(x: 3, y: 5), control2: CGPoint(x: 5, y: 2))
        p.addQuadCurve(to: CGPoint(x: 11, y: 1.5), control: CGPoint(x: 8, y: 0))
        p.addQuadCurve(to: CGPoint(x: 15, y: 2.5), control: CGPoint(x: 14, y: 0))
        p.addCurve(to: CGPoint(x: 18, y: 8), control1: CGPoint(x: 17, y: 2), control2: CGPoint(x: 19, y: 5))
        p.addQuadCurve(to: CGPoint(x: 21, y: 13), control: CGPoint(x: 19, y: 12))
        p.addQuadCurve(to: CGPoint(x: 17, y: 14), control: CGPoint(x: 19, y: 15))
        p.addLine(to: CGPoint(x: 18, y: 20))
        p.addQuadCurve(to: CGPoint(x: 13, y: 20), control: CGPoint(x: 15, y: 22))
        p.addLine(to: CGPoint(x: 9, y: 20))
        p.addQuadCurve(to: CGPoint(x: 4, y: 20), control: CGPoint(x: 6, y: 22))
        p.addLine(to: CGPoint(x: 5, y: 14))
        p.addQuadCurve(to: CGPoint(x: 1, y: 13), control: CGPoint(x: 2, y: 15))
        p.addQuadCurve(to: CGPoint(x: 4, y: 8), control: CGPoint(x: 3, y: 12)); p.closeSubpath()
        p.addEllipse(in: CGRect(x: 6, y: 8, width: 10, height: 10))
        p.move(to: CGPoint(x: 6, y: 5)); p.addQuadCurve(to: CGPoint(x: 16, y: 5), control: CGPoint(x: 11, y: 1.5))
        p.addLine(to: CGPoint(x: 16, y: 6.3)); p.addQuadCurve(to: CGPoint(x: 6, y: 6.3), control: CGPoint(x: 11, y: 3)); p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 22, y: rect.height / 22).translatedBy(x: rect.minX, y: rect.minY))
    }
}
struct CompanionMenuIcon: View {
    var body: some View {
        ZStack {
            CompanionHeadMark().fill(.black, style: FillStyle(eoFill: true))
            Path { p in
                p.move(to: CGPoint(x: 5.5, y: 7)); p.addLine(to: CGPoint(x: 13.5, y: 7))
                p.addQuadCurve(to: CGPoint(x: 11, y: 10.5), control: CGPoint(x: 13, y: 10))
                p.addLine(to: CGPoint(x: 9, y: 8.5)); p.addLine(to: CGPoint(x: 7.5, y: 11)); p.closeSubpath()
            }.fill(.black)
        }.frame(width: 18, height: 18)
    }
}
