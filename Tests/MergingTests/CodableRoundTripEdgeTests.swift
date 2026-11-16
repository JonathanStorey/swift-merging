// Not `@testable`, so these tests only see the public surface.
import Foundation
import Merging
import Testing

@Suite struct CodableRoundTripEdgeTests {
    @Test func dictionariesWithIntAndUUIDKeysRoundTrip() throws {
        let numbered: [Int: String] = [1: "a", 20: "b"]
        let byNumber = try CodableRepresentation(encoding: numbered)
        #expect(byNumber == ["1": "a", "20": "b"])
        #expect(try byNumber.decode(as: [Int: String].self) == numbered)

        let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let identified: [UUID: String] = [id: "a"]
        #expect(try CodableRepresentation(encoding: identified).decode(as: [UUID: String].self) == identified)
    }

    class Animal: Codable {
        var name: String
        init(name: String) { self.name = name }
    }

    final class Dog: Animal {
        var breed: String

        init(name: String, breed: String) {
            self.breed = breed
            super.init(name: name)
        }

        private enum CodingKeys: String, CodingKey { case breed }

        required init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            breed = try container.decode(String.self, forKey: .breed)
            try super.init(from: container.superDecoder())
        }

        override func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(breed, forKey: .breed)
            try super.encode(to: container.superEncoder())
        }
    }

    @Test func aSubclassRoundTripsThroughItsSuperclass() throws {
        let representation = try CodableRepresentation(encoding: Dog(name: "Rex", breed: "Lab"))
        #expect(representation == ["breed": "Lab", "super": ["name": "Rex"]])
        let dog = try representation.decode(as: Dog.self)
        #expect(dog.name == "Rex")
        #expect(dog.breed == "Lab")
        #expect(try CodableSchema(Dog.self) == .object(["breed": .string, "super": .object(["name": .string])]))
    }

    struct Empty: Codable, Equatable {}

    @Test func anEmptyStructIsAnEmptyObjectAndNilIsNull() throws {
        #expect(try CodableRepresentation(encoding: Empty()) == .object([:]))
        #expect(try CodableRepresentation(encoding: Empty()).decode(as: Empty.self) == Empty())
        let missing: Int? = nil
        #expect(try CodableRepresentation(encoding: missing) == .null)
        #expect(try CodableRepresentation.null.decode(as: Int?.self) == nil)
    }

    struct Twice: Codable {
        var value: String??
    }

    @Test func aDoubleOptionalLosesItsInnerNil() throws {
        // Codable can't tell `.some(nil)` from `nil`, so both come back as `nil`.
        let decoded = try CodableRepresentation(encoding: Twice(value: .some(nil))).decode(as: Twice.self)
        guard case .none = decoded.value else {
            Issue.record("Expected nil, got \(String(describing: decoded.value))")
            return
        }
    }

    @Test func canonicallyEquivalentStringsAreEqual() throws {
        // Swift compares strings by canonical equivalence, so "é" as one scalar or two is no change.
        let composed = "\u{E9}"
        let decomposed = "e\u{301}"
        #expect(CodableRepresentation.string(composed) == .string(decomposed))
        #expect(try CodableDifference(from: composed, to: decomposed).isEmpty)
    }

    @Test func deepNestingWorks() throws {
        // Encoding, diffing and comparing all recurse, so a test thread's small stack sets the limit. A
        // thousand levels overflowed one on Linux, so this stays well inside it.
        var old: CodableRepresentation = 0
        var new: CodableRepresentation = 1
        for _ in 0..<128 {
            old = [old]
            new = [new]
        }
        let difference = try CodableDifference(from: old, to: new)
        #expect(difference.count == 1)
        #expect(difference.first?.path.count == 128)
        #expect(try old.applying(difference) == new)
    }

    @Test func decimalsEqualByValueHashEqually() {
        let one = Decimal(string: "1.0")!
        let same = Decimal(string: "1.00")!
        #expect(CodableRepresentation.decimal(one) == .decimal(same))
        #expect(Set<CodableRepresentation>([.decimal(one), .decimal(same)]).count == 1)
    }
}

@Suite struct CodableDifferenceEdgeTests {
    @Test func severalElementsRemovedOrInsertedAtOnce() throws {
        let shrink = try CodableDifference(from: [1, 2, 3, 4], to: [1])
        #expect(shrink.count == 3)
        #expect(try [1, 2, 3, 4].applying(shrink) == [1])
        #expect(try [1].applying(shrink.inverse()) == [1, 2, 3, 4])

        let fill = try CodableDifference(from: [Int](), to: [5, 6])
        #expect(try [Int]().applying(fill) == [5, 6])
    }

