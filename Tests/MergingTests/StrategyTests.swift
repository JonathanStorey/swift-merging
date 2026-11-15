import Foundation
import Merging
import Testing

struct Level: Comparable, Sendable {
    var number: Int
    static func < (lhs: Level, rhs: Level) -> Bool { lhs.number < rhs.number }
}

struct Spot: Hashable, Sendable {
    var x: Int
    var y: Int
}

struct Shipping: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let fast = Shipping(rawValue: 1)
    static let gift = Shipping(rawValue: 2)
    static let signed = Shipping(rawValue: 4)
}

/// Every shorthand on one type, so a shorthand the macro doesn't know fails to compile.
struct Game {
    @Merged(.maximum) var highScore = 10
    @Merged(.maximum) var level: Level = Level(number: 1)
    @Merged(.maximum) var lastSeen: Date = Date(timeIntervalSinceReferenceDate: 100)
    @Merged(.sum) var wins = 3
    @Merged(.sum) var distance = 1.5
    @Merged(.sum) var bytes: UInt8 = 10
    @Merged(.trueWins) var flagged = false
    @Merged(.byWord) var note = "the quick brown fox"
    @Merged(.byElement) var steps: [String] = ["boil", "stir", "serve"]
    @Merged(.byElement) var title = "soup"
    @Merged(.byMembership) var tags: Set<String> = ["a", "b", "c"]
    @Merged(.byMembership) var shipping: Shipping = [.fast]
    @Merged(.union) var recipients: Set<String> = ["ana", "bo"]
    @Merged(.byKey) var pins: [Spot: String] = [Spot(x: 0, y: 0): "home"]
    @Merged(.keep(.theirs)) var cachedTotal = 0
}

@Suite struct StrategyTests {
    let base = Game()

