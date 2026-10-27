/// Merges text word by word, so edits to different words combine and edits to the same word conflict.
/// Needs a base.
///
/// ```swift
/// @Merged(.byWord) var note = ""
/// ```
public struct StringWordMerge<Value: StringProtocol & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        func words(_ text: Value) -> CodableTree { .array(Self.words(String(text)).map(CodableTree.string)) }
        do {
            let merged = try words(ours).merging(with: words(theirs), from: words(base))
            let text = merged.children.compactMap(\.string).joined()
            return Value(decoding: text.utf8, as: UTF8.self)
        } catch {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    /// The text as words, each a run of letters, digits, and apostrophes with the spaces and punctuation
    /// after it, so joining them gives back the text. Anything before the first word is one of its own. The
    /// rule is simple and the same everywhere, since both sides of a merge must cut text alike.
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var word = ""
        var inSeparator = false
        for character in text {
            let isWord = character.isLetter || character.isNumber || character == "'" || character == "’"
            if isWord, inSeparator, !word.isEmpty {
                words.append(word)
                word = ""
            }
            inSeparator = !isWord
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        return words
    }
}

// Only `String` is `Codable`, so it's the one `StringProtocol` type a property can be.
extension MergeStrategy where Self == StringWordMerge<String> {
    /// Edits to different words combine. Needs a base.
    public static var byWord: StringWordMerge<String> { StringWordMerge() }
}
