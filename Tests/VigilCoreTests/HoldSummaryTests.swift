import Foundation
import Testing
@testable import VigilCore

struct HoldSummaryTests {
    private let now = TestClock.date(h: 10)

    private func decision(
        hold: Bool = true,
        reasons: [HoldReason],
        blocked: Bool = false,
        effects: [Effect] = []
    ) -> Decision {
        Decision(hold: hold, holdDisplay: false, reasons: reasons, blockedByGuard: blocked, effects: effects)
    }

    // MARK: assertion name (what `pmset -g assertions` shows)

    @Test func assertionNameWithoutReasonsIsJustTheAppName() {
        #expect(HoldSummary.assertionName(for: []) == "Vigil")
    }

    @Test func assertionNameDescribesEachReason() {
        #expect(HoldSummary.assertionName(for: [.manual(until: nil)]) == "Vigil: manual hold")
        #expect(HoldSummary.assertionName(for: [.manual(until: now)]) == "Vigil: manual hold")
        #expect(HoldSummary.assertionName(for: [.process("Xcode")]) == "Vigil: Xcode is running")
        #expect(HoldSummary.assertionName(for: [.schedule]) == "Vigil: schedule")
    }

    @Test func assertionNameJoinsMultipleReasonsInOrder() {
        let reasons: [HoldReason] = [.manual(until: nil), .process("Xcode"), .schedule]
        #expect(HoldSummary.assertionName(for: reasons) == "Vigil: manual hold + Xcode is running + schedule")
    }

    // MARK: status line

    @Test func statusWhenNothingIsHeld() {
        let d = decision(hold: false, reasons: [])
        #expect(HoldSummary.statusLine(decision: d, now: now, threshold: 20) == "Not holding")
    }

    @Test func statusWhenTheBatteryGuardBlocksARule() {
        let d = decision(hold: false, reasons: [.process("Xcode")], blocked: true)
        #expect(HoldSummary.statusLine(decision: d, now: now, threshold: 20) == "Paused: battery below 20%")
    }

    @Test func statusForAnIndefiniteManualHold() {
        let d = decision(reasons: [.manual(until: nil)])
        #expect(HoldSummary.statusLine(decision: d, now: now, threshold: 20) == "Holding awake until you stop it")
    }

    @Test func statusForATimedManualHoldShowsTimeLeft() {
        let d = decision(reasons: [.manual(until: now.addingTimeInterval(4_320))])
        #expect(HoldSummary.statusLine(decision: d, now: now, threshold: 20) == "Holding awake · 1h 12m left")
    }

    @Test func statusForAProcessRule() {
        let d = decision(reasons: [.process("Xcode")])
        #expect(HoldSummary.statusLine(decision: d, now: now, threshold: 20) == "Holding awake while Xcode is running")
    }

    @Test func statusForAScheduleRule() {
        let d = decision(reasons: [.schedule])
        #expect(HoldSummary.statusLine(decision: d, now: now, threshold: 20) == "Holding awake on schedule")
    }

    @Test func aManualHoldTakesPrecedenceInTheStatusLine() {
        let d = decision(reasons: [.manual(until: nil), .process("Xcode")])
        #expect(HoldSummary.statusLine(decision: d, now: now, threshold: 20) == "Holding awake until you stop it")
    }

    // MARK: menu-bar text

    @Test func menuBarShowsNothingUnlessATimedHoldIsRunning() {
        #expect(HoldSummary.menuBarText(decision: decision(hold: false, reasons: []), now: now) == nil)
        #expect(HoldSummary.menuBarText(decision: decision(reasons: [.manual(until: nil)]), now: now) == nil)
        #expect(HoldSummary.menuBarText(decision: decision(reasons: [.process("Xcode")]), now: now) == nil)
    }

    @Test func menuBarShowsCompactTimeLeft() {
        func text(_ seconds: TimeInterval) -> String? {
            HoldSummary.menuBarText(decision: decision(reasons: [.manual(until: now.addingTimeInterval(seconds))]), now: now)
        }
        #expect(text(4_320) == "1:12")     // 1h 12m
        #expect(text(7_200) == "2:00")
        #expect(text(2_700) == "45m")
        #expect(text(60) == "1m")
        #expect(text(20) == "<1m")
    }

    // MARK: display note (the screen turning off is not the Mac sleeping)

    @Test func noDisplayNoteWhenNothingIsHeld() {
        #expect(HoldSummary.displayNote(decision: decision(hold: false, reasons: [])) == nil)
    }

    @Test func noDisplayNoteWhenTheDisplayIsHeldToo() {
        let d = Decision(hold: true, holdDisplay: true, reasons: [.manual(until: nil)], blockedByGuard: false, effects: [])
        #expect(HoldSummary.displayNote(decision: d) == nil)
    }

    @Test func explainsThatTheScreenCanTurnOffWhileTheMacStaysAwake() {
        let note = HoldSummary.displayNote(decision: decision(reasons: [.process("Xcode")]))
        #expect(note == HoldSummary.screenMayTurnOff)
        #expect(note?.contains("screen") == true)
        #expect(note?.contains("stays awake") == true)
    }

    // MARK: notifications

    @Test func guardNoticeMentionsThePercentageAndTheThreshold() {
        let n = Notices.notice(for: .guardReleased(percent: 19), threshold: 20)
        #expect(n.title == "Battery at 19%: sleep allowed again")
        #expect(n.body.contains("20%"))
    }

    @Test func guardNoticeWithoutAReadingStillMakesSense() {
        let n = Notices.notice(for: .guardReleased(percent: nil), threshold: 20)
        #expect(n.title == "Battery low: sleep allowed again")
    }

    @Test func sessionEndedNotice() {
        let n = Notices.notice(for: .sessionEnded, threshold: 20)
        #expect(n.title == "Keep-awake finished")
        #expect(!n.body.isEmpty)
    }
}
