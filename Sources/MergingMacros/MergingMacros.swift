import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Mergeable`: conforms a struct to `Mergeable`, merging each stored `var` with its `@Merged` strategy or
/// by its type. A `merge` the struct declares itself is left alone, and `mergeProperties` is always added.
public struct MergeableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: MergingMessage.notStruct))
            return []
        }
        let name = type.trimmedDescription
        let access = declaration.modifiers.contains { ["public", "package"].contains($0.name.text) }
            ? declaration.modifiers.first { ["public", "package"].contains($0.name.text) }!.name.text + " " : ""

        var merges: [String] = []
        for member in declaration.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self), variable.bindingSpecifier.tokenKind == .keyword(.var),
                  !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) else { continue }
            let strategy = mergedStrategy(of: variable)
            for binding in variable.bindings where isStored(binding) {
                guard let property = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription else { continue }
                let with = strategy.map { ", with: \($0)" } ?? ""
                merges.append(
                    "merged.\(property) = try _mergeProperty(base: base?.\(property), ours: ours.\(property), theirs: theirs.\(property)\(with))"
                )
            }
        }

        // Lines at their final indentation, since interpolated text keeps its own.
        var body = ["    \(access)static func mergeProperties(base: \(name)?, ours: \(name), theirs: \(name)) throws(MergeConflict<\(name)>) -> \(name) {"]
        if merges.isEmpty {
            body.append("        return ours")
        } else {
            body.append("        var merged = ours")
            body.append("        do {")
            body += merges.map { "            " + $0 }
            body.append("        } catch {")
            body.append("            throw MergeConflict(base: base, ours: ours, theirs: theirs)")
            body.append("        }")
            body.append("        return merged")
        }
        body.append("    }")

        var functions: [[String]] = []
        if !declares(declaration, labels: ["ours", "theirs"]) {
            functions.append([
                "    \(access)static func merge(ours: \(name), theirs: \(name)) throws(MergeConflict<\(name)>) -> \(name) {",
                "        try mergeProperties(base: nil, ours: ours, theirs: theirs)",
                "    }",
            ])
        }
        if !declares(declaration, labels: ["base", "ours", "theirs"]) {
            functions.append([
                "    \(access)static func merge(base: \(name), ours: \(name), theirs: \(name)) throws(MergeConflict<\(name)>) -> \(name) {",
                "        try mergeProperties(base: base, ours: ours, theirs: theirs)",
                "    }",
            ])
        }
        functions.append(["    /// Merges each stored property, and throws if any of them can't merge."] + body)
        let conformance = protocols.isEmpty ? "" : ": Mergeable"
        let lines = ["extension \(name)\(conformance) {"] + Array(functions.joined(separator: [""])) + ["}"]
        let source = DeclSyntax(stringLiteral: lines.joined(separator: "\n"))
        return [source.cast(ExtensionDeclSyntax.self)]
    }

    /// A stored property: no accessors, or only observers.
    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock?.accessors else { return true }
        guard case .accessors(let list) = accessors else { return false }
        return list.allSatisfy { [.keyword(.willSet), .keyword(.didSet)].contains($0.accessorSpecifier.tokenKind) }
    }

    /// The strategy a `@Merged(_:)` attribute names, as written.
    private static func mergedStrategy(of variable: VariableDeclSyntax) -> String? {
        for case .attribute(let attribute) in variable.attributes where attribute.attributeName.trimmedDescription == "Merged" {
            return attribute.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.trimmedDescription
        }
        return nil
    }

    /// Whether the struct declares a static `merge` with these argument labels.
    private static func declares(_ declaration: some DeclGroupSyntax, labels: [String]) -> Bool {
        declaration.memberBlock.members.contains { member in
            guard let function = member.decl.as(FunctionDeclSyntax.self), function.name.text == "merge" else { return false }
            return function.signature.parameterClause.parameters.map(\.firstName.text) == labels
        }
    }
}

/// `@Merged(_:)`, a marker `@Mergeable` reads. It expands to nothing, and checks it's on one stored `var`
/// of a `@Mergeable` type.
public struct MergedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self), variable.bindingSpecifier.tokenKind == .keyword(.var),
              variable.bindings.count == 1 else {
            context.diagnose(Diagnostic(node: node, message: MergingMessage.notStoredVar))
            return []
        }
        let owner = context.lexicalContext.first?.asProtocol(WithAttributesSyntax.self)
        let insideMergeable = owner?.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Mergeable"
        } ?? false
        if !insideMergeable {
            context.diagnose(Diagnostic(node: node, message: MergingMessage.outsideMergeable))
        }
        return []
    }
}

enum MergingMessage: String, DiagnosticMessage {
    case notStruct
    case notStoredVar
    case outsideMergeable

    var message: String {
        switch self {
        case .notStruct: "@Mergeable applies to a struct"
        case .notStoredVar: "@Merged applies to one stored 'var' property"
        case .outsideMergeable: "@Merged needs its type to be @Mergeable"
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "Merging", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

@main
struct MergingPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [MergeableMacro.self, MergedMacro.self]
}
