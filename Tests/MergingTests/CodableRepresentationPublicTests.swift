// Not `@testable`, so these tests only see the public surface.
import Foundation
import Merging
import Testing

@Suite struct CodableRepresentationPublicTests {
    struct Child: Codable, Equatable {
        var name: String
    }

    struct Person: Codable, Equatable {
        var name = "Ana"
        var age = 30
        var nickname: String?
        var child: Child? = Child(name: "Bo")
    }

    @Test func dictionaryIsOneLevelDeep() throws {
        let fields = try #require(try CodableRepresentation(encoding: Person()).dictionary())
        #expect(fields == ["name": "Ana", "age": 30, "child": ["name": "Bo"]])
        #expect(fields["nickname"] == nil)
    }

    @Test func dictionaryRoundTrips() throws {
        var person = Person()
        person.nickname = "A"
        let fields = try #require(try CodableRepresentation(encoding: person).dictionary())
        #expect(try CodableRepresentation.object(fields).decode(as: Person.self) == person)
    }

    @Test func onlyAnObjectHasADictionary() throws {
        #expect(try CodableRepresentation(encoding: 3).dictionary() == nil)
        #expect(try CodableRepresentation(encoding: ["a"]).dictionary() == nil)
    }

    @Test func jsonAndDataRoundTrip() throws {
        let representation = try CodableRepresentation(encoding: Person())
        #expect(try representation.json == #"{"age":30,"child":{"name":"Bo"},"name":"Ana"}"#)
        #expect(try CodableRepresentation(json: representation.json) == representation)
        #expect(try CodableRepresentation(data: representation.data) == representation)
        #expect(try CodableRepresentation(json: "[1, null, \"a/b\"]") == [1, nil, "a/b"])
        #expect(try CodableRepresentation.string("a/b").json == #""a/b""#)
    }
}
