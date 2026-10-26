/// A type that declares how its values merge, used wherever a value of it is merged without a strategy
/// of its own, such as a nested struct stored in a property.
///
/// ```swift
/// extension Address: Mergeable {
///     static var mergeStrategy: AddressMerge { AddressMerge() }
/// }
/// ```
public protocol Mergeable: Sendable {
    associatedtype Strategy: MergeStrategy where Strategy.Value == Self
    static var mergeStrategy: Strategy { get }
}
