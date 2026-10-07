import XCTest
@testable import CompanionCore

final class SessionStoreTests: XCTestCase {
    func feed(_ sequence: Int, events: [[String: Any]] = [], state: String = "working", waits: [[String: String]] = [], reset: Bool = false, epoch: String = "epoch") throws -> BridgeFeed {
        let record: [String: Any] = ["sessionId": "a", "title": "会话 A", "runId": "run1", "state": state, "activeWaits": waits, "updatedAt": 1000]
        return try JSONDecoder().decode(BridgeFeed.self, from: JSONSerialization.data(withJSONObject: ["protocolVersion": "1.0", "instanceId": "i", "sourceEpoch": epoch, "throughSequence": sequence, "reset": reset, "clientConnected": true, "sessions": [record], "events": events]))
    }
    func event(_ seq: Int, id: String? = nil, state: String = "success", waits: [[String: String]] = [], run: String = "run1", session: String = "a") -> [String: Any] {
        ["protocolVersion": "1.0", "eventId": id ?? "event\(seq)", "source": "deepseek-harness", "instanceId": "i", "sourceEpoch": "epoch", "sequence": seq, "sessionId": session, "title": "会话 A", "runId": run, "state": state, "activeWaits": waits, "updatedAt": 1000, "type": state == "waiting" ? "session.waiting" : "task.succeeded", "occurredAt": "2026-10-03T00:00:00Z", "summary": "需要关注", "notify": true]
    }
    func testBaselineDoesNotReplayHistoricalSuccess() throws {
        var store = SessionStore(); let created = try store.apply(feed(20, state: "success", reset: true))
        XCTAssertTrue(created.isEmpty); XCTAssertEqual(store.unreadCount, 0)
    }
    func testDuplicateAndSemanticTerminalDeduplication() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        _ = try store.apply(feed(1, events: [event(1)])); _ = try store.apply(feed(1, events: [event(1)]))
        _ = try store.apply(feed(2, events: [event(2)])); XCTAssertEqual(store.notices.count, 1)
    }
    func testReadDoesNotResolveWaitingAndNewNoticeSurvivesClickBoundary() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        let wait = [["actionId": "q1", "reason": "question"]]
        _ = try store.apply(feed(1, events: [event(1, state: "waiting", waits: wait)], state: "waiting", waits: wait))
        let boundary = store.unreadIDs(sessionId: "a")
        _ = try store.apply(feed(2, events: [event(2, run: "run2")], state: "waiting", waits: wait))
        store.markRead(sessionId: "a", ids: boundary)
        XCTAssertEqual(store.unreadCount, 1); XCTAssertEqual(store.sessions["a"]?.state, .waiting)
        XCTAssertFalse(store.notices[0].resolved)
    }
    func testWaitingResolutionUpdatesStaleReminder() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        let wait = [["actionId": "q", "reason": "approval"]]
        _ = try store.apply(feed(1, events: [event(1, state: "waiting", waits: wait)], state: "waiting", waits: wait))
        _ = try store.apply(feed(1)); XCTAssertTrue(store.notices[0].resolved); XCTAssertEqual(store.unreadCount, 1)
    }
    func testGapRejectsWholeBatchWithoutPartialMutation() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        XCTAssertThrowsError(try store.apply(feed(3, events: [event(1), event(3)])))
        XCTAssertEqual(store.sequence, 0); XCTAssertTrue(store.notices.isEmpty)
    }
    func testOldPacketCannotOverwriteNewerState() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        _ = try store.apply(feed(1, events: [event(1)], state: "success"))
        XCTAssertThrowsError(try store.apply(feed(0, state: "waiting", waits: [["actionId": "q", "reason": "question"]])))
        XCTAssertEqual(store.sessions["a"]?.state, .success)
    }
    func testReconnectKeepsUnreadAndNewEpochRequiresBaseline() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true)); _ = try store.apply(feed(1, events: [event(1)]))
        XCTAssertThrowsError(try store.apply(feed(0, epoch: "new")))
        _ = try store.apply(feed(0, reset: true, epoch: "new")); XCTAssertEqual(store.unreadCount, 1)
    }
    func testSeveralNoticesInOneSessionCountAsOneUnread() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        _ = try store.apply(feed(2, events: [event(1), event(2, run: "next")]))
        XCTAssertEqual(store.notices.count, 2); XCTAssertEqual(store.unreadCount, 1)
    }
    func testMalformedWaitingIsRejected() throws {
        var store = SessionStore(); XCTAssertThrowsError(try store.apply(feed(0, state: "waiting", reset: true)))
        XCTAssertEqual(store.sequence, -1)
    }
    func testUnknownWaitReasonAndEventTypeAreRejectedWithoutAdvancing() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        let waits = [["actionId": "q", "reason": "invented"]]
        XCTAssertThrowsError(try store.apply(feed(1, events: [event(1, state: "waiting", waits: waits)], state: "waiting", waits: waits)))
        var unknown = event(1); unknown["type"] = "unknown-event"
        XCTAssertThrowsError(try store.apply(feed(1, events: [unknown])))
        XCTAssertEqual(store.sequence, 0); XCTAssertTrue(store.notices.isEmpty)
    }
    func testPortraitDoesNotShowHistoricalCompletionAsActiveWork() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, state: "success", reset: true))
        XCTAssertNil(store.portrait(connected: true, now: 11000)); XCTAssertNil(store.portrait(connected: false, now: 1001))
    }
    func testPersistenceRoundTripKeepsReadSeparatelyFromWait() throws {
        var store = SessionStore(); let waits = [["actionId": "q", "reason": "question"]]
        _ = try store.apply(feed(0, reset: true)); _ = try store.apply(feed(1, events: [event(1, state: "waiting", waits: waits)], state: "waiting", waits: waits))
        store.markRead(sessionId: "a", ids: store.unreadIDs(sessionId: "a"))
        let restored = try JSONDecoder().decode(SessionStore.self, from: JSONEncoder().encode(store))
        XCTAssertEqual(restored.unreadCount, 0); XCTAssertEqual(restored.sessions["a"]?.state, .waiting)
    }
    func testUnloadedSessionKeepsUnreadRowWithoutPretendingItIsLive() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true)); _ = try store.apply(feed(1, events: [event(1)], state: "success"))
        var empty = try feed(1); empty.sessions = []
        _ = try store.apply(empty)
        XCTAssertEqual(store.unreadCount, 1); XCTAssertEqual(store.sessions["a"]?.available, false)
        XCTAssertNil(store.portrait(connected: true, now: 1001))
        store.markRead(sessionId: "a", ids: store.unreadIDs(sessionId: "a")); XCTAssertEqual(store.unreadCount, 0)
    }
    func testConfiguredFeedbackExpiresAtFiveOrTenSeconds() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        _ = try store.apply(feed(1, events: [event(1)], state: "success"))
        XCTAssertEqual(store.portrait(connected: true, now: 5999, retention: .fiveSeconds)?.state, .success)
        XCTAssertNil(store.portrait(connected: true, now: 6000, retention: .fiveSeconds))
        XCTAssertEqual(store.portrait(connected: true, now: 10999)?.state, .success)
        XCTAssertNil(store.portrait(connected: true, now: 11000))
        XCTAssertEqual(store.unreadCount, 1)
    }
    func testPermanentFeedbackEndsOnReadButPreservesNewClickBoundary() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        _ = try store.apply(feed(1, events: [event(1)], state: "success"))
        let boundary = store.unreadIDs(sessionId: "a")
        XCTAssertEqual(store.portrait(connected: true, now: 1_000_000, retention: .untilOpened)?.state, .success)
        var next = try feed(2, events: [event(2, run: "run2")], state: "success")
        next.sessions[0].runId = "run2"
        _ = try store.apply(next); store.markRead(sessionId: "a", ids: boundary)
        XCTAssertEqual(store.portrait(connected: true, now: 1_000_000, retention: .untilOpened)?.state, .success)
        store.markRead(sessionId: "a", ids: store.unreadIDs(sessionId: "a"))
        XCTAssertNil(store.portrait(connected: true, now: 1_000_000, retention: .untilOpened))
    }
    func testDismissedFeedbackKeepsUnreadAndBaselineDoesNotBecomePermanent() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, state: "success", reset: true))
        XCTAssertNil(store.portrait(connected: true, now: 1001, retention: .untilOpened))
        _ = try store.apply(feed(1, events: [event(1)], state: "success"))
        XCTAssertNil(store.portrait(connected: true, now: 1001, retention: .untilOpened, dismissedFeedbackIDs: ["event1"]))
        XCTAssertEqual(store.unreadCount, 1)
    }
    func testWaitingAlwaysOutranksPermanentCompletionAndReadDoesNotResolveIt() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        var completion = try feed(1, events: [event(1)], state: "success")
        _ = try store.apply(completion)
        let waits = [["actionId": "q", "reason": "approval"]]
        completion = try feed(2, events: [event(2, state: "waiting", waits: waits, session: "b")], state: "success")
        completion.sessions.append(SessionRecord(sessionId: "b", title: "B", runId: "run1", state: .waiting,
            activeWaits: [WaitItem(actionId: "q", reason: "approval")], updatedAt: 1000))
        _ = try store.apply(completion); store.markRead(sessionId: "b", ids: store.unreadIDs(sessionId: "b"))
        XCTAssertEqual(store.portrait(connected: true, now: 1_000_000, retention: .untilOpened)?.id, "b")
        XCTAssertFalse(store.notices.last!.resolved)
    }
}

