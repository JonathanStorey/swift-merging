import Merging
import Testing

/// Keeps the larger value, whatever the base.
struct MaxMerge<Value: Comparable & Sendable>: MergeStrategy {
    func merge(ours: Value, theirs: Value) -> Value { max(ours, theirs) }
}

@Mergeable
struct Address: Equatable {
    var street = ""
    var city = ""
}

@Mergeable
struct Player {
    let id: Int
    var name = ""
    var address = Address()
    @Merged(MaxMerge<Int>()) var highScore = 0
}

@Suite struct MergeableTests {
    let base = Player(id: 1, name: "Ana", address: Address(street: "Elm", city: "Oslo"), highScore: 10)

    @Test func eachPropertyKeepsTheSideThatChanged() throws {
        var ours = base
        ours.name = "Ana B"
        var theirs = base
        theirs.address.city = "Bergen"
        let merged = try Player.merge(base: base, ours: ours, theirs: theirs)
        #expect(merged.name == "Ana B")
        #expect(merged.address == Address(street: "Elm", city: "Bergen"))
    }

    @Test func aNestedMergeableMergesByItsOwnProperties() throws {
        var ours = base
        ours.address.street = "Oak"
        var theirs = base
        theirs.address.city = "Bergen"
        #expect(try Player.merge(base: base, ours: ours, theirs: theirs).address == Address(street: "Oak", city: "Bergen"))
    }

    @Test func aMergedStrategyDecidesItsProperty() throws {
        var ours = base
        ours.highScore = 30
        var theirs = base
        theirs.highScore = 20
        #expect(try Player.merge(base: base, ours: ours, theirs: theirs).highScore == 30)
        #expect(try Player.merge(ours: theirs, theirs: ours).highScore == 30)
    }

    @Test func aPropertyBothChangedMakesTheValueAConflict() {
        var ours = base
        ours.name = "Ana B"
        var theirs = base
        theirs.name = "Ana C"
        do {
            _ = try Player.merge(base: base, ours: ours, theirs: theirs)
            Issue.record("Expected a conflict")
        } catch {
            #expect(error.base?.name == "Ana")
            #expect(error.ours.name == "Ana B")
            #expect(error.theirs.name == "Ana C")
        }
    }

    @Test func twoWayMergesOnlyWhatsEqual() throws {
        var theirs = base
        theirs.highScore = 50
        #expect(try Player.merge(ours: base, theirs: theirs).highScore == 50)
        theirs.name = "Other"
        #expect(throws: MergeConflict<Player>.self) { try Player.merge(ours: base, theirs: theirs) }
    }
}

/// A type that writes its own merge, and settles only what merging its properties couldn't.
@Mergeable
struct Booking {
    var note = ""
    var confirmed = false

    static func merge(base: Booking, ours: Booking, theirs: Booking) throws(MergeConflict<Booking>) -> Booking {
        do {
            return try mergeProperties(base: base, ours: ours, theirs: theirs)
        } catch {
            return ours.confirmed ? ours : theirs
        }
    }
}

@Suite struct CustomMergeTests {
    @Test func aConfirmedBookingWinsAClash() throws {
        let base = Booking(note: "a")
        let ours = Booking(note: "b", confirmed: false)
        let theirs = Booking(note: "c", confirmed: true)
        #expect(try Booking.merge(base: base, ours: ours, theirs: theirs).note == "c")
    }
}
