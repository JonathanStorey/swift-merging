import Testing
@testable import Merging

struct Tally: Codable, Equatable, Mergeable {
    @Merged(.numericSum) var visits = 0
    @Merged(.numericSum) var distance = 0.0
    @Merged(NumericSumMerge()) var bytes: UInt8 = 0
}

@Suite struct NumericSumMergeTests {
    @Test func bothSidesChangesCount() throws {
        let base = Tally(visits: 3, distance: 1.5, bytes: 10)
        var ours = base
        ours.visits += 1
        ours.distance += 2
        var theirs = base
        theirs.visits += 1
        theirs.bytes -= 4
        let merged = try ours.merging(theirs, base: base)
        #expect(merged == Tally(visits: 5, distance: 3.5, bytes: 6))
    }

    @Test func overflowIsAConflict() {
        #expect(throws: MergeConflict<UInt8>.self) {
            try NumericSumMerge<UInt8>().merge(base: 100, ours: 200, theirs: 200)
        }
        #expect(throws: MergeConflict<Int>.self) {
            try NumericSumMerge<Int>().merge(base: 0, ours: .max, theirs: 1)
        }
    }

    @Test func needsABase() {
        #expect(throws: MergeConflict<Int>.self) {
            try NumericSumMerge<Int>().merge(ours: 1, theirs: 2)
        }
    }
}
