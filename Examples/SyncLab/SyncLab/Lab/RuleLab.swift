import Foundation
import MergingSwiftData

/// Merges `Item`'s snapshots directly, with no store: what every later stage relies on.
@MainActor
enum RuleLab {
    static func run(_ kind: DataKind, _ lab: LabContext) -> [String] {
        var failures: [String] = []
        let base = Draft()
        var ours = base
        ours.apply(kind, by: 0)
        var theirs = base
        theirs.apply(kind, by: 1)
        var theirsTwice = theirs
        theirsTwice.apply(kind, by: 2)

        lab.board.set(0, .editing)
        lab.board.set(1, .editing)
        lab.log("Ours \(kind.editSummary(0)); theirs \(kind.editSummary(1))")

        // 3-way, two editors.
        lab.board.hub = .merging
        let two = Draft(Item.mergeSnapshots(base: base.snapshot, ours: ours.snapshot, theirs: theirs.snapshot, favoring: .ours))
        let twoMisses = kind.mismatches(two.values, editors: 2)
        failures += twoMisses.map { "3-way, 2 editors: \($0)" }
        lab.log(twoMisses.isEmpty ? "3-way with 2 editors kept both edits" : "3-way with 2 editors lost an edit")

        // 3-way, three editors: theirs is two saves on top of each other.
        let three = Draft(Item.mergeSnapshots(base: base.snapshot, ours: ours.snapshot, theirs: theirsTwice.snapshot, favoring: .ours))
        let threeMisses = kind.mismatches(three.values, editors: 3)
        failures += threeMisses.map { "3-way, 3 editors: \($0)" }
        lab.log(threeMisses.isEmpty ? "3-way with 3 editors kept all three edits" : "3-way with 3 editors lost an edit")

        // 2-way, no base: a strategy may refuse, but must never quietly keep one edit and drop the other.
        // Keep(.theirs) is the exception by design: it keeps theirs with or without a base.
        let outcome: String
        switch kind {
        case .string:
            outcome = judge(Merged(wrappedValue: ours.title, .byWord).merging(with: theirs.title), want: two.title, &failures)
        case .strings:
            outcome = judge(Merged(wrappedValue: ours.steps, .byElement).merging(with: theirs.steps), want: two.steps, &failures)
        case .codable:
            outcome = judge(Merged(wrappedValue: ours.spec, .byNode).merging(with: theirs.spec), want: two.spec, &failures)
        case .relationship:
            outcome = judge(Merged(wrappedValue: ours.labels, .byMembership).merging(with: theirs.labels), want: two.labels, &failures)
        case .blob:
            let merged = Merged(wrappedValue: ours.blob, .keep(.theirs)).merging(with: theirs.blob)
            if merged != theirs.blob {
                failures.append("2-way: .keep(.theirs) didn't keep theirs")
                outcome = "didn't keep theirs"
            } else {
                outcome = "kept theirs, as .keep(.theirs) always does"
            }
        }
        lab.log("2-way with no base \(outcome)")
        lab.board.hub = failures.isEmpty ? .done : .failed
        return failures
    }

    /// A 2-way result passes if it refused (nil) or kept both edits.
    private static func judge<Value: Equatable>(_ merged: Value?, want: Value, _ failures: inout [String]) -> String {
        guard let merged else { return "refused, which is the honest answer without a base" }
        if merged == want { return "kept both edits" }
        failures.append("2-way: merged to \(merged), which drops an edit")
        return "dropped an edit"
    }
}
