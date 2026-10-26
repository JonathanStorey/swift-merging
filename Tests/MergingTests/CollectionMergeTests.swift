@testable import Merging
import Testing

struct Spot: Codable, Hashable {
    var x: Int
    var y: Int
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
        let one = Snapshot.object(["b": .int(1), "a": .string("x")])
        #expect(one.canonical == #"{"a":"x","b":i1}"#)
    }
}
