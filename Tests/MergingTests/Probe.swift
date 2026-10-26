@testable import Merging

enum MergeKindProbe {
    static func words(_ text: String) -> [String] { MergeKind.Text.words(of: text) }
}
