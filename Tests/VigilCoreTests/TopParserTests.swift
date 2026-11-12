import Testing
@testable import VigilCore

/// Fixture shaped exactly like `/usr/bin/top -l 2 -s 1 -o power -stats pid,power`
/// on macOS 27: a first sample of zeros (no delta yet), then the real sample.
private let twoSampleOutput = [
    "Processes: 650 total, 4 running, 646 sleeping, 5004 threads ",
    "2026/11/13 02:15:40",
    "Load Avg: 4.64, 4.40, 4.19 ",
    "",
    "PID    POWER",
    "99662  0.0  ",
    "99369  0.0  ",
    "Processes: 650 total, 2 running, 648 sleeping, 4997 threads ",
    "2026/11/13 02:15:41",
    "Load Avg: 4.64, 4.40, 4.19 ",
    "",
    "PID    POWER",
    "94791  39.9 ",
    "456    21.6 ",
    "2475   13.2 ",
    "3056   9.7  ",
    "11493  8.9  ",
    "603    7.0  ",
].joined(separator: "\n")

struct TopParserTests {
    @Test func readsTheSecondSampleNotTheFirst() {
        let rows = TopParser.parse(twoSampleOutput)
        #expect(rows.map(\.pid) == [94791, 456, 2475, 3056, 11493, 603])
        #expect(rows.map(\.power) == [39.9, 21.6, 13.2, 9.7, 8.9, 7.0])
    }

    @Test func stopsAtTheFirstLineThatIsNotARow() {
        let text = ["PID    POWER", "10  5.0 ", "20  3.0 ", "", "Processes: 1 total", "30  9.0 "].joined(separator: "\n")
        #expect(TopParser.parse(text).map(\.pid) == [10, 20])
    }

    @Test func returnsNothingForEmptyOrGarbageInput() {
        #expect(TopParser.parse("").isEmpty)
        #expect(TopParser.parse("hello\nworld").isEmpty)
        #expect(TopParser.parse("Processes: 650 total").isEmpty)   // no PID header at all
    }

    @Test func skipsRowsWithUnparseableValuesButKeepsReading() {
        let text = ["PID    POWER", "10  5.0 ", "30  x ", "40  2.5 "].joined(separator: "\n")
        #expect(TopParser.parse(text).map(\.pid) == [10, 40])
    }

    @Test func aLineThatDoesNotStartWithAPidEndsTheTable() {
        let text = ["PID    POWER", "10  5.0 ", "abc  3.0 ", "40  2.5 "].joined(separator: "\n")
        #expect(TopParser.parse(text).map(\.pid) == [10])
    }

    @Test func toleratesTrendMarkersAfterTheValue() {
        let text = ["PID    POWER", "10  12.5+", "20  3.0-"].joined(separator: "\n")
        #expect(TopParser.parse(text).map(\.power) == [12.5, 3.0])
    }

    @Test func dropsNegativeAndNonFiniteValues() {
        let text = ["PID    POWER", "10  -4.0 ", "20  nan ", "30  1.5 "].joined(separator: "\n")
        #expect(TopParser.parse(text).map(\.pid) == [30])
    }

    @Test func ignoresPidsThatAreNotPositive() {
        let text = ["PID    POWER", "0  5.0 ", "10  1.0 "].joined(separator: "\n")
        #expect(TopParser.parse(text).map(\.pid) == [10])
    }
}
