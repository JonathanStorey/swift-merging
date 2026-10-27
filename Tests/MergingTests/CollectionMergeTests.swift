@testable import Merging
import Testing

struct Spot: Codable, Hashable {
    var x: Int
    var y: Int
}

struct Shipping: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int
    static let fast = Shipping(rawValue: 1)
    static let gift = Shipping(rawValue: 2)
    static let signed = Shipping(rawValue: 4)
}

struct Board: Codable, Equatable, Mergeable {
    var tags: Set<String> = ["a", "b", "c"]
    var pins: [Spot: String] = [Spot(x: 0, y: 0): "home"]
    var counts: [String: Int] = ["a": 1]
    var players: [String: Player] = [:]
}

@Suite struct CollectionMergeTests {
    let base = Board()

    @Test func aSetKeepsAdditionsAndRemovalsFromBothSides() throws {
        var ours = base
        ours.tags.insert("ours")
        ours.tags.remove("a")
        var theirs = base
        theirs.tags.insert("theirs")
        theirs.tags.remove("b")
        #expect(try ours.merging(theirs, base: base).tags == ["c", "ours", "theirs"])
    }

    @Test func manySetsMergeWhateverTheirOrder() throws {
        // Large sets encode in an order that varies between instances.
        let big = Set((0..<200).map(String.init))
        let start = Board(tags: big)
        var ours = start
        ours.tags.insert("x")
        var theirs = start
        theirs.tags.remove("7")
        #expect(try ours.merging(theirs, base: start).tags == big.subtracting(["7"]).union(["x"]))
    }

    @Test func aDictionaryWithStructKeysMergesByKey() throws {
        var ours = base
        ours.pins[Spot(x: 1, y: 1)] = "ours"
        var theirs = base
        theirs.pins[Spot(x: 0, y: 0)] = "start"
        theirs.pins[Spot(x: 2, y: 2)] = "theirs"
        #expect(try ours.merging(theirs, base: base).pins == [
            Spot(x: 0, y: 0): "start", Spot(x: 1, y: 1): "ours", Spot(x: 2, y: 2): "theirs",
        ])
    }

    @Test func aDictionaryKeyBothChangedIsAConflict() {
        var ours = base
        ours.counts["a"] = 2
        var theirs = base
        theirs.counts["a"] = 3
        #expect(throws: MergeConflict<Board>.self) { try ours.merging(theirs, base: base) }
    }

    @Test func dictionaryValuesUseTheirOwnMerge() throws {
        let player = Player(id: 1, name: "Ana", highScore: 10)
        let start = Board(players: ["ana": player])
        var ours = start
        ours.players["ana"]!.highScore = 30
        var theirs = start
        theirs.players["ana"]!.highScore = 20
        theirs.players["ana"]!.name = "Ana B"
        let merged = try ours.merging(theirs, base: start).players["ana"]
        #expect(merged?.highScore == 30)
        #expect(merged?.name == "Ana B")
    }

    @Test func twoWayAcceptsEqualSetsInAnyOrder() throws {
        let board = Board(tags: Set((0..<200).map(String.init)))
        #expect(try board.merging(Board(tags: Set((0..<200).map(String.init)))) == board)
    }

    @Test func canonicalTextSortsKeys() {
        let one = MergeTree.object(["b": .int(1), "a": .string("x")])
        #expect(one.canonical == #"{"a":"x","b":i1}"#)
    }
}

@Suite struct CollectionStrategyTests {
    struct Note: Codable, Equatable, Mergeable {
        @Merged(.byMembership) var tags: Set<String> = ["a", "b", "c"]
        @Merged(.byMembership) var shipping: Shipping = [.fast]
        @Merged(.byKey) var scores: [Spot: Int] = [Spot(x: 0, y: 0): 1]
    }

    @Test func setsMergeByMembership() throws {
        var ours = Note()
        ours.tags = ["c", "a", "ours"]
        ours.shipping = [.fast, .gift]
        var theirs = Note()
        theirs.tags = ["b", "a", "theirs"]
        theirs.shipping = [.signed]
        let merged = try ours.merging(theirs, base: Note())
        #expect(merged.tags == ["a", "ours", "theirs"])
        #expect(merged.shipping == [.gift, .signed])
    }

    @Test func aDictionaryMergesByKeyWhenNamed() throws {
        var ours = Note()
        ours.scores[Spot(x: 1, y: 1)] = 2
        var theirs = Note()
        theirs.scores[Spot(x: 0, y: 0)] = 5
        #expect(try ours.merging(theirs, base: Note()).scores == [Spot(x: 0, y: 0): 5, Spot(x: 1, y: 1): 2])
    }
}

@Suite struct UnionMergeTests {
    struct Mail: Codable, Equatable, Mergeable {
        @Merged(.union) var recipients: Set<String> = ["ana", "bo"]
        @Merged(.union) var labels: Set<String> = ["inbox"]
    }

    @Test func withoutABaseNothingIsLost() throws {
        var ours = Mail()
        ours.recipients = ["ana", "cy"]
        ours.labels = ["inbox", "work"]
        var theirs = Mail()
        theirs.recipients = ["bo", "di", "ana"]
        theirs.labels = ["home"]
        let merged = try ours.merging(theirs)
        #expect(merged.recipients == ["ana", "cy", "bo", "di"])
        #expect(merged.labels == ["inbox", "work", "home"])
    }

    @Test func withABaseRemovalsStick() throws {
        var ours = Mail()
        ours.recipients = ["ana"]
        var theirs = Mail()
        theirs.recipients = ["ana", "bo", "cy"]
        #expect(try ours.merging(theirs, base: Mail()).recipients == ["ana", "cy"])
    }
}
