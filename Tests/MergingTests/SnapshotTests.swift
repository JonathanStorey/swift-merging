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

@Mergeable
struct Team {
    var lead = Profile()
}

@Suite struct SnapshotArrayMergeTests {
    @Test func bothReplacingAnElementDifferentlyIsAConflict() {
        let base = Snapshot.array([.string("a"), .string("b")])
        let ours = Snapshot.array([.string("a"), .string("x")])
        let theirs = Snapshot.array([.string("a"), .string("y")])
        #expect(throws: SnapshotConflict.self) { try ours.merging(theirs, base: base) }
    }

    @Test func oneSideChangingAndTheOtherRemovingKeepsTheChange() throws {
        let base = Snapshot.array([.string("a"), .string("b"), .string("c")])
        let ours = Snapshot.array([.string("a"), .string("B"), .string("c")])
        let theirs = Snapshot.array([.string("a"), .string("c")])
        #expect(try ours.merging(theirs, base: base) == .array([.string("a"), .string("B"), .string("c")]))
    }
}
