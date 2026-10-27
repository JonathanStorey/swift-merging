/// Merges text word by word, so edits to different words combine and edits to the same word conflict.
/// Needs a base.
public struct WordMerge: TreeMergeStrategy {
    public init() {}

    public func merge(base: CodableTree, ours: CodableTree, theirs: CodableTree) throws(MergeConflict<CodableTree>) -> CodableTree {
        guard let original = base.string, let mine = ours.string, let other = theirs.string else {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
        let merged = try Self.words(mine).merging(Self.words(other), base: Self.words(original))
        return .string(merged.array?.compactMap(\.string).joined() ?? "")
    }

    /// The text as an array of words, each a run of letters, digits, and apostrophes with the spaces and
    /// punctuation after it, so joining them gives back the text. Anything before the first word is one of
    /// its own. The rule is simple and the same everywhere, since both sides of a merge must cut text alike.
    static func words(_ text: String) -> CodableTree {
        var words: [CodableTree] = []
        var word = ""
        var inSeparator = false
        for character in text {
            let isWord = character.isLetter || character.isNumber || character == "'" || character == "’"
            if isWord, inSeparator, !word.isEmpty {
                words.append(.string(word))
                word = ""
            }
            inSeparator = !isWord
            word.append(character)
        }
        if !word.isEmpty { words.append(.string(word)) }
        return .array(words)
    }
}

extension MergeStrategy where Self == WordMerge {
    /// Edits to different words combine. Needs a base.
    public static var byWord: WordMerge { WordMerge() }
}

extension Merged where Strategy == WordMerge {
    public init(wrappedValue: Value, _ strategy: WordMerge) where Value == String {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}
