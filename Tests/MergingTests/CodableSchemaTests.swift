// Not `@testable`, so these tests only see the public surface.
import Foundation
import Merging
import Testing

@Suite struct CodableSchemaTests {
    enum Status: String, Codable, CaseIterable {
        case draft, done
    }

    struct Child: Codable {
        var grandchildren: [String]
    }

    struct Person: Codable {
        var name: String
        var age: Int
        var nickname: String?
        var tags: [String]
        var child: Child?
        var scores: [String: Double]
        var born: Date
        var id: UUID
        var status: Status
        var flags: Set<Int>
        var notes: [String?]
    }

    struct Pet: Codable {
        var name: String
        var nickname: String?
        var tags: [String]
    }

    struct Comment: Codable {
        var text: String
        var replies: [Comment]
    }

    enum Shape: Codable {
        case circle(radius: Double)
    }

    enum Mood: String, Codable {
        case happy
    }

    @Test func readsATypeWithItsOptionals() throws {
        let schema = try CodableSchema(Person.self)
        #expect(schema == .object([
            "name": .string,
            "age": .integer,
            "nickname": .optional(.string),
            "tags": .array(.string),
            "child": .optional(.object(["grandchildren": .array(.string)])),
            "scores": .dictionary(.double),
            "born": .double,
            "id": .string,
            "status": .string,
            "flags": .set(.integer),
            "notes": .array(.optional(.string)),
        ]))
        #expect(try CodableSchema(Person.self) == schema)
    }

    @Test func describesLikeSwift() throws {
        #expect(try CodableSchema(Pet.self).description == "{name: string, nickname: string?, tags: [string]}")
        #expect(try CodableSchema([String: Int?].self).description == "[string: integer?]")
        #expect(try CodableSchema(Set<String>.self).description == "set<string>")
    }

    @Test func looksUpByPath() throws {
        let schema = try CodableSchema(Person.self)
        #expect(schema["child.grandchildren[0]"] == .string)
        #expect(schema["scores.math"] == .double)
        #expect(schema["notes[3]"] == .optional(.string))
        #expect(schema["flags[0]"] == .integer)
        #expect(schema["."] == schema)
        #expect(schema["missing"] == nil)
        #expect(schema["name.first"] == nil)
    }

    @Test func roundTripsAsJSON() throws {
        let schema = try CodableSchema(Pet.self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(schema), as: UTF8.self)
        #expect(json == #"{"object":{"name":"string","nickname":{"optional":"string"},"tags":{"array":"string"}}}"#)
        #expect(try JSONDecoder().decode(CodableSchema.self, from: Data(json.utf8)) == schema)
        let person = try CodableSchema(Person.self)
        #expect(try JSONDecoder().decode(CodableSchema.self, from: encoder.encode(person)) == person)
    }

    @Test func diffsTwoVersionsOfAModel() throws {
        struct Before: Codable { var name: String }
        struct After: Codable {
            var name: String
            var nickname: String?
        }
        let difference = try CodableDifference(from: CodableSchema(Before.self), to: CodableSchema(After.self))
        #expect(difference.map(\.description) == [#"+ object.nickname: {"optional": "string"}"#])
    }

    @Test func explainsAnInsertionAtAnOptional() throws {
        let difference = try CodableDifference(
            from: Pet(name: "Rex", nickname: nil, tags: []),
            to: Pet(name: "Rex", nickname: "R", tags: [])
        )
        let schema = try CodableSchema(Pet.self)
        #expect(difference.map(\.path).map { schema[$0] } == [.optional(.string)])
    }

    @Test func throwsForTypesItCannotProbe() {
        #expect(throws: DecodingError.self) { try CodableSchema(Comment.self) }
        #expect(throws: DecodingError.self) { try CodableSchema(Shape.self) }
        #expect(throws: DecodingError.self) { try CodableSchema(Mood.self) }
    }

    @Test func idIsDerivedFromTheSchema() throws {
        let id = try CodableSchema(Pet.self).id
        // Computed independently, so a change to the hashed text, or a platform difference, shows here.
        #expect(id.uuidString == "63612143-9CF9-8D1A-AF78-CC11B874870D")
        let again = try CodableSchema(Pet.self).id
        let child = try CodableSchema(Child.self).id
        #expect(id == again)
        #expect(id != child)
        #expect(CodableSchema.optional(.string).id != CodableSchema.string.id)
        let text = Array(id.uuidString)
        #expect(text[14] == "8")
        #expect("89AB".contains(text[19]))
    }
}