    @Test func aChangeOfTypeIsAReplacement() throws {
        let old: CodableRepresentation = ["a": 1, "b": [1]]
        let new: CodableRepresentation = ["a": "x", "b": ["k": 1]]
        let difference = try CodableDifference(from: old, to: new)
        #expect(Array(difference) == [
            .replace(path: "a", old: 1, new: "x"),
            .replace(path: "b", old: [1], new: ["k": 1]),
        ])
        #expect(try old.applying(difference) == new)
    }

    @Test func changesToMissingPathsAreSkipped() throws {
        let removal = try CodableDifference(from: ["a": 1, "b": 2], to: ["a": 1])
        #expect(try ["a": 5].applying(removal) == ["a": 5])
        let replacement = try CodableDifference(from: ["a": 1, "b": 2], to: ["a": 1, "b": 3])
        #expect(try ["a": 5].applying(replacement) == ["a": 5])
        let beyond = try CodableDifference(from: [1, 2, 3], to: [1, 2, 4])
        #expect(try [1].applying(beyond) == [1])
    }

    struct Tagged: Codable, Equatable {
        var flags: Set<Int>?
    }

    @Test func squashingMixesWholeSetsAndMembers() throws {
        let none = Tagged(flags: nil)
        let one = Tagged(flags: [1])
        let two = Tagged(flags: [1, 2])

        let growing = try #require(try CodableDifference(from: none, to: one).followed(by: CodableDifference(from: one, to: two)))
        #expect(growing == (try CodableDifference(from: none, to: two)))
        #expect(try none.applying(growing) == two)

        let shrinking = try #require(try CodableDifference(from: two, to: one).followed(by: CodableDifference(from: one, to: none)))
        #expect(shrinking == (try CodableDifference(from: two, to: none)))
        #expect(try two.applying(shrinking) == none)
    }

    struct Before: Codable { var name = "Ana" }
    struct After: Codable {
        var name = "Ana"
        var nickname: String?
    }

    @Test func aDifferenceForAnOlderModelIsRefused() throws {
        let difference = try CodableDifference(from: Before(), to: Before(name: "Bo"))
        #expect(throws: DecodingError.self) { try After().applying(difference) }
    }
}

@Suite struct CodablePathEdgeTests {
    @Test func oddLiteralsParseAndRoundTrip() {
        let paths: [CodablePath] = ["", ".", "..", "a..b", "[x]", "a[", "items[0].title", "[2][1]"]
        #expect(paths[0].isEmpty && paths[1].isEmpty && paths[2].isEmpty)
        #expect(paths[3] == ["a", "b"])
        #expect(paths[4] == [.key("[x]")])
        #expect(paths[5] == [.key("a"), .key("[")])
        for path in paths {
            #expect(CodablePath(stringLiteral: path.description) == path, "\(path)")
        }
    }
}

@Suite struct CodableSchemaEdgeTests {
    struct Box<Value: Codable>: Codable {
        var value: Value
    }

    @Test func genericTypesHaveTheirOwnSchemas() throws {
        let numbers = try CodableSchema(Box<Int>.self)
        let words = try CodableSchema(Box<String>.self)
        #expect(numbers == .object(["value": .integer]))
        #expect(words == .object(["value": .string]))
        #expect(numbers.id != words.id)
    }

    @Test func schemasReadConcurrently() async throws {
        let schemas = try await withThrowingTaskGroup(of: CodableSchema.self) { group in
            for index in 0..<200 {
                group.addTask { index.isMultiple(of: 2) ? try CodableSchema(Box<Double>.self) : try CodableSchema(Box<Bool>.self) }
            }
            var schemas: [CodableSchema] = []
            for try await schema in group { schemas.append(schema) }
            return schemas
        }
        #expect(schemas.count == 200)
        #expect(Set(schemas) == [.object(["value": .double]), .object(["value": .bool])])
    }

    struct Strict: Codable {
        var code: String

        init(from decoder: any Decoder) throws {
            code = try decoder.singleValueContainer().decode(String.self)
            guard code.count == 3 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A code has three letters."))
            }
        }
    }

    @Test func aTypeThatRejectsPlaceholdersThrows() {
        #expect(throws: DecodingError.self) { try CodableSchema(Strict.self) }
    }
}
