import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct MergingMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [MergeableModelMacro.self, MergeMacro.self]
}

/// Writes a `@Model` class's `MergeableModel` conformance: a snapshot of its stored properties, each with
/// the strategy its `@Merge` names, and the code that reads and applies one.
public struct MergeableModelMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let model = declaration.as(ClassDeclSyntax.self), model.attributes.attribute(named: "Model") != nil else {
            throw MergingDiagnostic.error(at: node, "@MergeableModel is for SwiftData @Model classes; a Codable value merges with @Merged instead", id: "not-a-model")
        }
        // Already conforms, by hand or by an earlier expansion.
        if protocols.isEmpty { return [] }

        let properties = try StoredProperty.all(in: model)
        let access = model.modifiers.contains { [.keyword(.public), .keyword(.open)].contains($0.name.tokenKind) } ? "public " : ""
        let typeName = type.trimmedDescription

        let fields = properties.map { property in
            let wrapper = property.strategy.map { "@Merging.Merged(\($0)) " } ?? ""
            return "\(wrapper)\(access)var \(property.name): \(property.type)"
        }
        let parameters = properties.map { "\($0.name): \($0.type)" }.joined(separator: ", ")
        let assignments = properties.map { property in
            if let strategy = property.strategy {
                "self._\(property.name) = Merging.Merged(wrappedValue: \(property.name), \(strategy))"
            } else {
                "self.\(property.name) = \(property.name)"
            }
        }
        let arguments = properties.map { "\($0.name): self.\($0.name)" }.joined(separator: ", ")
        let applies = properties.map { "if self.\($0.name) != snapshot.\($0.name) { self.\($0.name) = snapshot.\($0.name) }" }
        let keyPaths = properties.map { "\\\(typeName).\($0.name)" }.joined(separator: ", ")

        let source = """
        extension \(typeName): MergingSwiftData.MergeableModel {
            \(access)struct MergeSnapshot: Codable, Equatable, Merging.Mergeable {
                \(fields.joined(separator: "\n        "))

                \(access)init(\(parameters)) {
                    \(assignments.joined(separator: "\n            "))
                }
            }

            \(access)var mergeSnapshot: MergeSnapshot {
                MergeSnapshot(\(arguments))
            }

            \(access)func applyMergeSnapshot(_ snapshot: MergeSnapshot) {
                \(applies.joined(separator: "\n        "))
            }

            \(access)static var mergeKeyPaths: [PartialKeyPath<\(typeName)>] {
                [\(keyPaths)]
            }
        }
        """
        let decl: DeclSyntax = "\(raw: source)"
        guard let extensionDecl = decl.as(ExtensionDeclSyntax.self) else { return [] }
        return [extensionDecl]
    }
}

/// Marks how one property merges. `@MergeableModel` reads it, so it expands to nothing, and it checks it's
/// on a stored property of a `@Model` class.
public struct MergeMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let onlyModels = "@Merge is for SwiftData @Model classes; a Codable value's property merges with @Merged instead"
        guard declaration.is(VariableDeclSyntax.self) else {
            throw MergingDiagnostic.error(at: node, "@Merge goes on a stored property of a SwiftData @Model class", id: "not-a-property")
        }
        guard let owner = context.lexicalContext.first else { return [] }
        if owner.is(StructDeclSyntax.self) || owner.is(EnumDeclSyntax.self) || owner.is(ActorDeclSyntax.self) {
            throw MergingDiagnostic.error(at: node, onlyModels, id: "not-a-model")
        }
        // The lexical context keeps a class's attributes, so check them when they're there.
        if let model = owner.as(ClassDeclSyntax.self), !model.attributes.isEmpty {
            guard model.attributes.attribute(named: "Model") != nil else {
                throw MergingDiagnostic.error(at: node, onlyModels, id: "not-a-model")
            }
            guard model.attributes.attribute(named: "MergeableModel") != nil else {
                throw MergingDiagnostic.error(at: node, "@Merge needs @MergeableModel on \(model.name.text)", id: "missing-mergeable-model")
            }
        }
        return []
    }
}

/// A stored property the snapshot holds.
struct StoredProperty {
    let name: String
    let type: String
    /// The `@Merge` arguments, such as `.sum`, or `nil` to keep the side that changed it.
    let strategy: String?

    /// Every stored `var` of a model, except static, computed, `@Transient`, and `@Relationship` ones.
    static func all(in model: ClassDeclSyntax) throws -> [StoredProperty] {
        var properties: [StoredProperty] = []
        for member in model.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                  variable.bindingSpecifier.tokenKind == .keyword(.var),
                  !variable.modifiers.contains(where: { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }),
                  variable.attributes.attribute(named: "Transient") == nil,
                  variable.attributes.attribute(named: "Relationship") == nil else { continue }
            let strategy = variable.attributes.attribute(named: "Merge")?.arguments?.trimmedDescription
            for binding in variable.bindings {
                guard binding.accessorBlock == nil, let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let name = pattern.identifier.text
                guard let type = binding.typeAnnotation?.type.trimmedDescription ?? literalType(of: binding.initializer?.value) else {
                    throw MergingDiagnostic.error(at: binding, "'\(name)' needs a type annotation for @MergeableModel to merge it", id: "no-type")
                }
                properties.append(StoredProperty(name: name, type: type, strategy: strategy))
            }
        }
        return properties
    }

    /// The type of a string, number, or Boolean literal.
    private static func literalType(of value: ExprSyntax?) -> String? {
        guard let value else { return nil }
        if value.is(StringLiteralExprSyntax.self) { return "String" }
        if value.is(IntegerLiteralExprSyntax.self) { return "Int" }
        if value.is(FloatLiteralExprSyntax.self) { return "Double" }
        if value.is(BooleanLiteralExprSyntax.self) { return "Bool" }
        return nil
    }
}

extension AttributeListSyntax {
    /// The attribute with this name, with or without its module, such as `Model` or `SwiftData.Model`.
    func attribute(named name: String) -> AttributeSyntax? {
        for element in self {
            guard case .attribute(let attribute) = element else { continue }
            let written = attribute.attributeName.trimmedDescription
            if written == name || written.hasSuffix(".\(name)") { return attribute }
        }
        return nil
    }
}

struct MergingDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    var severity: DiagnosticSeverity { .error }

    static func error(at node: some SyntaxProtocol, _ message: String, id: String) -> DiagnosticsError {
        DiagnosticsError(diagnostics: [
            Diagnostic(node: Syntax(node), message: MergingDiagnostic(message: message, diagnosticID: MessageID(domain: "MergingMacros", id: id))),
        ])
    }
}
