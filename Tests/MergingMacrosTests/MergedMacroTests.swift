#if canImport(MergingMacros)
import MergingMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite struct MergedMacroTests {
    @Test func shorthandBecomesItsStrategy() {
        expectExpansion(
            """
            @Merged(.keep(.ours)) var nickname = ""
            """,
            """
            var nickname = ""

            var $nickname: Merging.MergedProperty<String> {
                get {
                    Merging.MergedProperty(self.nickname, Merging.KeepMerge(.ours))
                }
                set {
                    self.nickname = newValue.value
                }
            }
            """
        )
    }

    @Test func aStrategyOfYourOwnIsKeptAsWritten() {
        expectExpansion(
            """
            @Merged(LongerMerge()) var title: String = ""
            """,
            """
            var title: String = ""

            var $title: Merging.MergedProperty<String> {
                get {
                    Merging.MergedProperty(self.title, LongerMerge())
                }
                set {
                    self.title = newValue.value
                }
            }
            """
        )
    }

    @Test func projectionMatchesTheAccessLevel() {
        expectExpansion(
            """
            @Merged(.keep(.theirs)) public private(set) static var count: Int?
            """,
            """
            public private(set) static var count: Int?

            public private(set) static var $count: Merging.MergedProperty<Int?> {
                get {
                    Merging.MergedProperty(self.count, Merging.KeepMerge(.theirs))
                }
                set {
                    self.count = newValue.value
                }
            }
            """
        )
    }

    @Test func literalsGiveTheType() {
        expectExpansion(
            """
            @Merged(AddMerge()) var likes = 0
            @Merged(.keep(.ours)) var ratio = 0.5
            @Merged(.keep(.ours)) var done = false
            """,
            """
            var likes = 0

            var $likes: Merging.MergedProperty<Int> {
                get {
                    Merging.MergedProperty(self.likes, AddMerge())
                }
                set {
                    self.likes = newValue.value
                }
            }
            var ratio = 0.5

            var $ratio: Merging.MergedProperty<Double> {
                get {
                    Merging.MergedProperty(self.ratio, Merging.KeepMerge(.ours))
                }
                set {
                    self.ratio = newValue.value
                }
            }
            var done = false

            var $done: Merging.MergedProperty<Bool> {
                get {
                    Merging.MergedProperty(self.done, Merging.KeepMerge(.ours))
                }
                set {
                    self.done = newValue.value
                }
            }
            """
        )
    }

    @Test func aLetHasAReadOnlyProjection() {
        expectExpansion(
            """
            @Merged(.keep(.ours)) let id: String
            """,
            """
            let id: String

            var $id: Merging.MergedProperty<String> {
                Merging.MergedProperty(self.id, Merging.KeepMerge(.ours))
            }
            """
        )
    }

    @Test func anInferredTypeNeedsAnAnnotation() {
        expectExpansion(
            """
            @Merged(.keep(.ours)) var total = makeTotal()
            """,
            """
            var total = makeTotal()
            """,
            diagnostics: [DiagnosticSpec(message: "'total' needs a type annotation for @Merged", line: 1, column: 27)]
        )
    }

    @Test func aComputedPropertyIsAnError() {
        expectExpansion(
            """
            @Merged(.keep(.ours)) var total: Int { 0 }
            """,
            """
            var total: Int { 0 }
            """,
            diagnostics: [DiagnosticSpec(message: "@Merged goes on a stored property", line: 1, column: 1)]
        )
    }

    /// Checks `@Merged` expands `source` to `expanded`, reporting a mismatch as a Swift Testing issue.
    private func expectExpansion(
        _ source: String,
        _ expanded: String,
        diagnostics: [DiagnosticSpec] = [],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        assertMacroExpansion(
            source,
            expandedSource: expanded,
            diagnostics: diagnostics,
            macroSpecs: ["Merged": MacroSpec(type: MergedMacro.self)],
            failureHandler: { failure in
                Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
            }
        )
    }
}
#endif
