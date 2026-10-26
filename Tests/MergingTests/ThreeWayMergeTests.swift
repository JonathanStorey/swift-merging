import Merging
import Testing

@Suite struct ThreeWayMergeTests {
    let strategy = ThreeWayMerge<String>()

    @Test func aChangeOnOneSideWins() throws {
        #expect(try strategy.merge(base: "a", ours: "b", theirs: "a") == "b")
        #expect(try strategy.merge(base: "a", ours: "a", theirs: "c") == "c")
        #expect(try strategy.merge(base: "a", ours: "d", theirs: "d") == "d")
    }

    @Test func differentChangesConflict() {
        #expect(throws: MergeConflict<String>.self) {
            try strategy.merge(base: "a", ours: "b", theirs: "c")
        }
    }

    @Test func twoWayMergesOnlyEqualValues() throws {
        #expect(try strategy.merge(ours: "a", theirs: "a") == "a")
        do {
            _ = try strategy.merge(ours: "a", theirs: "b")
            Issue.record("Expected a conflict")
        } catch {
            #expect(error.base == nil)
            #expect(error.ours == "a")
            #expect(error.theirs == "b")
        }
    }

    @Test func aTwoWayStrategyMergesThreeWayToo() throws {
        struct Longer: MergeStrategy {
            // A witness that doesn't throw doesn't name `Value`, so the strategy does.
            typealias Value = String
            func merge(ours: String, theirs: String) -> String { ours.count >= theirs.count ? ours : theirs }
        }
        #expect(try Longer().merge(base: "", ours: "ab", theirs: "abc") == "abc")
    }
}

struct Score: Mergeable, Equatable {
    var points = 0
    static var mergeStrategy: ThreeWayMerge<Score> { ThreeWayMerge() }
}

@Suite struct MergeableTests {
    @Test func aTypeNamesItsStrategy() throws {
        let merged = try Score.mergeStrategy.merge(base: Score(), ours: Score(points: 2), theirs: Score())
        #expect(merged.points == 2)
    }

    struct Game {
        @Merged(ThreeWayMerge<Int>()) var highScore = 0
    }

    @Test func mergedIsAMarker() {
        #expect(Game().highScore == 0)
    }
}
