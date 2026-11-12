import Testing
@testable import VigilCore

private let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
private let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
private let terminal = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
private let coreaudiod = "/usr/sbin/coreaudiod"

private func row(_ pid: Int32, _ power: Double, _ path: String?, name: String = "proc") -> ProcessEnergy {
    ProcessEnergy(pid: pid, power: power, path: path, fallbackName: name)
}

struct DrainModelTests {
    // MARK: path helpers

    @Test func appNameIsTheOutermostAppBundle() {
        #expect(DrainModel.appName(fromPath: chrome) == "Google Chrome")
        #expect(DrainModel.appName(fromPath: chromeHelper) == "Google Chrome")   // helper rolls up to its app
        #expect(DrainModel.appName(fromPath: terminal) == "Terminal")
    }

    @Test func appNameIsNilOutsideAnAppBundle() {
        #expect(DrainModel.appName(fromPath: coreaudiod) == nil)
        #expect(DrainModel.appName(fromPath: "") == nil)
    }

    @Test func bundlePathIsTheOutermostAppDirectory() {
        #expect(DrainModel.bundlePath(fromPath: chromeHelper) == "/Applications/Google Chrome.app")
        #expect(DrainModel.bundlePath(fromPath: coreaudiod) == nil)
    }

    // MARK: grouping

    @Test func helperProcessesRollUpIntoTheirApp() {
        let result = DrainModel.group([row(1, 20, chrome), row(2, 13, chromeHelper)], top: 5)
        #expect(result.count == 1)
        #expect(result[0].name == "Google Chrome")
        #expect(result[0].power == 33)
        #expect(result[0].processCount == 2)
        #expect(result[0].bundlePath == "/Applications/Google Chrome.app")
    }

    @Test func nonAppProcessesAreNamedAfterTheirExecutable() {
        let result = DrainModel.group([row(603, 7, coreaudiod)], top: 5)
        #expect(result[0].name == "coreaudiod")
        #expect(result[0].bundlePath == nil)
    }

    @Test func processesWithoutAPathUseTheFallbackName() {
        let result = DrainModel.group([row(0, 4, nil, name: "kernel_task")], top: 5)
        #expect(result[0].name == "kernel_task")
    }

    @Test func executablesNamedAfterTheirVersionUseTheProcessNameInstead() {
        // Claude Code installs as .../versions/2.1.322: "2.1.322" tells nobody anything.
        let path = "/Users/me/.local/share/claude/versions/2.1.322"
        let result = DrainModel.group([row(1, 5, path, name: "claude"), row(2, 3, path, name: "claude")], top: 5)
        #expect(result.count == 1)
        #expect(result[0].name == "claude")
        #expect(result[0].processCount == 2)
    }

    @Test func aVersionLikeNameWithNoFallbackIsKeptAsIs() {
        let result = DrainModel.group([row(1, 5, "/opt/tool/1.2.3", name: "")], top: 5)
        #expect(result[0].name == "1.2.3")
    }

    @Test func executableNameHelperOnlyReplacesDigitsAndDots() {
        #expect(DrainModel.isVersionLike("2.1.322"))
        #expect(DrainModel.isVersionLike("10"))
        #expect(!DrainModel.isVersionLike("python3.12"))
        #expect(!DrainModel.isVersionLike("zsh"))
        #expect(!DrainModel.isVersionLike(""))
    }

    @Test func manyProcessesOfTheSameExecutableAreOneRow() {
        let result = DrainModel.group([row(1, 2, "/bin/zsh"), row(2, 3, "/bin/zsh")], top: 5)
        #expect(result.count == 1)
        #expect(result[0].processCount == 2)
        #expect(result[0].power == 5)
    }

    // MARK: ordering, sharing, "Other"

    @Test func sortsByPowerDescending() {
        let result = DrainModel.group([row(1, 3, "/a/one"), row(2, 9, "/a/two"), row(3, 5, "/a/three")], top: 5)
        #expect(result.map(\.name) == ["two", "three", "one"])
    }

    @Test func sharesAreRelativeToTheTotalOfAllProcesses() {
        let result = DrainModel.group([row(1, 50, "/a/one"), row(2, 30, "/a/two"), row(3, 20, "/a/three")], top: 2)
        #expect(result[0].share == 0.5)
        #expect(result[1].share == 0.3)
    }

    @Test func everythingBeyondTheTopNIsFoldedIntoOther() {
        let rows = (1...6).map { row(Int32($0), Double(100 - $0 * 10), "/a/p\($0)") }   // 90 80 70 60 50 40
        let result = DrainModel.group(rows, top: 3)
        #expect(result.count == 4)
        #expect(result.last?.isOther == true)
        #expect(result.last?.name == "Other")
        #expect(result.last?.power == 150)          // 60 + 50 + 40
        #expect(result.last?.processCount == 3)
    }

    @Test func noOtherRowWhenEverythingFits() {
        let result = DrainModel.group([row(1, 5, "/a/one"), row(2, 4, "/a/two")], top: 5)
        #expect(result.contains { $0.isOther } == false)
    }

    @Test func idleProcessesDoNotCountAsRows() {
        let result = DrainModel.group([row(1, 0, "/a/idle"), row(2, 5, "/a/busy")], top: 5)
        #expect(result.map(\.name) == ["busy"])
    }

    @Test func zeroTotalProducesAnEmptyListNotNaN() {
        #expect(DrainModel.group([row(1, 0, "/a/idle")], top: 5).isEmpty)
        #expect(DrainModel.group([], top: 5).isEmpty)
    }
}
