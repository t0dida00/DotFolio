import Foundation
import Testing
@testable import DotFolioModels

private let cases: [(Int, String)] = [
    (0, "Now"), (12, "Now"), (59, "Now"), (60, "1m"), (300, "5m"), (3_599, "59m"),
    (3_600, "1h"), (18_000, "5h"), (86_400, "1d"), (518_400, "6d"),
    (604_800, "1w"), (2_505_600, "4w"), (2_592_000, "1mth"), (31_449_600, "12mth"),
    (31_536_000, "1yrs"), (69_120_000, "2yrs"),
]

struct CompactAgeTests {
    let now = Date(timeIntervalSince1970: 1_000_000_000)

    @Test(arguments: cases)
    func formats(secondsAgo: Int, expected: String) {
        #expect(CompactAge.string(since: now.addingTimeInterval(-Double(secondsAgo)), now: now) == expected)
    }

    @Test func futureDatesReadAsNow() {
        #expect(CompactAge.string(since: now.addingTimeInterval(30), now: now) == "Now")
    }

    @Test func refreshesEveryFifteenMinutes() {
        #expect(CompactAge.refreshInterval == 900)
    }
}
