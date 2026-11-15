@testable import Merging
import Testing

@Suite struct CodableValueWalkingTests {
    let tree: CodableValue = [
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
        #expect((["items", 0, "title"] as CodableDifference.Path).description == "items[0].title")
        #expect(CodableDifference.Path.root.description == ".")
    }

    @Test func forEachVisitsEveryNodeDepthFirst() {
        var visited: [String] = []
        tree.forEach { path, _ in visited.append(path.description) }
        #expect(visited == [".", "address", "address.city", "address.street", "name", "tags", "tags[0]", "tags[1]"])
    }
}
