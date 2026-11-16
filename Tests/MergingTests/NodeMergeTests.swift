@testable import Merging
import Testing

struct Place: Codable, Equatable {
    var street = "Elm"
    var city = "Oslo"
}

struct Contact: Codable, Equatable {
    var name = "Ann"
    var place = Place()
    var tags: Set<String> = ["family"]
    var notes: [String: String] = ["a": "1"]
    var pins: [Spot: String] = [Spot(x: 0, y: 0): "home"]
}

struct Trip {
    @Merged(.byNode) var place: Place = Place()
    @Merged(.total(favoring: .theirs)) var stop: Place = Place()
    @Merged(.total(favoring: .ours)) var home: Place = Place()
}

@Suite struct NodeMergeTests {
    let base = Contact()

    @Test func byNodeMergesAnyCodableRepresentation() {
        let trip = Trip(place: Place(street: "Oak"))
        #expect(trip.$place.merging(with: Place(city: "Bergen"), from: Place()) == Place(street: "Oak", city: "Bergen"))
        #expect(trip.$place.merging(with: Place(street: "Pine"), from: Place()) == nil)
    }

    @Test func aSetInsideMergesByMembership() {
        var ours = base
        ours.tags = ["family", "ours"]
        var theirs = base
        theirs.tags = ["theirs"]
        #expect(CodableNodeMerge<Contact>().merge(base: base, ours: ours, theirs: theirs)?.tags == ["ours", "theirs"])
    }

    @Test func manySetsMergeWhateverTheirOrder() {
        // Large sets encode in an order that varies between instances.
        let big = Set((0..<200).map(String.init))
        let start = Contact(tags: big)
        var ours = start
        ours.tags.insert("x")
        var theirs = start
        theirs.tags.remove("7")
        #expect(CodableNodeMerge<Contact>().merge(base: start, ours: ours, theirs: theirs)?.tags == big.subtracting(["7"]).union(["x"]))
        #expect(CodableNodeMerge<Contact>().merge(ours: Contact(tags: big), theirs: Contact(tags: Set(big))) == Contact(tags: big))
    }

    @Test func aDictionaryWithStructKeysMergesByKey() {
        var ours = base
        ours.pins[Spot(x: 1, y: 1)] = "ours"
        var theirs = base
        theirs.pins[Spot(x: 0, y: 0)] = "start"
        theirs.pins[Spot(x: 2, y: 2)] = "theirs"
        #expect(CodableNodeMerge<Contact>().merge(base: base, ours: ours, theirs: theirs)?.pins == [
            Spot(x: 0, y: 0): "start", Spot(x: 1, y: 1): "ours", Spot(x: 2, y: 2): "theirs",
        ])
    }

    @Test func totalKeepsTheFavoredSideAndTheRestStillMerges() {
        var ours = base
        ours.name = "Ann B."
        ours.place = Place(street: "Oak", city: "Bergen")
        var theirs = base
        theirs.name = "Anne"
        theirs.place.city = "Trondheim"
        theirs.tags.insert("work")
        #expect(CodableTotalMerge<Contact>(favoring: .theirs).merge(base: base, ours: ours, theirs: theirs)
            == Contact(name: "Anne", place: Place(street: "Oak", city: "Trondheim"), tags: ["family", "work"]))
        #expect(CodableTotalMerge<Contact>(favoring: .ours).merge(base: base, ours: ours, theirs: theirs)
            == Contact(name: "Ann B.", place: Place(street: "Oak", city: "Bergen"), tags: ["family", "work"]))
        #expect(CodableNodeMerge<Contact>().merge(base: base, ours: ours, theirs: theirs) == nil)
    }

    @Test func aKeyRemovedWhileTheOtherChangedItKeepsTheFavoredSide() {
        var ours = base
        ours.notes["a"] = nil
        var theirs = base
        theirs.notes["a"] = "2"
        #expect(CodableTotalMerge<Contact>(favoring: .ours).merge(base: base, ours: ours, theirs: theirs)?.notes == [:])
        #expect(CodableTotalMerge<Contact>(favoring: .theirs).merge(base: base, ours: ours, theirs: theirs)?.notes == ["a": "2"])
    }

    @Test func totalWithoutABaseKeepsTheFavoredSideOfEachDifference() {
        var ours = base
        ours.name = "Ann B."
        var theirs = base
        theirs.place.city = "Bergen"
        #expect(CodableTotalMerge<Contact>(favoring: .theirs).merge(ours: ours, theirs: theirs)
            == Contact(name: "Ann", place: Place(street: "Elm", city: "Bergen")))
    }

    @Test func totalShorthandTakesItsSide() {
        let trip = Trip(stop: Place(street: "Oak", city: "Bergen"), home: Place(street: "Oak", city: "Bergen"))
        let theirs = Place(city: "Trondheim")
        #expect(trip.$stop.merging(with: theirs, from: Place()) == Place(street: "Oak", city: "Trondheim"))
        #expect(trip.$home.merging(with: theirs, from: Place()) == Place(street: "Oak", city: "Bergen"))
    }

    @Test func canonicalTextSortsKeys() {
        let one = MergeTree.object(["b": .integer(1), "a": .string("x")])
        #expect(one.canonical == #"{"a":"x","b":i1}"#)
    }
}
