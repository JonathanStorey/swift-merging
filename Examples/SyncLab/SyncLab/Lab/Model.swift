import Foundation
import MergingSwiftData
import SwiftData

/// A Codable value with a bit of everything SwiftData stores in its own way: a nested struct, a dictionary,
/// and an array of structs.
///
/// SwiftData on iOS 18.6 stops the app, as soon as a store opens, when a Codable property's struct holds
/// either of two things, so this one holds neither:
/// - an optional, such as `String?`: "Failed to materialize a keypath for spec.caption"
/// - an enum, even a plain `String` raw-value one: "Failed to validate spec.shape.shape because shape is not
///   a member of Shape"
struct Spec: Codable, Equatable, Sendable {
    struct Size: Codable, Equatable, Sendable {
        var width = 1.0
        var height = 1.0
    }

    struct Point: Codable, Equatable, Sendable {
        var x = 0
        var y = 0
    }

    var size = Size()
    var shape = "circle"
    var options: [String: Int] = [:]
    var points: [Point] = []
    var caption = ""
}

/// The object every test edits. Each kind of data the lab checks has its own property, and every property
/// has a default, as CloudKit requires.
@Model @MergeableModel
final class Item {
    /// Finds the same item in every store, since each store gives it its own identifier.
    var key: String = ""
    @Merge(.byWord) var title: String = ""
    @Merge(.byElement) var steps: [String] = []
    @Merge(.byNode) var spec: Spec = Spec()
    @Merge(.byMembership) @Relationship(deleteRule: .nullify, inverse: \Tag.items) var labels: [Tag]? = []
    @Merge(.keep(.theirs)) @Attribute(.externalStorage) var blob: Data? = nil

    init(key: String) {
        self.key = key
    }
}

@Model
final class Tag {
    var name: String = ""
    var items: [Item]? = []

    init(name: String) {
        self.name = name
    }
}

enum LabSchema {
    static var schema: Schema { Schema([Item.self, Tag.self]) }
}
