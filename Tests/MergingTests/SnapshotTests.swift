import Foundation
@testable import Merging
import Testing

struct Item: Codable, Equatable {
    var title: String
    var done = false
}

enum Status: Codable, Equatable {
    case draft
    case scheduled(at: Date)
    case archived(reason: String)
}

struct Profile: Codable, Equatable, Mergeable {
    var name = "Ana"
    var age = 30
    var nickname: String?
    var tags = ["a", "b", "c"]
    var scores: [String: Double] = ["math": 1.5]
    var items = [Item(title: "One"), Item(title: "Two")]
    var status = Status.draft
    var big = UInt64.max
    var small: Int8 = -3
    var ratio: Float = 0.1
}

@Suite struct SnapshotCodingTests {
    @Test func aValueRoundTrips() throws {
        var profile = Profile()
        profile.nickname = "Annie"
        profile.status = .scheduled(at: Date(timeIntervalSinceReferenceDate: 1234.5))
        let snapshot = try SnapshotEncoder().encode(profile)
        #expect(try SnapshotDecoder().decode(Profile.self, from: snapshot) == profile)
    }

    @Test func aMissingOptionalIsLeftOut() throws {
        guard case .object(let object) = try SnapshotEncoder().encode(Profile()) else {
            Issue.record("Expected an object")
            return
        }
        #expect(object["nickname"] == nil)
        #expect(object["age"] == .int(30))
        #expect(object["big"] == .uint(.max))
    }

    @Test func aWrongTypeFailsToDecode() {
        #expect(throws: DecodingError.self) { try SnapshotDecoder().decode(Profile.self, from: .object(["name": .int(1)])) }
    }
}

@Suite struct CodableMergeTests {
    let base = Profile()

    @Test func differentFieldsMerge() throws {
        var ours = base
        ours.name = "Ana B"
        var theirs = base
        theirs.age = 31
        theirs.nickname = "Annie"
        let merged = try ours.merging(theirs, base: base)
        #expect(merged.name == "Ana B")
        #expect(merged.age == 31)
        #expect(merged.nickname == "Annie")
    }

    @Test func bothSidesAppendingKeepsBoth() throws {
        var ours = base
        ours.tags.append("ours")
        var theirs = base
        theirs.tags.append("theirs")
        #expect(try ours.merging(theirs, base: base).tags == ["a", "b", "c", "ours", "theirs"])
    }

    @Test func aRemovalAndAnInsertBothApply() throws {
        var ours = base
        ours.tags.removeAll { $0 == "b" }
        var theirs = base
        theirs.tags.insert("first", at: 0)
        #expect(try ours.merging(theirs, base: base).tags == ["first", "a", "c"])
    }

    @Test func editsToDifferentFieldsOfOneElementMerge() throws {
        var ours = base
        ours.items[1].title = "Second"
        var theirs = base
        theirs.items[1].done = true
        #expect(try ours.merging(theirs, base: base).items == [Item(title: "One"), Item(title: "Second", done: true)])
    }

    @Test func dictionariesMergeByKey() throws {
        var ours = base
        ours.scores["art"] = 2
        var theirs = base
        theirs.scores["math"] = 3
        #expect(try ours.merging(theirs, base: base).scores == ["math": 3, "art": 2])
    }

    @Test func bothChangingAFieldIsAConflict() {
        var ours = base
        ours.name = "Ana B"
        var theirs = base
        theirs.name = "Ana C"
        #expect(throws: MergeConflict<Profile>.self) { try ours.merging(theirs, base: base) }
    }

    @Test func aMergeThatWontDecodeIsAConflict() {
        var ours = base
        ours.status = .archived(reason: "Old")
        var theirs = base
        theirs.status = .scheduled(at: .distantFuture)
        #expect(throws: MergeConflict<Profile>.self) { try ours.merging(theirs, base: base) }
    }

    @Test func twoWayMergesOnlyEqualValues() throws {
        #expect(try base.merging(base) == base)
        var theirs = base
        theirs.age = 31
        #expect(throws: MergeConflict<Profile>.self) { try base.merging(theirs) }
    }

    @Test func aCodablePropertyOfAMergeableStructMergesByItsSnapshot() throws {
        var ours = Team()
        ours.lead.name = "Bo"
        var theirs = Team()
        theirs.lead.age = 40
        let merged = try ours.merging(theirs, base: Team())
        #expect(merged.lead.name == "Bo")
        #expect(merged.lead.age == 40)
    }
}

struct Team: Codable, Mergeable {
    var lead = Profile()
}

@Suite struct SnapshotArrayMergeTests {
    @Test func bothReplacingAnElementDifferentlyIsAConflictNamingIt() {
        let base = Snapshot.array([.string("a"), .string("b")])
        let ours = Snapshot.array([.string("a"), .string("x")])
        let theirs = Snapshot.array([.string("a"), .string("y")])
        do {
            _ = try ours.merging(theirs, base: base)
            Issue.record("Expected a conflict")
        } catch {
            #expect(error.base == .string("b"))
            #expect(error.ours == .string("x"))
            #expect(error.theirs == .string("y"))
        }
    }

    @Test func oneSideChangingAndTheOtherRemovingKeepsTheChange() throws {
        let base = Snapshot.array([.string("a"), .string("b"), .string("c")])
        let ours = Snapshot.array([.string("a"), .string("B"), .string("c")])
        let theirs = Snapshot.array([.string("a"), .string("c")])
        #expect(try ours.merging(theirs, base: base) == .array([.string("a"), .string("B"), .string("c")]))
    }
}

@Suite struct PublicSnapshotTests {
    struct Point: Codable, Equatable {
        var x: Int
        var y: Double
        var name: String?
    }

    @Test func aSnapshotShowsWhatItHolds() throws {
        let snapshot = try Snapshot(encoding: Point(x: 1, y: 2.5, name: "A"))
        #expect(snapshot["x"]?.int == 1)
        #expect(snapshot["y"]?.double == 2.5)
        #expect(snapshot["name"]?.string == "A")
        #expect(snapshot.description == #"{"name": "A", "x": 1, "y": 2.5}"#)
        #expect(try snapshot.decode(as: Point.self) == Point(x: 1, y: 2.5, name: "A"))
    }

    @Test func literalsBuildSnapshots() {
        let snapshot: Snapshot = ["tags": ["a", 1, 2.5, true, nil]]
        #expect(snapshot["tags"]?[1] == .int(1))
        #expect(snapshot["tags"]?[4]?.isNull == true)
        #expect(snapshot["missing"] == nil)
    }
}
