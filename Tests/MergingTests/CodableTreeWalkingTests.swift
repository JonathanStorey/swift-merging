@testable import Merging
import Testing

@Suite struct CodableTreeWalkingTests {
    let tree: CodableTree = [
        "name": "Ana",
        "address": ["city": "Oslo", "street": "Elm"],
        "tags": ["a", "b"],
    ]

    @Test func subscriptsEditInPlace() {
        var tree = tree
        tree["address"]?["city"] = "Bergen"
        tree["tags"]?[0] = "z"
        tree["tags"]?[1] = nil
        tree["name"] = nil
        tree["age"] = 31
        tree["tags"]?[9] = "ignored"
        tree["age"]?["ignored"] = 1
        #expect(tree == ["address": ["city": "Bergen", "street": "Elm"], "tags": ["z"], "age": 31])
    }

    @Test func childrenAreDirectNodesInKeyOrder() {
        #expect(tree.children.count == 3)
        #expect(tree.children.first == ["city": "Oslo", "street": "Elm"])
        #expect(tree["tags"]?.children == ["a", "b"])
        #expect(tree["name"]?.children == [])
    }

    @Test func pathsReadAndWrite() {
        var tree = tree
        #expect(tree[["address", "city"]] == "Oslo")
        #expect(tree[["tags", 1]] == "b")
        #expect(tree[["tags", 5]] == nil)
        #expect(tree[.root] == tree)
        tree[["address", "city"]] = "Bergen"
        tree[["missing", "deep"]] = 1
        #expect(tree["address"]?["city"] == "Bergen")
        #expect(tree["missing"] == nil)
        #expect((["items", 0, "title"] as CodableTree.Path).description == "items[0].title")
        #expect(CodableTree.Path.root.description == ".")
    }

    @Test func forEachVisitsEveryNodeDepthFirst() {
        var visited: [String] = []
        tree.forEach { path, _ in visited.append(path.description) }
        #expect(visited == [".", "address", "address.city", "address.street", "name", "tags", "tags[0]", "tags[1]"])
    }

    @Test func differenceListsWhatChanged() throws {
        struct Person: Codable {
            var name: String
            var age: Int
            var nickname: String?
            var tags: [String]
        }
        let original = try CodableTree(encoding: Person(name: "Ana", age: 30, nickname: "A", tags: ["a", "b"]))
        let edited = try CodableTree(encoding: Person(name: "Ana", age: 31, nickname: nil, tags: ["a", "b", "c"]))
        let changes = edited.difference(from: original)
        #expect(changes == [
            .changed(["age"], from: 30, to: 31),
            .removed(["nickname"], "A"),
            .added(["tags", 2], "c"),
        ])
        #expect(changes.map(\.description) == [#"~ age: 30 → 31"#, #"- nickname: "A""#, #"+ tags[2]: "c""#])
        #expect(edited.difference(from: edited).isEmpty)
        #expect(CodableTree.int(1).difference(from: "x") == [.changed(.root, from: "x", to: 1)])
    }
}
