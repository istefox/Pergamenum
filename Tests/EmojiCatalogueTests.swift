import Testing
@testable import Pergamenum

/// The emoji `:` offers, and the filter that narrows them.
///
/// A closed catalogue's tests are mostly about the catalogue being coherent: a duplicate
/// name is two rows a person cannot tell apart, and a duplicate glyph is a row that can
/// never be reached because the first one always ranks the same or better.

@Test func theCatalogueHasNoDuplicateNameOrGlyph() {
    let names = EmojiCatalogue.entries.map(\.name)
    let glyphs = EmojiCatalogue.entries.map(\.glyph)
    #expect(Set(names).count == names.count)
    #expect(Set(glyphs).count == glyphs.count)
}

@Test func everyEntryCarriesAtLeastOneKeyword() {
    // Without keywords an entry is reachable only by someone who already knows the Italian
    // name it was filed under, which is the whole failure the keywords exist to prevent.
    let bare = EmojiCatalogue.entries.filter(\.keywords.isEmpty)
    #expect(bare.isEmpty, "voci senza parole chiave: \(bare.map(\.name))")
}

@Test func anEmptyQueryOffersTheWholeCatalogue() {
    // `:` alone has to show something. An empty list would read as "no emoji here".
    #expect(EmojiCatalogue.matching("") .count == EmojiCatalogue.entries.count)
}

@Test func theNameItselfOutranksAWordInsideAnotherName() {
    let matches = EmojiCatalogue.matching("data")
    #expect(matches.first?.name == "data")
}

@Test func anEnglishKeywordFindsAnItalianName() {
    // The names are Italian because the interface is; the keywords are how the other half
    // of this person's vocabulary still lands on the right row.
    #expect(EmojiCatalogue.matching("target").contains { $0.glyph == "🎯" })
    #expect(EmojiCatalogue.matching("warning").contains { $0.glyph == "⚠️" })
}

@Test func aQueryMatchingNothingOffersNothing() {
    // Not "everything", which is what a subsequence filter would do with a stray query.
    #expect(EmojiCatalogue.matching("zqx").isEmpty)
}

@Test func aSubsequenceReachesWhatNoWordStartWould() {
    // Stefano asked for fuzzy on 2026-08-18 and this is what it buys: a name half-remembered,
    // or typed without its vowels, still lands.
    #expect(EmojiCatalogue.matching("stblmnt").contains { $0.glyph == "🏭" })
    #expect(EmojiCatalogue.matching("crsct").contains { $0.glyph == "📈" })
    #expect(EmojiCatalogue.matching("ppun").contains { $0.glyph == "📝" })
}

@Test func aWordStartAlwaysOutranksASubsequence() {
    // **This is the invariant the fuzzy tier had to preserve**, and the reason it sits below
    // the other three rather than replacing them. `EmojiCatalogueTests` used to assert that
    // `ppun` found nothing at all - the rule the slash menu settled on - and that assertion is
    // deliberately gone: fuzzy is on for emoji now. What must not change is the top of the
    // list. Everything matching a word start keeps its place; fuzzy only ever appends.
    let matches = EmojiCatalogue.matching("cal")
    let wordStart = matches.prefix { entry in
        entry.name.hasPrefix("cal") || entry.keywords.contains { $0.hasPrefix("cal") }
    }
    #expect(!wordStart.isEmpty, "nessuna corrispondenza per inizio parola: il caso non prova niente")
    // Nothing reached only as a subsequence may appear before them.
    #expect(matches.prefix(wordStart.count).allSatisfy { entry in
        entry.name.hasPrefix("cal") || entry.keywords.contains { $0.hasPrefix("cal") }
    })
}

@Test func fuzzyDoesNotMakeTheListAlwaysAnswer() {
    // A subsequence filter that matches everything is a filter that says nothing. `zqx` has to
    // stay empty even with fuzzy on.
    #expect(EmojiCatalogue.matching("zqx").isEmpty)
}
