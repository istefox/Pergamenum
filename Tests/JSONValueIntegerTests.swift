import Foundation
import Testing
@testable import Pergamenum

// PG-279 (ADR-0065 §D13.6): an integer beyond 2^53 in a `.canvas` is re-encoded exactly, not
// rounded through a `Double`.

@Test func anIntegerBeyondTwoToTheFiftyThreeRoundTripsExactly() throws {
    let data = Data("""
    {"nodes":[{"id":"a1","type":"text","x":0,"y":0,"width":10,"height":10,"text":"A","foreign":9007199254740993}],\
    "edges":[],"stamp":-9007199254740993}
    """.utf8)
    let document = try CanvasDocument(data: data)
    #expect(document.node(id: "a1")?.unknown["foreign"] == .integer(9_007_199_254_740_993))
    #expect(document.unknown["stamp"] == .integer(-9_007_199_254_740_993))
    let encoded = String(decoding: try document.encoded(), as: UTF8.self)
    #expect(encoded.contains("\"foreign\" : 9007199254740993"))
    #expect(encoded.contains("\"stamp\" : -9007199254740993"))
}

@Test func anIntegerADoubleHoldsStaysANumber() throws {
    let data = Data(#"{"nodes":[],"edges":[],"n":3,"m":9007199254740992,"f":1.5}"#.utf8)
    let document = try CanvasDocument(data: data)
    #expect(document.unknown["n"] == .number(3))
    #expect(document.unknown["m"] == .number(9_007_199_254_740_992))
    #expect(document.unknown["f"] == .number(1.5))
}

@Test func anExactIntegerReadsAsADoubleForTheQueryLayer() {
    #expect(JSONValue.integer(9_007_199_254_740_993).doubleValue == 9_007_199_254_740_992)
}
