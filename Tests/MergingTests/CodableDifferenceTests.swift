// Not `@testable`, so these tests only see the public surface.
import Foundation
import Merging
import Testing

@Suite struct CodableDifferenceTests {
    struct Person: Codable, Equatable {
        var name: String
        var age: Int
        var nickname: String?
        var tags: [String]
        var child: Child?
    }

    struct Child: Codable, Equatable {
        var grandchildren: [String]
    }

    let original = Person(name: "Ana", age: 30, nickname: "A", tags: ["a", "b"], child: Child(grandchildren: ["Ava", "Bo"]))
    let edited = Person(name: "Ana", age: 31, nickname: nil, tags: ["a", "b", "c"], child: Child(grandchildren: ["Eva", "Bo"]))

    @Test func listsChangesInPathOrder() throws {
        let difference = try CodableDifference(from: original, to: edited)
        #expect(Array(difference) == [
            .replace(path: "age", old: 30, new: 31),
            .replace(path: "child.grandchildren[0]", old: "Ava", new: "Eva"),
            .remove(path: "nickname", element: "A"),
            .insert(path: "tags[2]", element: "c"),
        ])
        #expect(difference.map(\.description) == [
            "~ age: 30 → 31",
            #"~ child.grandchildren[0]: "Ava" → "Eva""#,
            #"- nickname: "A""#,
            #"+ tags[2]: "c""#,
        ])
        #expect(difference.insertions.map(\.path) == ["tags[2]"])
        #expect(difference.removals.map(\.path) == ["nickname"])
        #expect(difference.replacements.count == 2)
        #expect(try CodableDifference(from: original, to: original).isEmpty)
    }

    @Test func appliesAndInverts() throws {
        let difference = try CodableDifference(from: original, to: edited)
        #expect(try original.applying(difference) == edited)
        #expect(try edited.applying(difference.inverse()) == original)
        #expect(difference.inverse().inverse() == difference)
    }

    @Test func appliesArraysThatGrowAndShrink() throws {
        let short = [1, 2]
        let long = [1, 5, 3, 4]
        let growing = try CodableDifference(from: short, to: long)
        #expect(growing.map(\.description) == ["~ [1]: 2 → 5", "+ [2]: 3", "+ [3]: 4"])
        #expect(try short.applying(growing) == long)
        #expect(try long.applying(growing.inverse()) == short)
        #expect(try long.applying(CodableDifference(from: long, to: short)) == short)
    }

    @Test func replacesAWholeValueAtTheRoot() throws {
        let difference = try CodableDifference(from: "x", to: "y")
        #expect(Array(difference) == [.replace(path: ".", old: "x", new: "y")])
        #expect(try "x".applying(difference) == "y")
    }

    @Test func applyingThrowsWhenTheResultDoesNotDecode() throws {
        let toText = try CodableDifference(from: "x", to: "y")
        #expect(throws: DecodingError.self) { try 2.applying(toText) }
    }

    @Test func pathsReadAsStrings() {
        let path: CodableDifference.Path = "items[0].title"
        #expect(path.components == [.key("items"), .index(0), .key("title")])
        #expect(path == ["items", 0, "title"])
        #expect(path.description == "items[0].title")
        #expect(("[2][1]" as CodableDifference.Path).components == [.index(2), .index(1)])
        #expect(("." as CodableDifference.Path).components.isEmpty)
        #expect((["config", "v1.2"] as CodableDifference.Path).components == [.key("config"), .key("v1.2")])
    }

    @Test func travelsAsJSON() throws {
        let difference = try CodableDifference(from: original, to: edited)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(difference)
        let received = try JSONDecoder().decode(CodableDifference.self, from: data)
        #expect(received == difference)
        #expect(try original.applying(received) == edited)

        let small = try CodableDifference(from: [1, 2], to: [1, 3, 4])
        #expect(String(decoding: try encoder.encode(small), as: UTF8.self)
            == #"[{"replace":{"new":3,"old":2,"path":[1]}},{"insert":{"element":4,"path":[2]}}]"#)
    }

    @Test func pathsAndValuesEncodeAsPlainJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let path: CodableDifference.Path = ["config", "v1.2", 0]
        #expect(String(decoding: try encoder.encode(path), as: UTF8.self) == #"["config","v1.2",0]"#)
        #expect(try JSONDecoder().decode(CodableDifference.Path.self, from: encoder.encode(path)) == path)

        let value: CodableValue = ["name": "Ana", "tags": ["a", nil], "age": 30, "ratio": 0.5, "on": true]
        #expect(String(decoding: try encoder.encode(value), as: UTF8.self)
            == #"{"age":30,"name":"Ana","on":true,"ratio":0.5,"tags":["a",null]}"#)
        #expect(try JSONDecoder().decode(CodableValue.self, from: encoder.encode(value)) == value)
    }
}