final class ReminderRetentionTests: XCTestCase {
    private func notice(_ id: String, session: String = "a", state: TaskState = .success) -> Notice {
        Notice(id: id, sessionId: session, instanceId: "i", runId: id, title: id, summary: id,
               state: state, actionIds: [], createdAt: 0, read: false, resolved: false)
    }
    func testPreferenceDefaultAndSavedChoices() throws {
        XCTAssertEqual(ReminderRetention.saved(nil), .tenSeconds)
        XCTAssertEqual(ReminderRetention.saved("invalid"), .tenSeconds)
        for choice in ReminderRetention.allCases {
            XCTAssertEqual(ReminderRetention.saved(choice.rawValue), choice)
            XCTAssertEqual(try JSONDecoder().decode(ReminderRetention.self, from: JSONEncoder().encode(choice)), choice)
        }
    }
    func testBubbleDeadlineDoesNotRestartOnPollingAndStaleExpiryCannotCloseNext() {
        var queue = PetReminderQueue()
        queue.enqueue(notice("a"), retention: .tenSeconds, now: 1000)
        queue.enqueue(notice("b", session: "b"), retention: .tenSeconds, now: 4000)
        XCTAssertEqual(queue.remaining(retention: .tenSeconds, now: 6000), 5)
        queue.expire(id: "a", retention: .tenSeconds, now: 10999)
        XCTAssertEqual(queue.current?.id, "a")
        queue.expire(id: "a", retention: .tenSeconds, now: 11000)
        XCTAssertEqual(queue.current?.id, "b")
        queue.expire(id: "a", retention: .tenSeconds, now: 21000)
        XCTAssertEqual(queue.current?.id, "b")
    }
    func testPermanentBubbleSurvivesTimeAndNewWaitingIsVisible() {
        var queue = PetReminderQueue()
        queue.enqueue(notice("a"), retention: .untilOpened, now: 0)
        queue.expire(id: "a", retention: .untilOpened, now: 1_000_000)
        XCTAssertEqual(queue.current?.id, "a")
        queue.enqueue(notice("b", session: "b", state: .waiting), retention: .untilOpened, now: 1_000_000)
        XCTAssertEqual(queue.current?.id, "b")
        queue.enqueue(notice("c", session: "c"), retention: .untilOpened, now: 1_000_001)
        XCTAssertEqual(queue.current?.id, "b")
        queue.remove(ids: ["b"], now: 1_000_002)
        XCTAssertEqual(queue.current?.id, "c")
    }
    func testCapturedClickRemovalDoesNotClearNewReminderInSameSession() {
        var queue = PetReminderQueue()
        queue.enqueue(notice("old"), retention: .untilOpened, now: 0)
        queue.enqueue(notice("new"), retention: .untilOpened, now: 1000)
        queue.remove(ids: ["old"], now: 2000)
        XCTAssertEqual(queue.current?.id, "new")
        queue.remove(ids: ["new"], now: 3000)
        XCTAssertNil(queue.current)
    }
    func testRetentionChangeStartsNewTimerAndClearPreventsReplay() {
        var queue = PetReminderQueue()
        queue.enqueue(notice("a"), retention: .untilOpened, now: 0)
        queue.restartTimer(now: 9000)
        XCTAssertEqual(queue.remaining(retention: .fiveSeconds, now: 10000), 4)
        queue.clear(); queue.advance(now: 20000)
        XCTAssertNil(queue.current); XCTAssertTrue(queue.queued.isEmpty)
    }
}
final class CharacterAnimationTests: XCTestCase {
    func testPauseFreezesPhaseAndResumeExcludesPausedTime() {
        var clock = CharacterPlaybackClock()
        clock.configure(state: .success, playing: true, now: 100)
        clock.configure(state: .success, playing: false, now: 100.65)
        XCTAssertEqual(clock.elapsedTime(at: 1000), 0.65, accuracy: 0.00001)
        clock.configure(state: .success, playing: true, now: 1000)
        XCTAssertEqual(clock.elapsedTime(at: 1000.1), 0.75, accuracy: 0.00001)
        clock.configure(state: .error, playing: false, now: 1001)
        XCTAssertEqual(clock.elapsedTime(at: 2000), 0)
    }
    func testManualPreviewDoesNotExpireOrReplaceLiveState() {
        var preview = AnimationPreview()
        XCTAssertFalse(preview.enabled)
        preview.begin(state: .idle)
        for state in TaskState.allCases {
            preview.select(state)
            XCTAssertEqual(preview.displayedState(live: .working), state)
        }
        preview.setPlaying(false)
        XCTAssertFalse(preview.playing)
        XCTAssertEqual(preview.displayedState(live: .waiting), .error)
        preview.end()
        XCTAssertEqual(preview.displayedState(live: .waiting), .waiting)
        preview.begin(state: .success)
        XCTAssertTrue(preview.playing)
        XCTAssertFalse(AnimationPreview().enabled)
    }
    func testBubblePlacementAtCornersAndOffsetDisplays() {
        for screen in [CGRect(x: 0, y: 25, width: 1440, height: 850), CGRect(x: -1440, y: -800, width: 1440, height: 850)] {
            for x in [screen.minX, screen.maxX - 208] {
                for y in [screen.minY, screen.maxY - 240] {
                    let pet = CGRect(x: x, y: y, width: 208, height: 240)
                    let placement = BubblePlacement.beside(pet: pet, screen: screen)
                    XCTAssertTrue(screen.contains(placement.frame))
                    XCTAssertEqual(placement.tailSide, x == screen.minX ? .left : .right)
                    XCTAssertGreaterThanOrEqual(placement.tailOffset, 38)
                    XCTAssertLessThanOrEqual(placement.tailOffset, BubblePlacement.size.height - 38)
                }
            }
        }
    }
    func testBubbleMovesAboveOrBelowPetInNarrowSpace() {
        let screen = CGRect(x: 0, y: 0, width: 640, height: 900)
        let low = BubblePlacement.beside(pet: CGRect(x: 216, y: 0, width: 208, height: 240), screen: screen)
        XCTAssertEqual(low.tailSide, .bottom)
        XCTAssertEqual(low.frame.minY, 248)
        let high = BubblePlacement.beside(pet: CGRect(x: 216, y: 660, width: 208, height: 240), screen: screen)
        XCTAssertEqual(high.tailSide, .top)
        XCTAssertEqual(high.frame.maxY, 652)
        XCTAssertTrue(screen.contains(low.frame)); XCTAssertTrue(screen.contains(high.frame))
    }
    private func selectedManifest() throws -> CharacterManifest {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/characters/character.json")
        return try JSONDecoder().decode(CharacterManifest.self, from: Data(contentsOf: url))
    }
    func testSelectedCharacterContainsAllFiveUsableMotions() throws {
        let manifest = try selectedManifest()
        try manifest.validate()
        let selectionURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("playground/pet-design/production.json")
        let selection = try JSONSerialization.jsonObject(with: Data(contentsOf: selectionURL)) as? [String: Any]
        XCTAssertEqual(manifest.id, selection?["selected"] as? String)
        XCTAssertEqual(manifest.states.reduce(0) { $0 + $1.frames.count }, 20)
        XCTAssertEqual(Set(manifest.states.map(\.state)), Set(TaskState.allCases))
        XCTAssertEqual(manifest.canvasSize, 208)
    }
    func testBlinkScheduleHoldsOpenEyesAndWraps() throws {
        let motion = try XCTUnwrap(selectedManifest().motion(for: .idle))
        XCTAssertEqual(motion.frameIndex(at: 2.79), 0)
        XCTAssertEqual(motion.frameIndex(at: 2.8), 1)
        XCTAssertEqual(motion.frameIndex(at: 2.95), 2)
        XCTAssertEqual(motion.frameIndex(at: 3.01), 3)
        XCTAssertEqual(motion.frameIndex(at: motion.duration), 0)
        XCTAssertEqual(motion.frameIndex(at: motion.duration * 20 + 2.95), 2)
    }
    func testDelayedPlaybackCatchesUpInsteadOfReplayingOldFrames() throws {
        let motion = try XCTUnwrap(selectedManifest().motion(for: .working))
        XCTAssertEqual(motion.frameIndex(at: 0.65), 3)
        XCTAssertEqual(motion.secondsUntilNextFrame(at: 0.65), 0.15, accuracy: 0.00001)
        XCTAssertEqual(motion.frameIndex(at: -.infinity), 0)
        XCTAssertEqual(motion.frameIndex(at: .nan), 0)
    }
    func testMalformedAtlasAndMissingStatesAreRejected() throws {
        var manifest = try selectedManifest()
        manifest.states[0].frames[0].x = manifest.atlasWidth
        XCTAssertThrowsError(try manifest.validate())
        manifest = try selectedManifest()
        manifest.states[1].state = .idle
        XCTAssertThrowsError(try manifest.validate())
        manifest = try selectedManifest()
        manifest.states[0].durations[0] = 0
        XCTAssertThrowsError(try manifest.validate())
    }
}

