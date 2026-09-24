import Foundation
import Testing
@testable import Pergamenum

// PG-124 / #224: the one scheme policy every link-opening surface asks.

@Test(arguments: [
    "http://vibrofer.it",
    "https://vibrofer.it/prodotti",
    "mailto:ufficio@example.com",
    "message://%3Cabc@example.com%3E",
    "pergamenum://canvas?file=Board.canvas",
    // A scheme is case-insensitive (RFC 3986 §3.1).
    "HTTPS://vibrofer.it",
])
func aSchemeTheAppUsesIsOpenable(link: String) throws {
    let url = try #require(URL(string: link))
    #expect(LinkPolicy.isOpenable(url))
    #expect(LinkPolicy.isOpenable(link))
}

@Test(arguments: [
    "file:///Applications/Calculator.app",
    "javascript:alert(1)",
    "evil://payload",
])
func anyOtherSchemeIsRefused(link: String) throws {
    let url = try #require(URL(string: link))
    #expect(!LinkPolicy.isOpenable(url))
    #expect(!LinkPolicy.isOpenable(link))
}

@Test func aURLWithNoSchemeIsRefused() throws {
    // A relative reference has nothing to be opened by.
    let url = try #require(URL(string: "note/idea.md"))
    #expect(url.scheme == nil)
    #expect(!LinkPolicy.isOpenable(url))
}
