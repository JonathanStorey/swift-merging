// Not `@testable`, so these tests only see the public surface.
import Foundation
import Merging
import Testing

@Suite struct CodableEdgeCaseTests {
    @Test func setMembersWithTheSameTextHaveAFixedOrder() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1234.5)
        let members: CodableRepresentation = .set([.date(date), .string(date.ISO8601Format())])
        #expect(try members.json == #"["2001-01-01T00:20:34Z",1234.5]"#)
    }

    struct Wide: Codable, Equatable {
        var signed = Int128.min
        var unsigned = UInt128(Int128.max)
    }

    @Test func int128PropertiesRoundTrip() throws {
        let wide = Wide()
        let representation = try CodableRepresentation(encoding: wide)
        #expect(representation.dictionary()?["signed"] == .integer(.min))
        #expect(representation.dictionary()?["unsigned"] == .integer(.max))
        #expect(try representation.decode(as: Wide.self) == wide)
        #expect(try CodableSchema(Wide.self) == .object(["signed": .integer, "unsigned": .integer]))
        #expect(throws: EncodingError.self) { try CodableRepresentation(encoding: UInt128.max) }
    }

    @Test func nanDatesAndDecimalsEqualThemselves() {
        let date = Date(timeIntervalSinceReferenceDate: .nan)
        #expect(CodableRepresentation.date(date) == .date(date))
        #expect(CodableRepresentation.decimal(.nan) == .decimal(.nan))
        #expect(Set<CodableRepresentation>([.date(date), .date(date), .decimal(.nan), .decimal(.nan)]).count == 2)
    }

    struct Link: Codable, Equatable {
        var url: URL
    }

    @Test func urlsCompareByTheirAbsoluteForm() throws {
        let relative = URL(string: "b", relativeTo: URL(string: "https://example.com/a/")!)!
        let absolute = URL(string: "https://example.com/a/b")!
        #expect(CodableRepresentation.url(relative) == .url(absolute))
        #expect(Set<CodableRepresentation>([.url(relative), .url(absolute)]).count == 1)
        #expect(try CodableDifference(from: Link(url: relative), to: Link(url: absolute)).isEmpty)
        #expect(try CodableRepresentation(encoding: Link(url: relative)).decode(as: Link.self) == Link(url: relative))
    }
}
