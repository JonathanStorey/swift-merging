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
                public func merging(_ theirs: Game) throws(MergeConflict<Game>) -> Game {
                    var merged = self
                    do {
                        merged.title = try _mergeProperty(ours: self.title, theirs: theirs.title)
                        merged.highScore = try _mergeProperty(ours: self.highScore, theirs: theirs.highScore, with: MaxMerge())
                    } catch {
                        throw MergeConflict(ours: self, theirs: theirs)
                    }
                    return merged
                }

                public func merging(_ theirs: Game, base: Game) throws(MergeConflict<Game>) -> Game {
                    var merged = self
                    do {
                        merged.title = try _mergeProperty(base: base.title, ours: self.title, theirs: theirs.title)
                        merged.highScore = try _mergeProperty(base: base.highScore, ours: self.highScore, theirs: theirs.highScore, with: MaxMerge())
                    } catch {
                        throw MergeConflict(base: base, ours: self, theirs: theirs)
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
                func merging(_ theirs: Game) throws(MergeConflict<Game>) -> Game {
                    return self
                }

                func merging(_ theirs: Game, base: Game) throws(MergeConflict<Game>) -> Game {
                    return self
                }
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@Merged applies to one stored 'var' property", line: 3, column: 5)],
            macroSpecs: macros,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test func aStructWritingItsOwnMergeIsAnError() {
        assertMacroExpansion(
            """
            @Mergeable
            struct Booking {
                var note = ""
                func merging(_ theirs: Booking) -> Booking { self }
            }
            """,
            expandedSource: """
            struct Booking {
                var note = ""
                func merging(_ theirs: Booking) -> Booking { self }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Mergeable writes the merge for you. Remove @Mergeable to write your own", line: 1, column: 1,
                    fixIts: [FixItSpec(message: "Remove @Mergeable")]
                )
            ],
            macroSpecs: macros,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }
}
