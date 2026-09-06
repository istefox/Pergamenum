import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 5 -
// R-08; ADR §D9.
//
// `PlaudQuote.fingerprint`'s production body is a tester-declared stub (see
// `Sources/Features/Recordings/PlaudQuote.swift`, "returns `raw` unchanged") - every
// assertion below that depends on the real five-step algorithm is red until the coder
// implements it. A few (documented inline) can pass trivially against the identity stub;
// that is expected, not a sign the test is weak (they will keep passing once the real
// algorithm exists, and the ones that matter will start failing loudly if a future change
// breaks them).

@Test func foldsAccents() {
    // "però" / "PERO" - the exact pair the ADR names.
    #expect(PlaudQuote.fingerprint("però") == PlaudQuote.fingerprint("PERO"))
}

@Test func foldsCase() {
    #expect(PlaudQuote.fingerprint("Sopralluogo Linea Quattro") == PlaudQuote.fingerprint("sopralluogo linea quattro"))
}

@Test func collapsesPunctuationAndWhitespace() {
    #expect(PlaudQuote.fingerprint("dobbiamo,  fare   qualcosa!") == PlaudQuote.fingerprint("dobbiamo fare qualcosa"))
}

@Test func treatsNfcAndNfdFormsAsEqual() {
    let nfc = "società".precomposedStringWithCanonicalMapping
    let nfd = "società".decomposedStringWithCanonicalMapping
    // `String`'s `==` compares by canonical equivalence (grapheme clusters), so `nfc != nfd`
    // is false here even though the two are stored as different scalar sequences - comparing
    // as `String` would make this guard always fail and hide a fixture that stopped exercising
    // two distinct Unicode forms. Compare the scalar sequences themselves instead.
    #expect(Array(nfc.unicodeScalars) != Array(nfd.unicodeScalars), "the fixture must actually exercise two different Unicode forms")
    #expect(PlaudQuote.fingerprint(nfc) == PlaudQuote.fingerprint(nfd))
}

@Test func anEmptyFingerprintNeverMatchesAnotherEmptyOne() {
    // ADR §D9 step 5, the guard that matters: two punctuation-only quotes both collapse
    // to "" through steps 1-4, and must still not dedup against each other.
    #expect(PlaudQuote.fingerprint("...") != PlaudQuote.fingerprint("???"))
}

@Test func sanitizedAndRawQuotesFingerprintTheSame() {
    // Re-asserted from this side too, per the brief: sanitation (`TranscriptNote
    // .sanitizedQuote`) must be invisible to the fingerprint, because dedup compares
    // the sanitized form written in the note against the raw form the service sends.
    let raw = "Testo > con # marcatori ^ e [parentesi] quadre\ne una nuova riga"
    let sanitized = TranscriptNote.sanitizedQuote(raw)
    #expect(PlaudQuote.fingerprint(sanitized) == PlaudQuote.fingerprint(raw))
}

@Test func realWordsWithDifferentPunctuationStillDiffer() {
    // Negative control: the empty-guard is about a wholly-punctuation quote, not a
    // license to conflate any two different sentences.
    #expect(PlaudQuote.fingerprint("prima frase") != PlaudQuote.fingerprint("seconda frase"))
}
