// Not `@testable`, so these tests only see the public surface.
import Foundation
import Merging
import Testing

@Suite struct CodableRepresentationTypedTests {
    struct Listing: Codable, Equatable {
        var id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        var listed = Date(timeIntervalSinceReferenceDate: 1234.5)
        var photo = Data([0, 1, 2, 254, 255])
        var price = Decimal(string: "19.99")!
        var site = URL(string: "https://example.com/a?b=c")!
        var ratio: Float = 0.1
    }

    @Test func typedValuesKeepTheirType() throws {
        let listing = Listing()
        let representation = try CodableRepresentation(encoding: listing)
        let fields = try #require(representation.dictionary())
        #expect(fields["id"] == .uuid(listing.id))
        #expect(fields["listed"] == .date(listing.listed))
        #expect(fields["photo"] == .data(listing.photo))
        #expect(fields["price"] == .decimal(listing.price))
        #expect(fields["site"] == .url(listing.site))
        #expect(fields["ratio"] == .double(0.1))
        #expect(try representation.decode(as: Listing.self) == listing)
    }

    @Test func jsonMatchesJSONEncoder() throws {
        let listing = Listing()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let expected = String(decoding: try encoder.encode(listing), as: UTF8.self)
        #expect(try CodableRepresentation(encoding: listing).json == expected)
    }

    @Test func jsonRoundTripsThroughTheType() throws {
        let listing = Listing()
        let typed = try CodableRepresentation(encoding: listing)
        let plain = try CodableRepresentation(json: typed.json)
        #expect(plain.dictionary()?["id"] == .string(listing.id.uuidString))
        #expect(plain.dictionary()?["listed"] == .double(1234.5))
        let decoded = try plain.decode(as: Listing.self)
        #expect(decoded == listing)
        #expect(try CodableRepresentation(encoding: decoded) == typed)
    }

    @Test func schemaNamesTheTypes() throws {
        let schema = try CodableSchema(Listing.self)
        #expect(schema == .object([
            "id": .uuid, "listed": .date, "photo": .data, "price": .decimal, "site": .url, "ratio": .double,
        ]))
        #expect(schema.description == "{id: uuid, listed: date, photo: data, price: decimal, ratio: double, site: url}")
        #expect(try JSONDecoder().decode(CodableSchema.self, from: JSONEncoder().encode(schema)) == schema)
    }

    @Test func aDifferenceShowsTypedValues() throws {
        let original = Listing()
        var edited = original
        edited.id = UUID(uuidString: "00000000-0000-8000-8000-000000000001")!
        edited.price = Decimal(string: "24.50")!
        let difference = try CodableDifference(from: original, to: edited)
        #expect(Array(difference) == [
            .replace(path: "id", old: .uuid(original.id), new: .uuid(edited.id)),
            .replace(path: "price", old: .decimal(original.price), new: .decimal(edited.price)),
        ])

        let received = try JSONDecoder().decode(CodableDifference.self, from: JSONEncoder().encode(difference))
        #expect(try original.applying(received) == edited)
    }

    @Test func floatsWidenToTheirShortestForm() throws {
        #expect(try CodableRepresentation(encoding: Float(0.1)) == .double(0.1))
        #expect(try CodableRepresentation(encoding: Float(-2.5e-3)) == .double(-2.5e-3))
        var values: [Float] = [
            0, -0.0, 1, -1, .pi, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
            .leastNormalMagnitude, .leastNonzeroMagnitude, .ulpOfOne, 16_777_217, 0.3,
        ]
        for bits in stride(from: UInt32(0), to: .max, by: 40_009) {
            values.append(Float(bitPattern: bits))
        }
        for value in values {
            let decoded = try CodableRepresentation(encoding: value).decode(as: Float.self)
            if value.isNaN {
                #expect(decoded.isNaN)
            } else {
                #expect(decoded.bitPattern == value.bitPattern, "\(value) came back as \(decoded)")
            }
        }
    }

    @Test func decimalsKeepEveryDigit() throws {
        let price = Decimal(string: "12345678901234567890.123456789")!
        let representation = try CodableRepresentation(encoding: price)
        #expect(representation == .decimal(price))
        #expect(try representation.decode(as: Decimal.self) == price)
        #expect(try CodableRepresentation(json: "0.1").decode(as: Decimal.self) == Decimal(string: "0.1"))
    }

    struct Post: Codable, Equatable {
        var title = "Hello"
        var tags: Set<String> = ["swift", "sync"]
        var readers: Set<UUID> = [UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!]
    }

    @Test func setsAreSets() throws {
        let post = Post()
        let representation = try CodableRepresentation(encoding: post)
        #expect(representation.dictionary()?["tags"] == .set(["sync", "swift"]))
        #expect(try representation.decode(as: Post.self) == post)
        #expect(try CodableRepresentation.set([3, 1, 2]).json == "[1,2,3]")
        #expect(CodableRepresentation.set([3, 1, 2]).description == "[1, 2, 3]")
        #expect(try CodableRepresentation(encoding: Set([3, 1, 2])) == .set([1, 2, 3]))
    }

    @Test func setsDifferByMembership() throws {
        let original = Post()
        var edited = original
        edited.tags = ["swift", "cloudkit"]
        let difference = try CodableDifference(from: original, to: edited)
        #expect(Array(difference) == [
            .insert(path: ["tags", .member("cloudkit")], element: "cloudkit"),
            .remove(path: ["tags", .member("sync")], element: "sync"),
        ])
        #expect(difference.map(\.description) == [#"+ tags{"cloudkit"}: "cloudkit""#, #"- tags{"sync"}: "sync""#])
        #expect(try original.applying(difference) == edited)
        #expect(try edited.applying(difference.inverse()) == original)
        #expect(try CodableSchema(Post.self)[["tags", .member("cloudkit")]] == .string)
    }

    @Test func setChangesTravelAsJSON() throws {
        let original = Post()
        var edited = original
        edited.readers = [UUID(uuidString: "00000000-0000-8000-8000-000000000001")!]
        edited.tags.insert("cloudkit")
        let difference = try CodableDifference(from: original, to: edited)
        let received = try JSONDecoder().decode(CodableDifference.self, from: JSONEncoder().encode(difference))
        #expect(try original.applying(received) == edited)

        let path: CodablePath = ["tags", .member("swift")]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(path), as: UTF8.self) == #"["tags",{"member":"swift"}]"#)
        #expect(try JSONDecoder().decode(CodablePath.self, from: encoder.encode(path)) == path)
        #expect(path.description == #"tags{"swift"}"#)
    }

    @Test func setChangesSquash() throws {
        let original = Post()
        var middle = original
        middle.tags.insert("cloudkit")
        let first = try CodableDifference(from: original, to: middle)
        let second = try CodableDifference(from: middle, to: original)
        let squashed = try #require(first.followed(by: second))
        #expect(squashed.isEmpty)
    }
}

