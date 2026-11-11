import Foundation
import MergingSwiftData
import SwiftData

/// A point, as both Codable values hold a list of them.
struct Point: Codable, Equatable, Sendable {
    var x = 0
    var y = 0
}

/// A width and height, as both Codable values hold one.
struct Size: Codable, Equatable, Sendable {
    var width = 1.0
    var height = 1.0
}

/// A Codable value stored as itself, which SwiftData does as a composite attribute: one column per field.
///
/// SwiftData on iOS 18.6 stops the app when such a struct holds either of two things, so this one holds
/// neither:
/// - an optional, such as `String?`: "Failed to materialize a keypath for layout.caption"
/// - an enum, even a plain `String` raw-value one: "Failed to validate layout.shape.shape because shape is
///   not a member of Shape"
///
/// The first is a known bug in reading the store's history, which merging relies on
/// (https://developer.apple.com/forums/thread/784036).
struct Layout: Codable, Equatable, Sendable {
    var size = Size()
    var options: [String: Int] = [:]
    var points: [Point] = []
    var caption = ""
}

/// A Codable value stored as JSON `Data`, so it can hold what `Layout` can't: an optional and an enum.
struct Spec: Codable, Equatable, Sendable {
    enum Shape: String, Codable, Sendable {
        case circle, square, star
    }

    var size = Size()
    var shape = Shape.circle
    var options: [String: Int] = [:]
    var points: [Point] = []
    var caption: String? = nil
}

/// The object every test edits. Each kind of data the lab checks has its own property, and every property
/// has a default, as CloudKit requires.
@Model @MergeableModel
final class Item {
    /// Finds the same item in every store, since each store gives it its own identifier.
    var key: String = ""
    @Merge(.byWord) var title: String = ""
    @Merge(.byElement) var steps: [String] = []
    @Merge(.byNode) var layout: Layout = Layout()
    @Merge(.json(Spec.self)) var specJSON: Data = Data()
    @Merge(.byMembership) @Relationship(deleteRule: .nullify, inverse: \Tag.items) var labels: [Tag]? = []
    @Merge(.keep(.theirs)) @Attribute(.externalStorage) var blob: Data? = nil

    /// The JSON, decoded. Set it to write new JSON.
    var spec: Spec {
        get { JSONDataMerge<Spec>.decode(specJSON) ?? Spec() }
        set { specJSON = JSONDataMerge<Spec>.encode(newValue) }
    }

    init(key: String) {
        self.key = key
        specJSON = JSONDataMerge<Spec>.encode(Spec())
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
