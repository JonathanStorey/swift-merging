import Foundation
import Merging
import Testing

/// A typed strategy: keeps the larger value by the type's own `<`, with or without a base.
struct Larger<Value: Comparable & Sendable>: MergeStrategy {
    func merge(base: Value, ours: Value, theirs: Value) -> Value { max(ours, theirs) }
    func merge(ours: Value, theirs: Value) -> Value { max(ours, theirs) }
}

/// Adds both sides' changes, which needs the base.
struct CounterMerge: MergeStrategy {
    typealias Value = Int

    func merge(base: Int, ours: Int, theirs: Int) -> Int { ours + theirs - base }
}

struct Address: Codable, Equatable, Mergeable {
    var street = ""
    var city = ""
}

/// Merges as a whole: a confirmed booking wins.
struct Booking: Codable, Equatable, Mergeable {
    var note = ""
    var confirmed = false

    func merging(_ theirs: Booking, base: Booking) -> Booking {
        confirmed ? self : theirs
    }
}

struct Player: Codable, Equatable, Mergeable {
    let id: Int
    var name = ""
    var address = Address()
    var booking = Booking()
    @Merged(Larger()) var highScore = 0
    @Merged(CounterMerge()) var wins = 0
}

@Suite struct MergeableTests {
    let base = Player(id: 1, name: "Ana", address: Address(street: "Elm", city: "Oslo"), highScore: 10, wins: 3)

    @Test func eachPropertyKeepsTheSideThatChanged() throws {
        var ours = base
        ours.name = "Ana B"
        var theirs = base
        theirs.address.city = "Bergen"
        let merged = try ours.merging(theirs, base: base)
        #expect(merged.name == "Ana B")
        #expect(merged.address == Address(street: "Elm", city: "Bergen"))
    }

    @Test func aStrategyDecidesWhenBothChanged() throws {
        var ours = base
        ours.highScore = 30
        ours.wins = 5
        var theirs = base
        theirs.highScore = 20
        theirs.wins = 4
        let merged = try ours.merging(theirs, base: base)
        #expect(merged.highScore == 30)
        #expect(merged.wins == 6)
    }

    @Test func aNestedMergeableUsesItsOwnMerge() throws {
        var ours = base
        ours.booking = Booking(note: "mine")
        var theirs = base
        theirs.booking = Booking(note: "theirs", confirmed: true)
        #expect(try ours.merging(theirs, base: base).booking == Booking(note: "theirs", confirmed: true))
    }

    @Test func aPropertyBothChangedMakesTheValueAConflict() {
        var ours = base
        ours.name = "Ana B"
        var theirs = base
        theirs.name = "Ana C"
        do {
            _ = try ours.merging(theirs, base: base)
            Issue.record("Expected a conflict")
        } catch {
            #expect(error.base?.name == "Ana")
            #expect(error.ours.name == "Ana B")
            #expect(error.theirs.name == "Ana C")
        }
    }

    @Test func twoWayMergesWhatsEqualAndWhatsStrategyAllows() throws {
        var theirs = base
        theirs.highScore = 50
        #expect(try base.merging(theirs).highScore == 50)
        theirs.wins = 9
        #expect(throws: MergeConflict<Player>.self) { try base.merging(theirs) }
    }

    @Test func aHandWrittenMergeThrowsWithoutABase() {
        #expect(throws: MergeConflict<Booking>.self) { try Booking().merging(Booking(note: "x")) }
    }

    @Test func mutatingAndStaticMergesMatch() throws {
        var ours = base
        ours.name = "Ana B"
        var theirs = base
        theirs.address.city = "Bergen"
        let merged = try Player.merge(base: base, ours: ours, theirs: theirs)
        try ours.merge(theirs, base: base)
        #expect(ours == merged)
    }

    @Test func aConflictLeavesTheValueUnchanged() {
        var ours = base
        ours.name = "Ana B"
        let before = ours
        var theirs = base
        theirs.name = "Ana C"
        #expect(throws: MergeConflict<Player>.self) { try ours.merge(theirs, base: base) }
        #expect(ours == before)
    }

    @Test func theWrapperEncodesAsItsBareValue() throws {
        let data = try JSONEncoder().encode(base)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["highScore"] as? Int == 10)
        #expect(try JSONDecoder().decode(Player.self, from: data) == base)
    }
}
