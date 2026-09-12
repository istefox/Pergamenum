import Foundation
import Testing
@testable import Pergamenum

// ADR-0042 (Pratiche inline image placeholders) §D2, §D4, §D6.
@Suite struct MessageInlineImageTests {
    // MARK: - placeholder

    @Test func placeholderIsPlainTextNoLinkNoWikilink() {
        let placeholder = MessageInlineImage.placeholder
        #expect(!placeholder.contains("cid:"))
        #expect(!placeholder.contains("![["))
        #expect(!placeholder.contains("]("))
    }

    // MARK: - replacingReferences

    @Test func replacingReferencesRemovesWholeMarkdownConstruct() {
        let result = MessageInlineImage.replacingReferences(
            to: "abc", in: "testo ![Logo](cid:abc) coda", with: "X"
        )
        #expect(result == "testo X coda")
    }

    @Test func replacingReferencesWithEmptyStringLeavesNoRemnant() {
        let result = MessageInlineImage.replacingReferences(
            to: "abc", in: "testo ![Logo](cid:abc) coda", with: ""
        )
        #expect(result == "testo  coda")
        #expect(!result.contains("!["))
        #expect(!result.contains("]("))
    }

    @Test func replacingReferencesReplacesBareReferenceInPlainTextBody() {
        let result = MessageInlineImage.replacingReferences(
            to: "abc", in: "vedi immagine cid:abc", with: "X"
        )
        #expect(result == "vedi immagine X")
    }

    @Test func replacingReferencesReplacesBothFormsOfSameID() {
        let result = MessageInlineImage.replacingReferences(
            to: "abc", in: "![Logo](cid:abc) e anche cid:abc qui", with: "X"
        )
        #expect(result == "X e anche X qui")
    }

    @Test func replacingReferencesEscapesRegexMetacharactersInContentID() {
        let contentID = "image001.png@01DA5C3E.9F2B1C40"
        let result = MessageInlineImage.replacingReferences(
            to: contentID, in: "![Logo](cid:\(contentID)) testo", with: "X"
        )
        #expect(result == "X testo")
    }

    // MARK: - referencesContentID

    @Test func referencesContentIDFalseWhenBodyNeverMentionsIt() {
        #expect(!MessageInlineImage.referencesContentID("abc", in: "nessuna menzione qui"))
    }

    @Test func referencesContentIDTrueForMarkdownConstruct() {
        #expect(MessageInlineImage.referencesContentID("abc", in: "![Logo](cid:abc)"))
    }

    @Test func referencesContentIDTrueForBareForm() {
        #expect(MessageInlineImage.referencesContentID("abc", in: "vedi cid:abc"))
    }

    // MARK: - resolvingDeferralTokens

    @Test func resolvingDeferralTokensOrdersByTextThenByAppearanceNotByOrdinal() {
        let token7 = MessageInlineImage.deferralToken(forPart: 7)
        let token2 = MessageInlineImage.deferralToken(forPart: 2)
        // Reversed ordinals on purpose (ADR-0042 §D6): token 7 sits in the third text,
        // token 2 in the first. The recorded order must follow the texts, not the
        // ordinal numbers.
        let texts = ["primo \(token2) testo", "secondo testo", "terzo \(token7) testo"]
        let ids: [Int: String] = [2: "id-two", 7: "id-seven"]

        let result = MessageInlineImage.resolvingDeferralTokens(in: texts, contentIDByOrdinal: ids)

        #expect(result.pending == ["id-two", "id-seven"])
        #expect(result.texts[0] == "primo \(MessageInlineImage.placeholder) testo")
        #expect(result.texts[1] == "secondo testo")
        #expect(result.texts[2] == "terzo \(MessageInlineImage.placeholder) testo")
    }

    @Test func resolvingDeferralTokensTwoTokensSamePartInOneText() {
        let token = MessageInlineImage.deferralToken(forPart: 3)
        let text = "uno \(token) due \(token) tre"
        let ids: [Int: String] = [3: "id-three"]

        let result = MessageInlineImage.resolvingDeferralTokens(in: [text], contentIDByOrdinal: ids)

        #expect(result.pending == ["id-three", "id-three"])
        #expect(result.texts[0] == "uno \(MessageInlineImage.placeholder) due \(MessageInlineImage.placeholder) tre")
    }

    @Test func resolvingDeferralTokensNoTokensReturnsUnchanged() {
        let texts = ["nessun token qui", "né qui"]
        let result = MessageInlineImage.resolvingDeferralTokens(in: texts, contentIDByOrdinal: [:])
        #expect(result.texts == texts)
        #expect(result.pending.isEmpty)
    }
}
