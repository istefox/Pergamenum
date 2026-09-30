import Foundation
import Testing
@testable import Pergamenum

// ADR-0077 §D5, plan docs/plans/pg-147-core-app-shell-structure.md, Task 2 (PG-147,
// structure-NoteExport.swift-c0f).
//
// Three defects the exporter would inherit from the shared parsers once it reads them, fixed in
// the parsers for every reading surface at once: an intraword `_` opened emphasis (P1), a link's
// label was not parsed (P2), and any single bracketed character made a task line (P3).

// MARK: - P1: intraword underscore

@Test func anIntrawordUnderscoreOpensNothing() {
    #expect(MarkdownInlineParser.spans(in: "file_name_here") == [MarkdownSpan(text: "file_name_here")])
}

@Test func anIntrawordUnderscoreClosesNothing() {
    // The closing half: without it `_lieve_mente` reads as *lieve* followed by `mente`.
    #expect(MarkdownInlineParser.spans(in: "_lieve_mente") == [MarkdownSpan(text: "_lieve_mente")])
}

@Test func aRunOfUnderscoresIsJudgedByTheCharacterBeforeIt() {
    // The second `_` of `a__` follows a `_`, not a letter; read alone it would open emphasis and
    // the text would come back as `a_` *`b_`* ` c`.
    #expect(MarkdownInlineParser.spans(in: "a__b__ c") == [MarkdownSpan(text: "a__b__ c")])
}

@Test func aFlankedUnderscoreStillEmphasises() {
    #expect(MarkdownInlineParser.spans(in: "__forte__") == [MarkdownSpan(text: "forte", styles: [.strong])])
    #expect(MarkdownInlineParser.spans(in: "_lieve_") == [MarkdownSpan(text: "lieve", styles: [.emphasis])])
    #expect(MarkdownInlineParser.spans(in: "x _y_ z") == [
        MarkdownSpan(text: "x "), MarkdownSpan(text: "y", styles: [.emphasis]), MarkdownSpan(text: " z"),
    ])
}

@Test func anIntrawordAsteriskStillEmphasises() {
    // CommonMark allows `*` intraword; only `_` gains the rule.
    #expect(MarkdownInlineParser.spans(in: "a*b*c") == [
        MarkdownSpan(text: "a"), MarkdownSpan(text: "b", styles: [.emphasis]), MarkdownSpan(text: "c"),
    ])
}

// MARK: - P2: link labels

@Test func aLinkLabelIsParsed() {
    #expect(MarkdownInlineParser.spans(in: "[**forte**](https://x.it)") == [
        MarkdownSpan(text: "forte", styles: [.strong], link: .url("https://x.it")),
    ])
    #expect(MarkdownInlineParser.spans(in: "[a **b**](https://x.it)") == [
        MarkdownSpan(text: "a ", link: .url("https://x.it")),
        MarkdownSpan(text: "b", styles: [.strong], link: .url("https://x.it")),
    ])
}

@Test func aRemoteImageKeepsItsOneLinkSpan() {
    #expect(MarkdownInlineParser.spans(in: "![alt](https://x.it/a.png)") == [
        MarkdownSpan(text: "alt", link: .url("https://x.it/a.png")),
    ])
}

// MARK: - P3: task markers

@Test func aBracketedCharacterOutsideTheVocabularyIsABullet() {
    #expect(MarkdownBlockParser.blocks(in: "- [1] Rossi, 2020") == [.bulletList(["[1] Rossi, 2020"])])
    #expect(MarkdownBlockParser.blocks(in: "- [a] voce") == [.bulletList(["[a] voce"])])
}

@Test func theFourMarkersOfTheTaskIndexMakeTaskLines() {
    let blocks = MarkdownBlockParser.blocks(in: "- [ ] a\n- [x] b\n- [X] c\n- [-] d\n- [>] e")
    #expect(blocks == [.tasks([
        MarkdownBlock.TaskLine(isDone: false, marker: " ", text: "a"),
        MarkdownBlock.TaskLine(isDone: true, marker: "x", text: "b"),
        MarkdownBlock.TaskLine(isDone: true, marker: "X", text: "c"),
        MarkdownBlock.TaskLine(isDone: false, marker: "-", text: "d"),
        MarkdownBlock.TaskLine(isDone: false, marker: ">", text: "e"),
    ])])
}

@Test func aTaskWithNoSpaceAfterTheBoxStaysATask() {
    // `TaskParser` counts it, so the reading view draws it as one too.
    #expect(MarkdownBlockParser.blocks(in: "- [ ]attaccato") == [.tasks([
        MarkdownBlock.TaskLine(isDone: false, marker: " ", text: "attaccato"),
    ])])
}
