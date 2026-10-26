import MergingMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite struct MergedMacroTests {
    let macros = ["Merged": MacroSpec(type: MergedMacro.self)]

    @Test func expandsToNothing() {
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
            macroSpecs: macros,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }

    @Test func needsAStoredVar() {
        assertMacroExpansion(
            """
            struct Game {
                @Merged(MaxMerge()) let highScore = 0
            }
            """,
            expandedSource: """
            struct Game {
                let highScore = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Merged applies to one stored 'var' property", line: 2, column: 5),
            ],
            macroSpecs: macros,
            failureHandler: { Issue.record("\($0.message)") }
        )
    }
}
