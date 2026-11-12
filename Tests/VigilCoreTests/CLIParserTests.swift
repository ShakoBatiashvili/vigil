import Testing
@testable import VigilCore

struct DurationParserTests {
    static let cases: [(String, Double?)] = [
        ("90m", 90), ("2h", 120), ("1h30m", 90), ("1d", 1_440), ("1d2h3m", 1_563),
        ("45", 45),               // a bare number means minutes
        ("1H30M", 90),            // case-insensitive
        (" 15m ", 15),            // surrounding whitespace is fine
        ("", nil), ("abc", nil), ("m", nil), ("0m", nil), ("0", nil), ("-5m", nil),
        ("1.5h", nil),            // no fractions: say 1h30m
        ("1h1h", nil),            // repeated unit
        ("30m1h", nil),           // units out of order
        ("8d", nil),              // beyond the 7-day sanity limit
        ("1x", nil),
    ]

    @Test(arguments: cases)
    func parsesDurations(input: String, expected: Double?) {
        #expect(DurationParser.minutes(from: input) == expected)
    }
}

struct CLIParserTests {
    private func parse(_ args: String...) -> Result<CLICommand, CLIError> { CLIParser.parse(args) }

    // MARK: simple commands

    @Test func noArgumentsShowHelp() {
        #expect(CLIParser.parse([]) == .success(.help))
    }

    @Test func helpAndVersionSpellings() {
        #expect(parse("help") == .success(.help))
        #expect(parse("--help") == .success(.help))
        #expect(parse("-h") == .success(.help))
        #expect(parse("version") == .success(.version))
        #expect(parse("--version") == .success(.version))
    }

    @Test func readOnlyCommands() {
        #expect(parse("status") == .success(.status))
        #expect(parse("holders") == .success(.holders))
        #expect(parse("drain") == .success(.drain))
    }

    @Test func unknownCommandIsReported() {
        #expect(parse("frobnicate") == .failure(.unknownCommand("frobnicate")))
    }

    @Test func readOnlyCommandsRejectStrayArguments() {
        #expect(parse("status", "now") == .failure(.unexpectedArgument("now")))
    }

    // MARK: hold

    @Test func holdWithNoOptionsIsIndefinite() {
        #expect(parse("hold") == .success(.hold(mode: .indefinite, display: false)))
    }

    @Test func holdForADuration() {
        #expect(parse("hold", "--for", "1h30m") == .success(.hold(mode: .timed(seconds: 5_400), display: false)))
    }

    @Test func holdUntilAClockTime() {
        #expect(parse("hold", "--until", "18:00") == .success(.hold(mode: .until(hour: 18, minute: 0), display: false)))
        #expect(parse("hold", "--until", "9:05") == .success(.hold(mode: .until(hour: 9, minute: 5), display: false)))
    }

    @Test func holdWithTheDisplayFlag() {
        #expect(parse("hold", "--display") == .success(.hold(mode: .indefinite, display: true)))
        #expect(parse("hold", "--for", "30m", "--display") == .success(.hold(mode: .timed(seconds: 1_800), display: true)))
        #expect(parse("hold", "--display", "--for", "30m") == .success(.hold(mode: .timed(seconds: 1_800), display: true)))
    }

    @Test func holdRejectsBadDurations() {
        #expect(parse("hold", "--for", "abc") == .failure(.invalidDuration("abc")))
        #expect(parse("hold", "--for", "0m") == .failure(.invalidDuration("0m")))
    }

    @Test(arguments: ["24:00", "18", "18:60", "ab:cd", "", "-1:30", "12:5:0"])
    func holdRejectsBadClockTimes(value: String) {
        #expect(parse("hold", "--until", value) == .failure(.invalidTime(value)))
    }

    @Test func holdRejectsForAndUntilTogether() {
        #expect(parse("hold", "--for", "1h", "--until", "18:00") == .failure(.conflictingOptions))
    }

    @Test func holdReportsAMissingOptionValue() {
        #expect(parse("hold", "--for") == .failure(.missingValue("--for")))
        #expect(parse("hold", "--until") == .failure(.missingValue("--until")))
    }

    @Test func holdReportsUnknownOptionsAndStrayWords() {
        #expect(parse("hold", "--bogus") == .failure(.unknownOption("--bogus")))
        #expect(parse("hold", "extra") == .failure(.unexpectedArgument("extra")))
    }

    // MARK: stop

    @Test func stopTakesAPid() {
        #expect(parse("stop", "4242") == .success(.stop(pid: 4242)))
    }

    @Test func stopRejectsMissingOrInvalidPids() {
        #expect(parse("stop") == .failure(.missingValue("pid")))
        #expect(parse("stop", "abc") == .failure(.invalidPID("abc")))
        #expect(parse("stop", "0") == .failure(.invalidPID("0")))
        #expect(parse("stop", "1") == .failure(.invalidPID("1")))
        #expect(parse("stop", "-5") == .failure(.invalidPID("-5")))
        #expect(parse("stop", "99999999999") == .failure(.invalidPID("99999999999")))
    }

    @Test func stopRejectsExtraArguments() {
        #expect(parse("stop", "12", "13") == .failure(.unexpectedArgument("13")))
    }

    // MARK: messages

    @Test func errorsHaveReadableMessages() {
        #expect(CLIError.unknownCommand("frobnicate").message.contains("frobnicate"))
        #expect(CLIError.invalidDuration("abc").message.contains("abc"))
        #expect(CLIError.conflictingOptions.message.contains("--for"))
    }
}
