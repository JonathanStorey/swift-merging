import Foundation
import Testing
@testable import Merging

private struct Settings: Codable, Equatable, Sendable {
    enum Theme: String, Codable, Sendable { case light, dark }

    var theme = Theme.light
    var nickname: String? = nil
    var limits: [String: Int] = [:]
}

private struct Holder: Codable, Equatable, Mergeable {
    @Merged(.json(Settings.self)) var json = JSONDataMerge<Settings>.encode(Settings())
}

@Suite struct JSONDataMergeTests {
    typealias JSON = JSONDataMerge<Settings>

    @Test func editsToDifferentPartsCombine() throws {
        let base = Settings(limits: ["a": 1])
        var ours = base
        ours.theme = .dark
        ours.nickname = "me"
        var theirs = base
        theirs.limits["b"] = 2
        let merged = try #require(JSON().merge(base: JSON.encode(base), ours: JSON.encode(ours), theirs: JSON.encode(theirs)))
        #expect(JSON.decode(merged) == Settings(theme: .dark, nickname: "me", limits: ["a": 1, "b": 2]))
    }

    @Test func bothChangingOneFieldIsAConflict() {
        let base = Settings()
        let ours = Settings(nickname: "mine")
        let theirs = Settings(nickname: "theirs")
        #expect(JSON().merge(base: JSON.encode(base), ours: JSON.encode(ours), theirs: JSON.encode(theirs)) == nil)
    }

    @Test func dataThatDoesNotDecodeIsAConflict() {
        let good = JSON.encode(Settings())
        #expect(JSON().merge(base: good, ours: Data("nope".utf8), theirs: good) == nil)
    }

    @Test func equalValuesEncodeToEqualBytes() {
        let one = Settings(limits: ["a": 1, "b": 2, "c": 3, "d": 4])
        let two = Settings(limits: ["d": 4, "c": 3, "b": 2, "a": 1])
        #expect(JSON.encode(one) == JSON.encode(two))
    }

    @Test func worksThroughMerged() throws {
        let base = Holder()
        var ours = base
        ours.json = JSON.encode(Settings(theme: .dark))
        var theirs = base
        theirs.json = JSON.encode(Settings(limits: ["x": 9]))
        let merged = try #require(ours.merging(with: theirs, from: base))
        #expect(JSON.decode(merged.json) == Settings(theme: .dark, limits: ["x": 9]))
    }
}
