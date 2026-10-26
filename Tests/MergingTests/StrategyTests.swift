import Foundation
@testable import Merging
import Testing

struct Level: Codable, Comparable, Sendable {
    var number: Int
    static func < (lhs: Level, rhs: Level) -> Bool { lhs.number < rhs.number }
}

struct Game: Codable, Equatable, Mergeable {
    @Merged(.maximum) var highScore = 10
    @Merged(Larger()) var level = Level(number: 1)
    @Merged(.maximum) var lastSeen = Date(timeIntervalSinceReferenceDate: 100)
    @Merged(.adding) var wins = 3
    @Merged(.adding) var distance = 1.5
    @Merged(.trueWins) var flagged = false
    @Merged(.byWord) var note = "the quick brown fox"
}

@Suite struct StrategyTests {
    let base = Game()

    /// Merges two edits of the base made by `ours` and `theirs`.
    func merge(_ ours: (inout Game) -> Void, _ theirs: (inout Game) -> Void) throws -> Game {
        var mine = base
        ours(&mine)
        var other = base
        theirs(&other)
        return try mine.merging(other, base: base)
    }

    @Test func maxKeepsTheLargerAndATypedStrategyUsesTheTypesOrder() throws {
        let merged = try merge({ $0.highScore = 30; $0.level = Level(number: 5); $0.lastSeen = Date(timeIntervalSinceReferenceDate: 300) },
                               { $0.highScore = 20; $0.level = Level(number: 3); $0.lastSeen = Date(timeIntervalSinceReferenceDate: 200) })
        #expect(merged.highScore == 30)
        #expect(merged.level == Level(number: 5))
        #expect(merged.lastSeen == Date(timeIntervalSinceReferenceDate: 300))
    }

    @Test func addingCountsBothSides() throws {
        let merged = try merge({ $0.wins += 2; $0.distance += 1 }, { $0.wins += 1; $0.distance += 0.5 })
        #expect(merged.wins == 6)
        #expect(merged.distance == 3)
    }

    @Test func addingThatOverflowsIsAConflict() {
        var start = base
        start.wins = .max - 1
        var ours = start
        ours.wins += 1
        var theirs = start
        theirs.wins += 1
        #expect(throws: MergeConflict<Game>.self) { try ours.merging(theirs, base: start) }
    }

    @Test func trueWinsSetsTheFlag() throws {
        #expect(try merge({ $0.flagged = true; $0.highScore = 11 }, { $0.flagged = false; $0.highScore = 12 }).flagged)
    }

    @Test func wordEditsCombine() throws {
        let merged = try merge({ $0.note = "the slow brown fox" }, { $0.note = "the quick brown cat, again" })
        #expect(merged.note == "the slow brown cat, again")
    }

    @Test func editsToTheSameWordConflict() {
        #expect(throws: MergeConflict<Game>.self) {
            try merge({ $0.note = "the slow brown fox" }, { $0.note = "the fast brown fox" })
        }
    }

    @Test func twoWayWorksForStrategiesThatNeedNoBase() throws {
        var theirs = base
        theirs.highScore = 50
        theirs.flagged = true
        let merged = try base.merging(theirs)
        #expect(merged.highScore == 50)
        #expect(merged.flagged)
        theirs.wins = 9
        #expect(throws: MergeConflict<Game>.self) { try base.merging(theirs) }
    }

    @Test func wordsJoinBackToTheText() {
        let text = "  Hello, world!  Don't stop.\r\nNew line"
        #expect(WordMerge.words(text).array?.compactMap(\.string) == ["  ", "Hello, ", "world!  ", "Don't ", "stop.\r\n", "New ", "line"])
    }
}

@Suite struct EqualChangeTests {
    @Test func equalIncrementsBothCount() throws {
        let base = Game()
        var ours = base
        ours.wins += 1
        var theirs = base
        theirs.wins += 1
        #expect(try ours.merging(theirs, base: base).wins == 5)
    }
}

@Suite struct StrategyTypeTests {
    struct Mixed: Codable, Mergeable {
        @Merged(.maximum) var level = Level(number: 1)
    }

    @Test func maxOnAStructIsAConflict() {
        var ours = Mixed()
        ours.level = Level(number: 2)
        var theirs = Mixed()
        theirs.level = Level(number: 3)
        #expect(throws: MergeConflict<Mixed>.self) { try ours.merging(theirs, base: Mixed()) }
    }
}