    @Test func maximumKeepsTheLargerByTheTypesOwnOrder() {
        let ours = Game(highScore: 30, level: Level(number: 5), lastSeen: Date(timeIntervalSinceReferenceDate: 300))
        #expect(ours.$highScore.merging(with: 20, from: base.highScore) == 30)
        #expect(ours.$level.merging(with: Level(number: 3), from: base.level) == Level(number: 5))
        #expect(ours.$lastSeen.merging(with: Date(timeIntervalSinceReferenceDate: 200), from: base.lastSeen)
            == Date(timeIntervalSinceReferenceDate: 300))
        #expect(base.$highScore.merging(with: 50) == 50)
    }

    @Test func sumCountsBothSides() {
        var ours = base
        ours.wins += 2
        ours.distance += 1
        ours.bytes -= 4
        #expect(ours.$wins.merging(with: base.wins + 1, from: base.wins) == 6)
        #expect(ours.$distance.merging(with: base.distance + 0.5, from: base.distance) == 3)
        #expect(ours.$bytes.merging(with: base.bytes + 1, from: base.bytes) == 7)
    }

    @Test func equalIncrementsBothCount() {
        let ours = Game(wins: 4)
        #expect(ours.$wins.merging(with: 4, from: 3) == 5)
    }

    @Test func aSumThatOverflowsCantMerge() {
        #expect(NumericSumMerge<UInt8>().merge(base: 100, ours: 200, theirs: 200) == nil)
        #expect(NumericSumMerge<Int>().merge(base: 0, ours: .max, theirs: 1) == nil)
    }

    @Test func aSumNeedsABaseUnlessEqual() {
        #expect(NumericSumMerge<Int>().merge(ours: 1, theirs: 2) == nil)
        #expect(NumericSumMerge<Int>().merge(ours: 5, theirs: 5) == 5)
    }

    @Test func trueWinsSetsTheFlag() {
        #expect(Game(flagged: true).$flagged.merging(with: false, from: false) == true)
        #expect(base.$flagged.merging(with: true) == true)
        // A side only one changed keeps that side, so clearing the flag sticks when the other left it.
        #expect(base.$flagged.merging(with: true, from: true) == false)
        #expect(BoolTrueWinsMerge().merge(base: true, ours: false, theirs: true) == true)
    }

    @Test func wordEditsCombine() {
        let ours = Game(note: "the slow brown fox")
        #expect(ours.$note.merging(with: "the quick brown cat, again", from: base.note) == "the slow brown cat, again")
    }

    @Test func editsToTheSameWordCantMerge() {
        let ours = Game(note: "the slow brown fox")
        #expect(ours.$note.merging(with: "the fast brown fox", from: base.note) == nil)
        #expect(StringWordMerge<String>().merge(ours: "the fox", theirs: "the fox") == "the fox")
    }

    @Test func insertionsFromBothSidesAreKept() {
        let ours = Game(steps: ["boil", "salt", "stir", "serve"])
        #expect(ours.$steps.merging(with: ["stir", "serve", "eat"], from: base.steps) == ["salt", "stir", "serve", "eat"])
    }

    @Test func textMergesByCharacter() {
        let ours = Game(title: "soups")
        #expect(ours.$title.merging(with: "Soup", from: base.title) == "Soups")
        #expect(RangeReplaceableCollectionElementMerge<String>().merge(base: "cat", ours: "cart", theirs: "cats") == "carts")
    }

    @Test func anElementBothReplacedDifferentlyCantMerge() {
        let strategy = RangeReplaceableCollectionElementMerge<[Int]>()
        #expect(strategy.merge(base: [1, 2, 3], ours: [0, 1, 2, 3], theirs: [1, 2, 3, 4]) == [0, 1, 2, 3, 4])
        #expect(strategy.merge(base: [1], ours: [2], theirs: [3]) == nil)
        #expect(strategy.merge(base: [1], ours: [2], theirs: [2]) == [2])
    }

    @Test func setsMergeByMembership() {
        let ours = Game(tags: ["c", "a", "ours"], shipping: [.fast, .gift])
        #expect(ours.$tags.merging(with: ["b", "a", "theirs"], from: base.tags) == ["a", "ours", "theirs"])
        #expect(ours.$shipping.merging(with: [.signed], from: base.shipping) == [.gift, .signed])
        #expect(ours.$tags.merging(with: ["c", "a", "ours"]) == ["c", "a", "ours"])
        #expect(ours.$tags.merging(with: ["a"]) == nil)
    }

    @Test func manySetsMergeWhateverTheirOrder() {
        let big = Set((0..<200).map(String.init))
        let strategy = SetAlgebraMembershipMerge<Set<String>>()
        #expect(strategy.merge(base: big, ours: big.union(["x"]), theirs: big.subtracting(["7"])) == big.subtracting(["7"]).union(["x"]))
    }

    @Test func unionLosesNothingWithoutABase() {
        let ours = Game(recipients: ["ana", "cy"])
        #expect(ours.$recipients.merging(with: ["bo", "di", "ana"]) == ["ana", "cy", "bo", "di"])
    }

    @Test func unionKeepsRemovalsWithABase() {
        let ours = Game(recipients: ["ana"])
        #expect(ours.$recipients.merging(with: ["ana", "bo", "cy"], from: base.recipients) == ["ana", "cy"])
    }

    @Test func aDictionaryMergesByKey() {
        let ours = Game(pins: [Spot(x: 0, y: 0): "home", Spot(x: 1, y: 1): "ours"])
        let theirs: [Spot: String] = [Spot(x: 0, y: 0): "start", Spot(x: 2, y: 2): "theirs"]
        #expect(ours.$pins.merging(with: theirs, from: base.pins) == [
            Spot(x: 0, y: 0): "start", Spot(x: 1, y: 1): "ours", Spot(x: 2, y: 2): "theirs",
        ])
    }

    @Test func aDictionaryKeyBothChangedCantMerge() {
        let strategy = DictionaryKeyedMerge<String, Int>()
        #expect(strategy.merge(base: ["a": 1], ours: ["a": 2], theirs: ["a": 3]) == nil)
        #expect(strategy.merge(base: ["a": 1], ours: ["a": 2], theirs: ["a": 2]) == ["a": 2])
        #expect(strategy.merge(base: ["a": 1, "b": 1], ours: ["b": 1], theirs: ["a": 1, "b": 2]) == ["b": 2])
        #expect(strategy.merge(base: ["a": 1], ours: [:], theirs: ["a": 2]) == nil)
    }
}
