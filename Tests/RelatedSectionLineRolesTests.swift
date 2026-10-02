import Foundation
import Testing
@testable import Pergamenum

// PG-378: `RelatedSection.parse` reads a line as a link only in the role `RelatedLink` gives it,
// so «Collega», the linter's count (W-09) and the W-06 comparison agree on what a link bullet is.

private let fencedSection = "## Note correlate\n\n- [[A]] — a\n\n```\n- [[B]] — in a fence\n```\n"

@Test func aLinkInsideAFenceIsNotAStructuralLink() {
    #expect(RelatedSection.parse(from: fencedSection).map(\.target) == ["A"])
}

@Test func collegaTowardsATitleOnlyInAFenceWritesTheBullet() throws {
    let text = "---\ndate: 2026-10-02\ntags:\n  - type-note\n---\n\n" + fencedSection
    let linked = try RelatedLink.add(target: "B", reason: "b", to: text, selfTitle: "T")
    #expect(linked.contains("- [[A]] — a\n- [[B]] — b\n"))
    #expect(RelatedSection.parse(from: NoteDocument.parse(linked).body).map(\.target) == ["A", "B"])
}

@Test func aNestedSubItemIsNotAStructuralLink() {
    let body = "## Note correlate\n\n- [[A]] — a\n  - [[B]] — a sub-item of A\n"
    #expect(RelatedSection.parse(from: body).map(\.target) == ["A"])
}

@Test func aLineIndentedFourColumnsIsNotAStructuralLink() {
    let body = "## Note correlate\n\n- [[A]] — a\n\n    - [[B]] — indented code\n"
    #expect(RelatedSection.parse(from: body).map(\.target) == ["A"])
}

@Test func aBulletIndentedUpToThreeColumnsStillCounts() {
    // Three columns is a bullet (CommonMark) when it does not sit right under another one;
    // right under one it is that bullet's sub-item, as `RelatedLink` reads it.
    let body = "## Note correlate\n\n   - [[A]] — a\n\n- [[B]] — b\n   - [[C]] — a sub-item of B\n"
    #expect(RelatedSection.parse(from: body).map(\.target) == ["A", "B"])
}

@Test func fencedLinesDoNotRaiseTooManyLinks() throws {
    let fence = (1...6).map { "- [[F\($0)]] — f" }.joined(separator: "\n")
    let body = "## Note correlate\n\n- [[A]] — a\n\n```\n\(fence)\n```\n"
    let text = "---\ndate: 2026-10-02\ntags:\n  - type-note\n---\n\n" + body
    _ = try RelatedLink.add(target: "B", reason: "b", to: text, selfTitle: "T")
}
