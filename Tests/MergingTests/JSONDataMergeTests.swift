import Foundation
import Testing
@testable import Merging

struct JSONSettings: Codable, Equatable, Sendable {
    enum Theme: String, Codable, Sendable { case light, dark }

    var theme = Theme.light
    var nickname: String? = nil
    var limits: [String: Int] = [:]
}

struct JSONHolder: Codable, Equatable, Mergeable {
    @Merged(.json(JSONSettings.self)) var json = JSONDataMerge<JSONSettings>.encode(JSONSettings())
}

@Suite struct JSONDataMergeTests {
    typealias JSON = JSONDataMerge<JSONSettings>

    @Test func editsToDifferentPartsCombine() throws {
        let base = JSONSettings(limits: ["a": 1])
        var ours = base
        ours.theme = .dark
        ours.nickname = "me"
        var theirs = base
        theirs.limits["b"] = 2
        let merged = try #require(JSON().merge(base: JSON.encode(base), ours: JSON.encode(ours), theirs: JSON.encode(theirs)))
        #expect(JSON.decode(merged) == JSONSettings(theme: .dark, nickname: "me", limits: ["a": 1, "b": 2]))
    }

    @Test func bothChangingOneFieldIsAConflict() {
        let base = JSONSettings()
        let ours = JSONSettings(nickname: "mine")
        let theirs = JSONSettings(nickname: "theirs")
        #expect(JSON().merge(base: JSON.encode(base), ours: JSON.encode(ours), theirs: JSON.encode(theirs)) == nil)
    }

    @Test func dataThatDoesNotDecodeIsAConflict() {
        let good = JSON.encode(JSONSettings())
        #expect(JSON().merge(base: good, ours: Data("nope".utf8), theirs: good) == nil)
    }

    @Test func equalValuesEncodeToEqualBytes() {
        let one = JSONSettings(limits: ["a": 1, "b": 2, "c": 3, "d": 4])
        let two = JSONSettings(limits: ["d": 4, "c": 3, "b": 2, "a": 1])
        #expect(JSON.encode(one) == JSON.encode(two))
    }

    @Test func worksThroughMerged() throws {
        let base = JSONHolder()
        var ours = base
        ours.json = JSON.encode(JSONSettings(theme: .dark))
        var theirs = base
        theirs.json = JSON.encode(JSONSettings(limits: ["x": 9]))
        let merged = try #require(ours.merging(with: theirs, from: base))
        #expect(JSON.decode(merged.json) == JSONSettings(theme: .dark, limits: ["x": 9]))
    }
}
