import Foundation
import Merging
import Testing

/// Keeps the longer title, a strategy of the caller's own that needs a base.
struct LongerMerge: MergeStrategy {
    func merge(base: String, ours: String, theirs: String) -> String? {
        ours.count >= theirs.count ? ours : theirs
    }
}

/// Adds both sides' changes, so equal changes still count twice.
struct AddMerge: MergeStrategy {
    func merge(base: Int, ours: Int, theirs: Int) -> Int? {
        ours + theirs - base
    }
}

struct Profile: Codable, Equatable {
    @Merged(.keep(.ours)) var nickname = ""
    @Merged(.keep(.theirs)) var cachedTotal = 0
    @Merged(LongerMerge()) var title: String = ""
    @Merged(AddMerge()) var likes = 0
    @Merged(.keep(.ours)) var tags: [String] = []
    @Merged(.keep(.theirs)) var note: String? = nil
    var plain = ""
}

final class Draft {
    @Merged(.keep(.ours)) var text = ""
    @Merged(.keep(.theirs)) nonisolated(unsafe) static var shared = ""
}

@Suite struct MergedTests {
    let base = Profile(nickname: "ann", cachedTotal: 1, title: "Hi", likes: 0, tags: ["a"], note: nil)

    @Test func keepTakesTheNamedSideWhenBothChanged() {
        let ours = Profile(nickname: "annie", cachedTotal: 2, tags: ["a", "b"], note: "mine")
        let theirs = Profile(nickname: "anna", cachedTotal: 3, tags: ["c"], note: "theirs")
        #expect(ours.$nickname.merging(with: theirs.nickname, from: base.nickname) == "annie")
        #expect(ours.$cachedTotal.merging(with: theirs.cachedTotal, from: base.cachedTotal) == 3)
        #expect(ours.$tags.merging(with: theirs.tags, from: base.tags) == ["a", "b"])
        #expect(ours.$note.merging(with: theirs.note, from: base.note) == "theirs")
        // An optional property's base is the property's own type, so a `nil` base is a value, not "no base".
        #expect(Profile(note: "mine").$note.merging(with: nil, from: nil) == "mine")
    }

    @Test func aSideOnlyOneChangedKeepsThatSide() {
        let ours = base
        var theirs = base
        theirs.nickname = "anna"
        #expect(ours.$nickname.merging(with: theirs.nickname, from: base.nickname) == "anna")
        #expect(theirs.$cachedTotal.merging(with: 7, from: base.cachedTotal) == 7)
        #expect(theirs.$cachedTotal.merging(with: base.cachedTotal, from: base.cachedTotal) == base.cachedTotal)
    }

    @Test func aStrategyOfYourOwnDecides() {
        let ours = Profile(title: "Hello there")
        #expect(ours.$title.merging(with: "Hey", from: base.title) == "Hello there")
        #expect(Profile(title: "Yo").$title.merging(with: "Hey", from: base.title) == "Hey")
    }

    @Test func equalChangesStillGoToTheStrategy() {
        let ours = Profile(likes: 1)
        #expect(ours.$likes.merging(with: 1, from: 0) == 2)
    }

    @Test func withoutABase() {
        let ours = Profile(nickname: "annie", title: "Hello")
        #expect(ours.$nickname.merging(with: "anna") == "annie")
        // A strategy that needs a base merges only equal values without one.
        #expect(ours.$title.merging(with: "Hello") == "Hello")
        #expect(ours.$title.merging(with: "Hey") == nil)
    }

    @Test func worksInAClassAndOnAStaticProperty() {
        let draft = Draft()
        draft.text = "mine"
        #expect(draft.$text.merging(with: "theirs", from: "") == "mine")
        Draft.shared = "ours"
        #expect(Draft.$shared.merging(with: "theirs", from: "") == "theirs")
    }

    @Test func storesOnlyTheProperty() throws {
        let profile = Profile(nickname: "ann", likes: 3)
        let data = try JSONEncoder().encode(profile)
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys) == ["nickname", "cachedTotal", "title", "likes", "tags", "plain"])
        #expect(try JSONDecoder().decode(Profile.self, from: data) == profile)
    }
}

@Suite struct MergedPropertyTests {
    /// A value that isn't `Equatable`, so the strategy decides every merge.
    struct Blob: Sendable {
        var bytes: [UInt8]
    }

    @Test func aValueThatIsNotEquatableAlwaysGoesToTheStrategy() {
        let ours = Blob(bytes: [1])
        let merged = MergedProperty(ours, KeepMerge(.theirs)).merging(with: Blob(bytes: [1]), from: Blob(bytes: [2]))
        #expect(merged?.bytes == [1])
        let kept = MergedProperty(ours, KeepMerge(.ours)).merging(with: Blob(bytes: [3]), from: ours)
        #expect(kept?.bytes == [1])
    }

    @Test func aStrategyMergesDirectly() {
        #expect(KeepMerge<Int>(.ours).merge(base: 0, ours: 1, theirs: 2) == 1)
        #expect(KeepMerge<Int>(.theirs).merge(ours: 1, theirs: 2) == 2)
        #expect(LongerMerge().merge(ours: "a", theirs: "b") == nil)
    }
}
