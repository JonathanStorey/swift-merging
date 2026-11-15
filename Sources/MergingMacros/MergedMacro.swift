import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct MergingMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [MergedMacro.self]
}

/// Writes `$name` for a property marked `@Merged(strategy)`: a `MergedProperty` of the property's value and
/// its strategy. The property itself is left as written.
public struct MergedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self) else {
            throw MergedDiagnostic.error(at: node, "@Merged goes on a property", id: "not-a-property")
        }
        guard variable.bindings.count == 1, let binding = variable.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            throw MergedDiagnostic.error(at: node, "@Merged goes on a property that declares one name", id: "several-names")
        }
        let name = pattern.identifier.text.trimmingBackticks
        guard binding.accessorBlock == nil else {
            throw MergedDiagnostic.error(at: node, "@Merged goes on a stored property", id: "computed")
        }
        guard let type = binding.mergedType else {
            throw MergedDiagnostic.error(at: binding, "'\(name)' needs a type annotation for @Merged", id: "no-type")
        }
        guard let strategy = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression else {
            throw MergedDiagnostic.error(at: node, "@Merged needs a strategy, such as @Merged(.keep(.ours))", id: "no-strategy")
        }
        return [
            """
            \(raw: variable.projectionModifiers)var $\(raw: name): Merging.MergedProperty<\(type)> {
                Merging.MergedProperty(self.\(raw: name), \(strategy.expandingShorthand))
            }
            """,
        ]
    }
}

/// The package's strategies by the shorthand `MergeShorthand` spells them with.
private let shorthandStrategies = [
    "keep": "KeepMerge",
]

extension ExprSyntax {
    /// The strategy itself for a shorthand, such as `Merging.KeepMerge(.ours)` for `.keep(.ours)`, or the
    /// expression as written for anything else. The strategy's type parameter is left to the property's
    /// type.
    fileprivate var expandingShorthand: ExprSyntax {
        if let member = self.as(MemberAccessExprSyntax.self), let strategy = member.shorthandStrategy {
            return "Merging.\(raw: strategy)()"
        }
        if let call = self.as(FunctionCallExprSyntax.self),
           let strategy = call.calledExpression.as(MemberAccessExprSyntax.self)?.shorthandStrategy {
            return ExprSyntax(call.with(\.calledExpression, "Merging.\(raw: strategy)"))
        }
        return trimmed
    }
}

extension MemberAccessExprSyntax {
    /// The strategy's type name, for a leading-dot shorthand such as `.keep`.
    fileprivate var shorthandStrategy: String? {
        base == nil ? shorthandStrategies[declName.baseName.text] : nil
    }
}

extension PatternBindingSyntax {
    /// The property's type, from its annotation or a string, number, or Boolean literal. An implicitly
    /// unwrapped optional becomes an optional, which a generic argument can be.
    fileprivate var mergedType: TypeSyntax? {
        if let type = typeAnnotation?.type {
            if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                return "\(unwrapped.wrappedType.trimmed)?"
            }
            return type.trimmed
        }
        guard let value = initializer?.value else { return nil }
        if value.is(StringLiteralExprSyntax.self) { return "String" }
        if value.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if value.is(FloatLiteralExprSyntax.self) { return "Double" }
        if value.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        return nil
    }
}

extension VariableDeclSyntax {
    /// The property's access level and `static`, for `$name`, which matches it. `open` becomes `public`,
    /// and a setter's own access, such as `private(set)`, doesn't apply to a read-only projection.
    fileprivate var projectionModifiers: String {
        modifiers.compactMap { modifier -> String? in
            guard modifier.detail == nil else { return nil }
            switch modifier.name.tokenKind {
            case .keyword(.open): return "public "
            case .keyword(.public), .keyword(.package), .keyword(.internal), .keyword(.fileprivate),
                 .keyword(.private), .keyword(.static):
                return "\(modifier.name.text) "
            default: return nil
            }
        }.joined()
    }
}

extension String {
    fileprivate var trimmingBackticks: String {
        filter { $0 != "`" }
    }
}

struct MergedDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    var severity: DiagnosticSeverity { .error }

    static func error(at node: some SyntaxProtocol, _ message: String, id: String) -> DiagnosticsError {
        DiagnosticsError(diagnostics: [
            Diagnostic(node: Syntax(node), message: MergedDiagnostic(message: message, diagnosticID: MessageID(domain: "MergingMacros", id: id))),
        ])
    }
}