extension SessionStoreTests {
    func testViewedCandidateRequiresFreshExactForegroundConversation() {
        let view = ViewStatus(sessionId: "a", visible: true, focused: true, loaded: true, reportedAt: 1000)
        XCTAssertTrue(view.eligible(sessionId: "a", foreground: true, now: 2000))
        XCTAssertFalse(view.eligible(sessionId: "b", foreground: true, now: 2000))
        XCTAssertFalse(view.eligible(sessionId: "a", foreground: false, now: 2000))
        XCTAssertFalse(view.eligible(sessionId: "a", foreground: true, now: 4000))
        var loading = view; loading.loaded = false
        XCTAssertFalse(loading.eligible(sessionId: "a", foreground: true, now: 2000))
    }
    func testReceiptRejectsBlurEpochAndNewBoundary() {
        let receipt = ViewReceipt(requestId: "r", status: "viewed", sessionId: "a", instanceId: "i", sourceEpoch: "e", throughSequence: 2)
        XCTAssertTrue(receipt.confirms(requestId: "r", sessionId: "a", instanceId: "i", sourceEpoch: "e", throughSequence: 2, foregroundUnchanged: true))
        XCTAssertFalse(receipt.confirms(requestId: "r", sessionId: "a", instanceId: "i", sourceEpoch: "e", throughSequence: 3, foregroundUnchanged: true))
        XCTAssertFalse(receipt.confirms(requestId: "r", sessionId: "a", instanceId: "i", sourceEpoch: "new", throughSequence: 2, foregroundUnchanged: true))
        XCTAssertFalse(receipt.confirms(requestId: "r", sessionId: "a", instanceId: "i", sourceEpoch: "e", throughSequence: 2, foregroundUnchanged: false))
    }
    func testBubbleSamplesDoNotChangeLiveUnreadOrWaiting() throws {
        var store = SessionStore(); _ = try store.apply(feed(0, reset: true))
        let waits = [["actionId": "q", "reason": "question"]]
        _ = try store.apply(feed(1, events: [event(1, state: "waiting", waits: waits)], state: "waiting", waits: waits))
        let ids = store.unreadIDs(sessionId: "a")
        for kind in BubblePreviewKind.allCases {
            XCTAssertTrue(kind.notice.read); XCTAssertEqual(kind.notice.instanceId, "preview")
            store.markRead(sessionId: kind.notice.sessionId, ids: [kind.notice.id])
        }
        XCTAssertEqual(store.unreadIDs(sessionId: "a"), ids)
        XCTAssertEqual(store.unreadCount, 1); XCTAssertEqual(store.sessions["a"]?.state, .waiting)
    }
    func testLegacyBridgeWithoutViewingRemainsCompatible() throws {
        XCTAssertNil(try feed(0, reset: true).viewStatus)
        XCTAssertEqual(BubbleStyle.saved("unsupported"), .chibi)
        XCTAssertEqual(BubbleStyle.saved("glass"), .glass)
    }
}

