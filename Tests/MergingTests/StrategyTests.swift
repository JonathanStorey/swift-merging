import Foundation
@testable import Merging
import Testing

struct Level: Codable, Comparable, Sendable {
    var number: Int
    static func < (lhs: Level, rhs: Level) -> Bool { lhs.number < rhs.number }
}

struct Game: Codable, Equatable, Mergeable {
    @Merged(.maximum) var highScore = 10
    @Merged(.maximum) var level = Level(number: 1)
    @Merged(.maximum) var lastSeen = Date(timeIntervalSinceReferenceDate: 100)
    @Merged(.sum) var wins = 3
    @Merged(.sum) var distance = 1.5
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

    @Test func maximumKeepsTheLargerByTheTypesOwnOrder() throws {
        let merged = try merge({ $0.highScore = 30; $0.level = Level(number: 5); $0.lastSeen = Date(timeIntervalSinceReferenceDate: 300) },
                               { $0.highScore = 20; $0.level = Level(number: 3); $0.lastSeen = Date(timeIntervalSinceReferenceDate: 200) })
        #expect(merged.highScore == 30)
        #expect(merged.level == Level(number: 5))
        #expect(merged.lastSeen == Date(timeIntervalSinceReferenceDate: 300))
    }

    @Test func sumCountsBothSides() throws {
        let merged = try merge({ $0.wins += 2; $0.distance += 1 }, { $0.wins += 1; $0.distance += 0.5 })
        #expect(merged.wins == 6)
        #expect(merged.distance == 3)
    }

    @Test func sumThatOverflowsIsAConflict() {
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
        #expect(StringWordMerge<String>.words(text) == ["  ", "Hello, ", "world!  ", "Don't ", "stop.\r\n", "New ", "line"])
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

/// Keeps the larger number, working on the stored form.
struct LargerTree: TreeMergeStrategy {
    func merge(base: CodableTree, ours: CodableTree, theirs: CodableTree) throws(MergeConflict<CodableTree>) -> CodableTree {
        guard let mine = ours.double, let other = theirs.double else { throw MergeConflict(base: base, ours: ours, theirs: theirs) }
        return mine < other ? theirs : ours
    }
}

extension Merged where Strategy == LargerTree {
    init(wrappedValue: Value, _ strategy: LargerTree) where Value: Numeric {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}

@Suite struct TypedStrategyTests {
    @Test func strategiesMergePlainValues() throws {
        #expect(ComparableMaximumMerge<Int>().merge(base: 1, ours: 5, theirs: 3) == 5)
        #expect(try StringWordMerge<String>().merge(base: "a b c", ours: "x b c", theirs: "a b z") == "x b z")
        #expect(try StringWordMerge<Substring>().merge(base: "a b", ours: "x b", theirs: "a z") == "x z")
        #expect(throws: MergeConflict<Int>.self) { try NumericSumMerge<Int>().merge(ours: 1, theirs: 2) }
        #expect(SetAlgebraUnionMerge<Set<Int>>().merge(ours: [1], theirs: [2]) == [1, 2])
        #expect(try DictionaryKeyedMerge<[String: Int]>().merge(base: ["a": 1], ours: ["a": 1, "b": 2], theirs: [:]) == ["b": 2])
    }
}

@Suite struct TypedMergeTests {
    struct Score: Codable, Mergeable {
        @Merged(LargerTree()) var best = 0
        @Merged(LargerTree().typed(as: Int.self)) var worst = 0
    }

    @Test func aTreeStrategyMergesPlainValues() throws {
        #expect(try LargerTree().typed(as: Int.self).merge(base: 1, ours: 5, theirs: 3) == 5)
        #expect(throws: MergeConflict<String>.self) { try LargerTree().typed(as: String.self).merge(base: "a", ours: "b", theirs: "c") }
    }

    @Test func aTreeStrategyWorksInMerged() throws {
        var ours = Score()
        ours.best = 7
        ours.worst = 7
        var theirs = Score()
        theirs.best = 4
        theirs.worst = 4
        let merged = try ours.merging(theirs, base: Score())
        #expect(merged.best == 7)
        #expect(merged.worst == 7)
    }
}

@Suite struct CodableNodeMergeTests {
    /// Codable, but not Mergeable.
    struct Place: Codable, Equatable {
        var street = "Elm"
        var city = "Oslo"
    }

    struct Trip: Codable, Mergeable {
        @Merged(.byNode) var booking = Booking(note: "a", confirmed: false)
    }

    @Test func mergesAnyCodableValue() throws {
        let merged = try CodableNodeMerge<Place>().merge(base: Place(), ours: Place(street: "Oak"), theirs: Place(city: "Bergen"))
        #expect(merged == Place(street: "Oak", city: "Bergen"))
    }

    @Test func byNodeOverridesATypesOwnMerge() throws {
        var ours = Trip()
        ours.booking.note = "b"
        var theirs = Trip()
        theirs.booking.confirmed = true
        let merged = try ours.merging(theirs, base: Trip())
        #expect(merged.booking == Booking(note: "b", confirmed: true))
    }
}
