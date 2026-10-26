import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Merged(_:)`, a marker on a stored property. It expands to nothing, and checks it's on a single
/// stored `var`.
public struct MergedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self), variable.bindingSpecifier.tokenKind == .keyword(.var),
              variable.bindings.count == 1, variable.bindings.first?.accessorBlock == nil else {
            context.diagnose(Diagnostic(node: node, message: MergingMessage.notStoredVar))
            return []
        }
        return []
    }
}

enum MergingMessage: String, DiagnosticMessage {
    case notStoredVar

    var message: String {
        switch self {
        case .notStoredVar: "@Merged applies to one stored 'var' property"
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "Merging", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

@main
struct MergingPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [MergedMacro.self]
}
