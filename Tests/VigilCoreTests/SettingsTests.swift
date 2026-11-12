import Foundation
import Testing
@testable import VigilCore

struct SettingsTests {
    @Test func defaultsAreConservative() {
        let s = Settings()
        #expect(s.batteryThreshold == 20)
        #expect(s.keepDisplayOn == false)
        #expect(s.watchedProcesses.isEmpty)
        #expect(s.scheduleEnabled == false)
        #expect(s.schedule == nil)
    }

    // MARK: clamping

    @Test func clampsTheBatteryThresholdIntoItsRange() {
        var low = Settings(); low.batteryThreshold = 1
        var high = Settings(); high.batteryThreshold = 99
        #expect(low.validated().batteryThreshold == Settings.thresholdRange.lowerBound)
        #expect(high.validated().batteryThreshold == Settings.thresholdRange.upperBound)
    }

    // MARK: watched processes

    @Test func validationDedupesWatchedProcessesCaseInsensitivelyKeepingOrder() {
        var s = Settings()
        s.watchedProcesses = ["Xcode", "xcode", "Slack", "XCODE.app"]
        #expect(s.validated().watchedProcesses == ["Xcode", "Slack"])
    }

    @Test func validationDropsInvalidWatchedNames() {
        var s = Settings()
        s.watchedProcesses = ["", "/bin/sh", "Slack"]
        #expect(s.validated().watchedProcesses == ["Slack"])
    }

    @Test func validationCapsTheNumberOfWatchedProcesses() {
        var s = Settings()
        s.watchedProcesses = (0..<(Settings.maxWatchedProcesses + 10)).map { "app\($0)" }
        #expect(s.validated().watchedProcesses.count == Settings.maxWatchedProcesses)
    }

    // MARK: schedule

    @Test func validationDropsAnInvalidScheduleAndSwitchesItOff() {
        var s = Settings()
        s.scheduleEnabled = true
        s.schedule = TimeWindow(weekdays: [2], startMinute: 600, endMinute: 600) // zero length
        let v = s.validated()
        #expect(v.schedule == nil)
        #expect(v.scheduleEnabled == false)
    }

    @Test func validationKeepsAValidSchedule() throws {
        var s = Settings()
        s.scheduleEnabled = true
        s.schedule = try #require(TimeWindow.make(weekdays: [2, 3], startMinute: 540, endMinute: 1080))
        #expect(s.validated() == s)
    }

    // MARK: decoding

    @Test func decodingGarbageFallsBackToDefaults() {
        #expect(Settings.decode(from: Data("not json".utf8)) == Settings())
    }

    @Test func decodingEmptyDataFallsBackToDefaults() {
        #expect(Settings.decode(from: Data()) == Settings())
    }

    @Test func decodingFillsMissingKeysWithDefaults() {
        let data = Data(#"{"batteryThreshold": 30}"#.utf8)
        let s = Settings.decode(from: data)
        #expect(s.batteryThreshold == 30)
        #expect(s.keepDisplayOn == false)
        #expect(s.watchedProcesses.isEmpty)
    }

    @Test func decodingIgnoresUnknownKeys() {
        let data = Data(#"{"batteryThreshold": 25, "somethingFromTheFuture": true}"#.utf8)
        #expect(Settings.decode(from: data).batteryThreshold == 25)
    }

    @Test func decodingClampsOutOfRangeValues() {
        let data = Data(#"{"batteryThreshold": 400}"#.utf8)
        #expect(Settings.decode(from: data).batteryThreshold == Settings.thresholdRange.upperBound)
    }

    @Test func encodeThenDecodeRoundTrips() throws {
        var s = Settings()
        s.batteryThreshold = 35
        s.keepDisplayOn = true
        s.watchedProcesses = ["Xcode", "Slack"]
        s.scheduleEnabled = true
        s.schedule = try #require(TimeWindow.make(weekdays: [2, 6], startMinute: 480, endMinute: 1020))
        let data = try #require(s.encoded())
        #expect(Settings.decode(from: data) == s)
    }
}
