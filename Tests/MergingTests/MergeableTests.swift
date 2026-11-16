// Not `@testable`, so these tests only see the public surface.
import Merging
import Testing

@Suite struct MergeableTests {
    /// A counter that merges by adding both sides' changes.
    struct Tally: Mergeable, Equatable, Sendable {
        var count = 0

        func merging(with theirs: Tally, favoring side: MergeSide) throws -> Tally {
            side == .ours ? self : theirs
        }

        func merging(with theirs: Tally, from base: Tally, favoring side: MergeSide) throws -> Tally {
            Tally(count: count + theirs.count - base.count)
        }
    }

    struct Scoreboard {
        @Merged(.mergeable(favoring: .ours)) var tally: Tally = Tally()
    }

    struct Child: Codable, Equatable {
        var name: String
    }

    struct Note: Codable, Equatable, Sendable {
        var title = "A"
        var body = "x"
        var tags = ["a"]
        var nickname: String?
        var child: Child?
    }

    struct Bag: Codable, Equatable, Sendable {
        var items: Set<String>
    }

    let base = Note()

    @Test func twoFunctionsGiveSix() throws {
        var tally = Tally(count: 3)
        #expect(try tally.merging(with: Tally(count: 5), from: Tally(count: 1), favoring: .ours) == Tally(count: 7))
        #expect(try Tally.merge(base: Tally(count: 1), ours: tally, theirs: Tally(count: 5), favoring: .ours) == Tally(count: 7))
        #expect(try Tally.merge(ours: tally, theirs: Tally(count: 5), favoring: .theirs) == Tally(count: 5))
        try tally.merge(with: Tally(count: 5), from: Tally(count: 1), favoring: .ours)
        #expect(tally == Tally(count: 7))
        try tally.merge(with: Tally(count: 2), favoring: .theirs)
        #expect(tally == Tally(count: 2))
    }

    @Test func mergesThroughMerged() {
        let board = Scoreboard(tally: Tally(count: 3))
        #expect(board.$tally.merging(with: Tally(count: 5), from: Tally(count: 1)) == Tally(count: 7))
        #expect(board.$tally.merging(with: Tally(count: 5)) == Tally(count: 3))
    }

    @Test func followedBySquashesTwoDifferences() throws {
        let middle = Note(title: "B", tags: ["a", "b"])
        let end = Note(title: "C", body: "z")
        let squashed = try #require(try CodableDifference(from: base, to: middle).followed(by: CodableDifference(from: middle, to: end)))
        let direct = try CodableDifference(from: base, to: end)
        #expect(squashed == direct)
        #expect(try base.applying(squashed) == end)
    }

    @Test func followedByEditsInsideAndAround() throws {
        let added = Note(child: Child(name: "x"))
        let renamed = Note(child: Child(name: "y"))
        let inside = try #require(try CodableDifference(from: base, to: added).followed(by: CodableDifference(from: added, to: renamed)))
        let insideDirect = try CodableDifference(from: base, to: renamed)
        #expect(inside == insideDirect)

        let around = try #require(try CodableDifference(from: added, to: renamed).followed(by: CodableDifference(from: renamed, to: base)))
        let aroundDirect = try CodableDifference(from: added, to: base)
        #expect(around == aroundDirect)
    }

    @Test func followedByRefusesADifferenceThatCannotFollow() throws {
        let named = Note(nickname: "N")
        let clearing = try CodableDifference(from: named, to: base)
        #expect(clearing.followed(by: clearing) == nil)
    }
}
