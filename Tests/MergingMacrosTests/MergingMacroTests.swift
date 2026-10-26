import MergingMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite struct MergeableMacroTests {
    let macros = ["Mergeable": MacroSpec(type: MergeableMacro.self, conformances: ["Mergeable"]), "Merged": MacroSpec(type: MergedMacro.self)]

    @Test func mergesEachStoredVar() {
        assertMacroExpansion(
            """
            @Mergeable
            public struct Game {
                let id: Int
                var title = ""
                @Merged(MaxMerge()) var highScore = 0
                var summary: String { title }
                static var sample = 1
            }
            """,
            expandedSource: """
            public struct Game {
                let id: Int
                var title = ""
                var highScore = 0
                var summary: String { title }
                static var sample = 1
            }

            extension Game: Mergeable {
                public static func merge(ours: Game, theirs: Game) throws(MergeConflict<Game>) -> Game {
                    try mergeProperties(base: nil, ours: ours, theirs: theirs)
                }

                public static func merge(base: Game, ours: Game, theirs: Game) throws(MergeConflict<Game>) -> Game {
                    try mergeProperties(base: base, ours: ours, theirs: theirs)
                }

                /// Merges each stored property, and throws if any of them can't merge.
                public static func mergeProperties(base: Game?, ours: Game, theirs: Game) throws(MergeConflict<Game>) -> Game {
                    var merged = ours
                    do {
                        merged.title = try _mergeProperty(base: base?.title, ours: ours.title, theirs: theirs.title)
                        merged.highScore = try _mergeProperty(base: base?.highScore, ours: ours.highScore, theirs: theirs.highScore, with: MaxMerge())
                    } catch {
                        throw MergeConflict(base: base, ours: ours, theirs: theirs)
                    }
                    return merged
                }
            }
            """,
            macroSpecs: macros,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test func mergedNeedsAMergeableType() {
        assertMacroExpansion(
            """
            struct Game {
                @Merged(MaxMerge()) var highScore = 0
            }
            """,
            expandedSource: """
            struct Game {
                var highScore = 0
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@Merged needs its type to be @Mergeable", line: 2, column: 5)],
            macroSpecs: macros,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test func mergedNeedsAStoredVar() {
        assertMacroExpansion(
            """
            @Mergeable
            struct Game {
                @Merged(MaxMerge()) let highScore = 0
            }
            """,
            expandedSource: """
            struct Game {
                let highScore = 0
            }

            extension Game: Mergeable {
                static func merge(ours: Game, theirs: Game) throws(MergeConflict<Game>) -> Game {
                    try mergeProperties(base: nil, ours: ours, theirs: theirs)
                }

                static func merge(base: Game, ours: Game, theirs: Game) throws(MergeConflict<Game>) -> Game {
                    try mergeProperties(base: base, ours: ours, theirs: theirs)
                }

                /// Merges each stored property, and throws if any of them can't merge.
                static func mergeProperties(base: Game?, ours: Game, theirs: Game) throws(MergeConflict<Game>) -> Game {
                    return ours
                }
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@Merged applies to one stored 'var' property", line: 3, column: 5)],
            macroSpecs: macros,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }
}
