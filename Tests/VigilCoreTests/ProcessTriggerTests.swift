import Testing
@testable import VigilCore

struct ProcessTriggerTests {
    // MARK: matching

    @Test func matchesCaseInsensitively() {
        #expect(ProcessTrigger.firstMatch(running: ["zsh", "Xcode"], watching: ["xcode"]) == "xcode")
    }

    @Test func ignoresADotAppSuffixOnTheWatchedName() {
        #expect(ProcessTrigger.firstMatch(running: ["Xcode"], watching: ["Xcode.app"]) == "Xcode")
    }

    @Test func requiresAWholeNameNotASubstring() {
        // "ssh" must not keep the Mac awake just because sshd is running.
        #expect(ProcessTrigger.firstMatch(running: ["sshd"], watching: ["ssh"]) == nil)
    }

    @Test func returnsTheFirstWatchedNameThatIsRunning() {
        #expect(ProcessTrigger.firstMatch(running: ["Slack", "Xcode"], watching: ["Xcode", "Slack"]) == "Xcode")
    }

    @Test func ignoresBlankWatchEntries() {
        #expect(ProcessTrigger.firstMatch(running: ["", "zsh"], watching: ["", "   "]) == nil)
    }

    @Test func returnsNilWhenNothingIsRunning() {
        #expect(ProcessTrigger.firstMatch(running: [], watching: ["Xcode"]) == nil)
    }

    // MARK: normalising user input

    @Test func normalizeTrimsAndStripsDotApp() {
        #expect(ProcessTrigger.normalize("  Xcode.app \n") == "Xcode")
    }

    @Test func normalizeKeepsTheCaseForDisplay() {
        #expect(ProcessTrigger.normalize("Google Chrome") == "Google Chrome")
    }

    @Test func normalizeRejectsEmptyInput() {
        #expect(ProcessTrigger.normalize("") == nil)
        #expect(ProcessTrigger.normalize("   ") == nil)
        #expect(ProcessTrigger.normalize(".app") == nil)
    }

    @Test func normalizeRejectsPathsAndControlCharacters() {
        #expect(ProcessTrigger.normalize("/usr/bin/ssh") == nil)
        #expect(ProcessTrigger.normalize("a\nb") == nil)
        #expect(ProcessTrigger.normalize("a\u{0}b") == nil)
    }

    @Test func normalizeRejectsOverlongNames() {
        #expect(ProcessTrigger.normalize(String(repeating: "a", count: 129)) == nil)
        #expect(ProcessTrigger.normalize(String(repeating: "a", count: 128)) != nil)
    }
}
