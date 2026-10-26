import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Mergeable`: conforms a struct to `Mergeable`, merging each stored `var` with its `@Merged` strategy or
/// by its type. A struct that declares its own `merge` or `merging` is an error, since the macro owns them.
public struct MergeableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: MergingMessage.notStruct))
            return []
        }
        if declaresMerge(declaration) {
            context.diagnose(Diagnostic(
                node: node, message: MergingMessage.declaresMerge,
                fixIt: FixIt(message: RemoveMergeable(), changes: [.replace(oldNode: Syntax(node), newNode: Syntax(TokenSyntax.unknown("")))])
            ))
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
                    "merged.\(property) = try _mergeProperty(base: base?.\(property), ours: self.\(property), theirs: theirs.\(property)\(with))"
                )
            }
        }

        // Lines at their final indentation, since interpolated text keeps its own.
        var function = ["    \(access)func merging(_ theirs: \(name), base: \(name)?) throws(MergeConflict<\(name)>) -> \(name) {"]
        if merges.isEmpty {
            function.append("        return self")
        } else {
            function.append("        var merged = self")
            function.append("        do {")
            function += merges.map { "            " + $0 }
            function.append("        } catch {")
            function.append("            throw MergeConflict(base: base, ours: self, theirs: theirs)")
            function.append("        }")
            function.append("        return merged")
        }
        function.append("    }")
        let conformance = protocols.isEmpty ? "" : ": Mergeable"
        let lines = ["extension \(name)\(conformance) {"] + function + ["}"]
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

    /// Whether the struct declares a `merge` or `merging` of its own.
    private static func declaresMerge(_ declaration: some DeclGroupSyntax) -> Bool {
        declaration.memberBlock.members.contains { member in
            guard let function = member.decl.as(FunctionDeclSyntax.self) else { return false }
            return ["merge", "merging"].contains(function.name.text)
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
    case declaresMerge

    var message: String {
        switch self {
        case .notStruct: "@Mergeable applies to a struct"
        case .notStoredVar: "@Merged applies to one stored 'var' property"
        case .outsideMergeable: "@Merged needs its type to be @Mergeable"
        case .declaresMerge: "@Mergeable writes the merge for you. Remove @Mergeable to write your own"
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "Merging", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

struct RemoveMergeable: FixItMessage {
    var message: String { "Remove @Mergeable" }
    var fixItID: MessageID { MessageID(domain: "Merging", id: "removeMergeable") }
}

@main
struct MergingPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [MergeableMacro.self, MergedMacro.self]
}
