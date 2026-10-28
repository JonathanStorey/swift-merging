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
        return try mine.merging(with: other, from: base)
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
        #expect(throws: MergeConflict<Game>.self) { try ours.merging(with: theirs, from: start) }
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
        let merged = try base.merging(with: theirs)
        #expect(merged.highScore == 50)
        #expect(merged.flagged)
        theirs.wins = 9
        #expect(throws: MergeConflict<Game>.self) { try base.merging(with: theirs) }
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
        #expect(try ours.merging(with: theirs, from: base).wins == 5)
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
        let merged = try ours.merging(with: theirs, from: Score())
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
        let merged = try ours.merging(with: theirs, from: Trip())
        #expect(merged.booking == Booking(note: "b", confirmed: true))
    }
}

@Suite struct ProjectedValueTests {
    @Test func dollarMergesOnePropertyByItsStrategy() throws {
        var game = Game()
        #expect(try game.$highScore.merging(with: 20, from: 10) == 20)
        try game.$wins.merge(with: 5, from: 3)
        #expect(game.wins == 5)
        game.wins = 4
        try game.$wins.merge(with: 5, from: 3)
        #expect(game.wins == 6)
        #expect(try game.$flagged.merging(with: true))
        #expect(throws: MergeConflict<Int>.self) { try game.$wins.merging(with: 9) }
        #expect(game.wins == 6)
    }
}

@Suite struct KeepTests {
    struct Draft: Codable, Equatable, Mergeable {
        @Merged(.keep(.ours)) var body = "a"
        @Merged(.keep(.theirs)) var total = 1
        var title = "t"
    }

    @Test func keepsTheNamedSideWhenBothChanged() throws {
        var ours = Draft()
        ours.body = "ours"
        ours.total = 2
        var theirs = Draft()
        theirs.body = "theirs"
        theirs.total = 3
        theirs.title = "theirs"
        let merged = try ours.merging(with: theirs, from: Draft())
        #expect(merged.body == "ours")
        #expect(merged.total == 3)
        #expect(merged.title == "theirs")
    }

    @Test func mergesWithoutABase() throws {
        var ours = Draft()
        ours.body = "ours"
        ours.total = 2
        var theirs = Draft()
        theirs.body = "theirs"
        theirs.total = 3
        let merged = try ours.merging(with: theirs)
        #expect(merged.body == "ours")
        #expect(merged.total == 3)
    }

    @Test func typedStrategiesKeepTheirSide() {
        #expect(KeepOursMerge<Int>().merge(base: 1, ours: 2, theirs: 3) == 2)
        #expect(KeepTheirsMerge<Int>().merge(ours: 2, theirs: 3) == 3)
    }
}

@Suite struct FavoringTests {
    struct Place: Codable, Equatable {
        var street = "Elm"
        var city = "Oslo"
    }

    struct Contact: Codable, Equatable {
        var name = "Ann"
        var place = Place()
        var tags: Set<String> = ["family"]
        var notes: [String: String] = ["a": "1"]
    }

    @Test func aClashKeepsTheSideAndTheRestStillMerges() throws {
        var ours = Contact()
        ours.name = "Ann B."
        ours.place.street = "Oak"
        ours.place.city = "Bergen"
        var theirs = Contact()
        theirs.name = "Anne"
        theirs.place.city = "Trondheim"
        theirs.tags.insert("work")
        let keepTheirs = CodableTotalMerge<Contact, TheirsSide>().merge(base: Contact(), ours: ours, theirs: theirs)
        #expect(keepTheirs == Contact(name: "Anne", place: Place(street: "Oak", city: "Trondheim"), tags: ["family", "work"]))
        let keepOurs = CodableTotalMerge<Contact, OursSide>().merge(base: Contact(), ours: ours, theirs: theirs)
        #expect(keepOurs == Contact(name: "Ann B.", place: Place(street: "Oak", city: "Bergen"), tags: ["family", "work"]))
    }

    @Test func aKeyRemovedWhileTheOtherChangedItKeepsTheSide() throws {
        var ours = Contact()
        ours.notes["a"] = nil
        var theirs = Contact()
        theirs.notes["a"] = "2"
        #expect(CodableTotalMerge<Contact, OursSide>().merge(base: Contact(), ours: ours, theirs: theirs).notes == [:])
        #expect(CodableTotalMerge<Contact, TheirsSide>().merge(base: Contact(), ours: ours, theirs: theirs).notes == ["a": "2"])
    }

    @Test func withoutABaseEachDifferenceKeepsTheSide() throws {
        var ours = Contact()
        ours.name = "Ann B."
        var theirs = Contact()
        theirs.place.city = "Bergen"
        let merged = CodableTotalMerge<Contact, TheirsSide>().merge(ours: ours, theirs: theirs)
        #expect(merged == Contact(name: "Ann", place: Place(street: "Elm", city: "Bergen")))
    }

    @Test func withoutFavoringAClashStillThrows() {
        var ours = Contact()
        ours.name = "Ann B."
        var theirs = Contact()
        theirs.name = "Anne"
        #expect(throws: MergeConflict<Contact>.self) {
            try CodableNodeMerge<Contact>().merge(base: Contact(), ours: ours, theirs: theirs)
        }
    }
}

@Suite struct TotalTests {
    struct Place: Codable, Equatable {
        var street = "Elm"
        var city = "Oslo"
    }

    struct Trip: Codable, Equatable, Mergeable {
        @Merged(.total(favoring: .theirs)) var place = Place()
        @Merged(.total(favoring: .ours)) var stop = Place()
    }

    @Test func clashesTakeTheFavoredSideAndTheRestMerges() throws {
        var ours = Trip()
        ours.place = Place(street: "Oak", city: "Bergen")
        ours.stop = Place(street: "Oak", city: "Bergen")
        var theirs = Trip()
        theirs.place.city = "Trondheim"
        theirs.stop.city = "Trondheim"
        let merged = try ours.merging(with: theirs, from: Trip())
        #expect(merged.place == Place(street: "Oak", city: "Trondheim"))
        #expect(merged.stop == Place(street: "Oak", city: "Bergen"))
    }
}