final class PetLifeAnimationTests: XCTestCase {
    private func manifest() throws -> LifeManifest {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/characters")
        return try JSONDecoder().decode(LifeManifest.self,from: Data(contentsOf: directory.appendingPathComponent("life.json")))
    }
    func testApprovedTimingsSourceOrderAndRecoveredRegistration() throws {
        let data = try manifest(); try data.validate()
        let rice = try XCTUnwrap(data.motion(for: .rice)),toy = try XCTUnwrap(data.motion(for: .toy))
        XCTAssertEqual(rice.duration,5.04,accuracy: 0.000001); XCTAssertEqual(rice.cycle,8,accuracy: 0.000001)
        XCTAssertEqual(rice.durations[15],0.18); XCTAssertEqual(rice.durations[17],0.18)
        XCTAssertEqual(toy.duration,4.13,accuracy: 0.000001); XCTAssertEqual(toy.cycle,6.13,accuracy: 0.000001)
        XCTAssertEqual(toy.frames.map(\.sourcePose),Array(1...24).filter {$0 != 14})
        let f16 = try XCTUnwrap(toy.frames.first {$0.sourcePose == 16}),f17 = try XCTUnwrap(toy.frames.first {$0.sourcePose == 17})
        XCTAssertEqual(f16.file,"life-toy-16.png"); XCTAssertEqual(f16.anchorX,126); XCTAssertEqual(f16.footY,227)
        XCTAssertEqual(f17.file,"life-toy-17.png"); XCTAssertEqual(f17.anchorX,163); XCTAssertEqual(f17.footY,228)
        for motion in data.clips {
            var elapsed = 0.0
            for (index,hold) in motion.durations.enumerated() {
                XCTAssertEqual(motion.frameIndex(at: elapsed+hold/2),index)
                XCTAssertEqual(motion.secondsUntilNextFrame(at: elapsed+hold/2),hold/2,accuracy: 0.000001)
                elapsed += hold
            }
            XCTAssertEqual(motion.frameIndex(at: motion.duration+motion.rest/2),motion.frames.count-1)
            XCTAssertEqual(motion.frameIndex(at: motion.cycle),0)
            XCTAssertEqual(motion.frameIndex(at: motion.cycle,looping: false),motion.frames.count-1)
            XCTAssertEqual(motion.frameIndex(at: 999,looping: false),motion.frames.count-1)
        }
    }
    func testApprovedHeadPatAndWhalePatTimingsAndRecoveredAssets() throws {
        let data = try manifest(); try data.validate()
        let pet = try XCTUnwrap(data.motion(for: .pet)), whale = try XCTUnwrap(data.motion(for: .whale))
        XCTAssertEqual(PetAnimation.allCases.count,9)
        XCTAssertEqual(Set(PetAnimation.lifeAnimations),Set([.rice,.toy,.pet,.whale]))
        XCTAssertEqual(pet.durations,[0.12,0.16,0.32,0.25,0.38,0.22,0.3,0.45])
        XCTAssertEqual(pet.duration,2.2,accuracy: 0.000001); XCTAssertEqual(pet.rest,2)
        XCTAssertEqual(whale.duration,5.4,accuracy: 0.000001); XCTAssertEqual(whale.rest,2)
        XCTAssertEqual(pet.frames.map(\.sourcePose),Array(1...8))
        XCTAssertEqual(whale.frames.map(\.sourcePose),Array(1...24))
        for motion in [pet,whale] {
            for (i,f) in motion.frames.enumerated() {
                XCTAssertEqual(f.file,String(format: "life-%@-%02d.png",motion.animation.rawValue,i+1))
                XCTAssertEqual(f.x,0); XCTAssertEqual(f.y,0)
            }
        }
    }
    func testManifestRejectsMissingNewMotionAndInvalidHeadPatPose() throws {
        var data = try manifest()
        data.clips.removeAll { $0.animation == .whale }
        XCTAssertThrowsError(try data.validate())
        data = try manifest()
        let index = try XCTUnwrap(data.clips.firstIndex { $0.animation == .pet })
        data.clips[index].frames[0].sourcePose = 9
        XCTAssertThrowsError(try data.validate())
    }
    func testIdleWaitPlaysOneRoundThenWaitsAgainForBothSettings() throws {
        let data = try manifest()
        for delay in PetIdleDelay.allCases {
            for animation in PetAnimation.lifeAnimations {
                var player = PetLoafPlayback()
                let duration = try XCTUnwrap(data.motion(for: animation)).cycle
                func advance(_ now: Double,_ eligible: Bool = true) {
                    player.advance(eligible: eligible,delay: delay.seconds,now: now,choose: {animation},cycle: {_ in duration})
                }
                advance(100); advance(100+delay.seconds-0.01); XCTAssertNil(player.animation)
                advance(100+delay.seconds); XCTAssertEqual(player.animation,animation)
                advance(100+delay.seconds+duration-0.01); XCTAssertEqual(player.animation,animation)
                let end = 100+delay.seconds+duration
                advance(end); XCTAssertNil(player.animation)
                advance(end+delay.seconds-0.01); XCTAssertNil(player.animation)
                advance(end+delay.seconds); XCTAssertEqual(player.animation,animation)
                advance(end+delay.seconds+0.1,false); XCTAssertNil(player.animation)
                advance(end+50); XCTAssertNil(player.animation)
                advance(end+50+delay.seconds); XCTAssertEqual(player.animation,animation)
            }
        }
    }
    func testNonIdlePresentationInterruptsAndResetsWait() {
        var player = PetLoafPlayback()
        player.advance(eligible: true,delay: 5,now: 0,choose: {.rice},cycle: {_ in 8})
        player.advance(eligible: true,delay: 5,now: 5,choose: {.rice},cycle: {_ in 8})
        XCTAssertEqual(player.animation,.rice)
        player.advance(eligible: false,delay: 5,now: 6,choose: {.toy},cycle: {_ in 6.13})
        XCTAssertNil(player.animation)
        player.advance(eligible: true,delay: 5,now: 100,choose: {.toy},cycle: {_ in 6.13})
        player.advance(eligible: true,delay: 5,now: 104.99,choose: {.toy},cycle: {_ in 6.13})
        XCTAssertNil(player.animation)
        player.advance(eligible: true,delay: 5,now: 105,choose: {.toy},cycle: {_ in 6.13})
        XCTAssertEqual(player.animation,.toy)
        XCTAssertEqual(PetIdleDelay.saved(nil),.tenSeconds)
        XCTAssertEqual(PetIdleDelay.saved("invalid"),.tenSeconds)
        XCTAssertEqual(PetIdleDelay.saved("fiveSeconds"),.fiveSeconds)
    }
    func testLifePreviewPauseResumeRestartAndLiveTaskRecovery() {
        var preview = AnimationPreview(),clock = CharacterPlaybackClock()
        preview.begin(state: .working); preview.select(PetAnimation.rice)
        clock.configure(animation: preview.selectedAnimation,playing: true,now: 10,revision: preview.revision)
        preview.setPlaying(false)
        clock.configure(animation: .rice,playing: false,now: 10.4,revision: preview.revision)
        XCTAssertEqual(clock.elapsedTime(at: 100),0.4,accuracy: 0.000001)
        preview.setPlaying(true)
        clock.configure(animation: .rice,playing: true,now: 100,revision: preview.revision)
        XCTAssertEqual(clock.elapsedTime(at: 100.1),0.5,accuracy: 0.000001)
        preview.restart()
        clock.configure(animation: .rice,playing: true,now: 101,revision: preview.revision)
        XCTAssertEqual(clock.elapsedTime(at: 101),0)
        preview.select(PetAnimation.toy)
        clock.configure(animation: .toy,playing: false,now: 102,revision: preview.revision)
        XCTAssertEqual(clock.elapsedTime(at: 200),0)
        preview.end(); XCTAssertEqual(preview.displayedState(live: .waiting),.waiting)
        XCTAssertFalse(AnimationPreview().enabled)
    }
}
