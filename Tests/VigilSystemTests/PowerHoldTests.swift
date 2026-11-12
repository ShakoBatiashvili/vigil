import Foundation
import Testing
import VigilCore
@testable import VigilSystem

/// These talk to the real power-management daemon: no mocks. Each test holds an
/// assertion for a fraction of a second and releases it.
@Suite(.serialized)
struct PowerHoldTests {
    private let me = ProcessInfo.processInfo.processIdentifier

    private func mine(_ kind: HolderKind) -> [SleepHolder] {
        HolderReader.read().filter { $0.pid == me && $0.kind == kind }
    }

    @Test func holdingSystemSleepShowsUpInTheOSAssertionList() {
        let hold = PowerHold()
        hold.apply(system: true, display: false, reason: "Vigil test: system")
        defer { hold.releaseAll() }

        let found = mine(.system)
        #expect(found.contains { $0.reason == "Vigil test: system" })
        #expect(mine(.display).isEmpty)
    }

    @Test func holdingTheDisplayShowsUpAsADisplayHolder() {
        let hold = PowerHold()
        hold.apply(system: false, display: true, reason: "Vigil test: display")
        defer { hold.releaseAll() }

        #expect(mine(.display).contains { $0.reason == "Vigil test: display" })
    }

    @Test func releasingRemovesTheAssertion() {
        let hold = PowerHold()
        hold.apply(system: true, display: true, reason: "Vigil test: release")
        hold.releaseAll()

        #expect(mine(.system).filter { $0.reason == "Vigil test: release" }.isEmpty)
        #expect(mine(.display).filter { $0.reason == "Vigil test: release" }.isEmpty)
        #expect(hold.heldKinds.isEmpty)
    }

    @Test func applyingTheSameRequestTwiceCreatesOnlyOneAssertion() {
        let hold = PowerHold()
        hold.apply(system: true, display: false, reason: "Vigil test: idempotent")
        hold.apply(system: true, display: false, reason: "Vigil test: idempotent")
        defer { hold.releaseAll() }

        #expect(mine(.system).filter { $0.reason == "Vigil test: idempotent" }.count == 1)
    }

    @Test func applyReconcilesDownToWhatIsRequested() {
        let hold = PowerHold()
        hold.apply(system: true, display: true, reason: "Vigil test: reconcile")
        hold.apply(system: true, display: false, reason: "Vigil test: reconcile")
        defer { hold.releaseAll() }

        #expect(hold.heldKinds == [.system])
        #expect(mine(.display).filter { $0.reason == "Vigil test: reconcile" }.isEmpty)
    }

    @Test func droppingTheObjectReleasesItsAssertions() {
        do {
            let hold = PowerHold()
            hold.apply(system: true, display: false, reason: "Vigil test: deinit")
        }
        #expect(mine(.system).filter { $0.reason == "Vigil test: deinit" }.isEmpty)
    }
}
