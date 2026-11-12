import Testing
@testable import VigilCore

struct HolderTests {
    // MARK: which assertions matter

    @Test(arguments: ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"])
    func systemSleepAssertionsAreRecognised(type: String) {
        #expect(HolderAssessment.kind(forAssertionType: type) == .system)
    }

    @Test(arguments: ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"])
    func displaySleepAssertionsAreRecognised(type: String) {
        #expect(HolderAssessment.kind(forAssertionType: type) == .display)
    }

    @Test(arguments: ["BackgroundTask", "NetworkClientActive", "UserIsActive", "ExternalMedia", ""])
    func otherAssertionsAreNotSleepHolders(type: String) {
        #expect(HolderAssessment.kind(forAssertionType: type) == nil)
    }

    // MARK: how worrying is a hold

    @Test func holdsUnderAnHourAreNormal() {
        #expect(HolderAssessment.severity(heldSeconds: 0) == .normal)
        #expect(HolderAssessment.severity(heldSeconds: 3_599) == .normal)
    }

    @Test func holdsOfAnHourOrMoreAreLong() {
        #expect(HolderAssessment.severity(heldSeconds: 3_600) == .long)
        #expect(HolderAssessment.severity(heldSeconds: 43_199) == .long)
    }

    @Test func holdsOfTwelveHoursOrMoreAreStale() {
        #expect(HolderAssessment.severity(heldSeconds: 43_200) == .stale)
        #expect(HolderAssessment.severity(heldSeconds: 293_346) == .stale)   // the 3-day caffeinate
    }

    @Test func aNegativeAgeIsNormal() {
        #expect(HolderAssessment.severity(heldSeconds: -10) == .normal)
    }

    // MARK: what the user may stop

    @Test func onlyYourOwnCaffeinateCanBeStopped() {
        #expect(HolderAssessment.isStoppable(executablePath: "/usr/bin/caffeinate", ownerUID: 501, currentUID: 501))
    }

    @Test func otherUsersCaffeinateIsNotStoppable() {
        #expect(!HolderAssessment.isStoppable(executablePath: "/usr/bin/caffeinate", ownerUID: 0, currentUID: 501))
    }

    @Test func nothingElseIsStoppable() {
        #expect(!HolderAssessment.isStoppable(executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", ownerUID: 501, currentUID: 501))
        #expect(!HolderAssessment.isStoppable(executablePath: "/usr/libexec/powerd", ownerUID: 501, currentUID: 501))
        #expect(!HolderAssessment.isStoppable(executablePath: "/usr/bin/caffeinate-evil", ownerUID: 501, currentUID: 501))
        #expect(!HolderAssessment.isStoppable(executablePath: "/tmp/usr/bin/caffeinate", ownerUID: 501, currentUID: 501))
        #expect(!HolderAssessment.isStoppable(executablePath: nil, ownerUID: 501, currentUID: 501))
        #expect(!HolderAssessment.isStoppable(executablePath: "/usr/bin/caffeinate", ownerUID: nil, currentUID: 501))
    }

    // MARK: ordering

    @Test func longestHeldComesFirst() {
        let a = SleepHolder(pid: 1, processName: "a", executablePath: nil, kind: .system, reason: "", heldSeconds: 10, ownerUID: nil)
        let b = SleepHolder(pid: 2, processName: "b", executablePath: nil, kind: .system, reason: "", heldSeconds: 5_000, ownerUID: nil)
        let c = SleepHolder(pid: 3, processName: "c", executablePath: nil, kind: .display, reason: "", heldSeconds: 300, ownerUID: nil)
        #expect(HolderAssessment.sorted([a, b, c]).map(\.pid) == [2, 3, 1])
    }
}
