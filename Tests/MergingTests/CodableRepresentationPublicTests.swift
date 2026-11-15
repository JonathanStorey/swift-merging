// Not `@testable`, so these tests only see the public surface.
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
}
