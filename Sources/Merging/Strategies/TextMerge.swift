extension MergeKind {
    /// Splits text into tokens, merges them like an array, and joins them again. Edits to different tokens
    /// combine, and edits to the same one conflict. Needs a base.
    enum Text {
        static func merge<Value>(base: Value?, ours: Value, theirs: Value) throws -> Value {
            guard let base = base as? String else { throw Unmergeable() }
            let split = { (text: String) in Snapshot.array(words(of: text).map(Snapshot.string)) }
            guard case .array(let merged) = try split(ours as! String).merging(split(theirs as! String), base: split(base)) else {
                throw Unmergeable()
            }
            return merged.map { token in
                guard case .string(let text) = token else { return "" }
                return text
            }.joined() as! Value
        }

        /// The text cut into words, each a run of letters, digits, and apostrophes with the spaces and
        /// punctuation after it, so joining them gives back the text. Anything before the first word is a
        /// token of its own. The rule is simple and the same everywhere, since both sides of a merge must
        /// cut the text alike.
        static func words(of text: String) -> [String] {
            var tokens: [String] = []
            var token = ""
            var inSeparator = false
            for character in text {
                let isWord = character.isLetter || character.isNumber || character == "'" || character == "’"
                if isWord, inSeparator, !token.isEmpty {
                    tokens.append(token)
                    token = ""
                }
                inSeparator = !isWord
                token.append(character)
            }
            if !token.isEmpty { tokens.append(token) }
            return tokens
        }
    }
}
