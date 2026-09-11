import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 §R-10 amendment (2026-09-11): a pasted inline image is decorative only when
// both the byte-weight and pixel-dimension signals agree.

@Test func smallInBothBytesAndPixelsIsDecorative() {
    let logo = EmailFixtureCorpus.solidColorPNG(width: 32, height: 32)
    #expect(InlineImageClassifier.isDecorative(logo))
}

@Test func lightInBytesButLargeInPixelsIsNotDecorative() {
    // A solid fill compresses tiny at any resolution - this is what a real screenshot or
    // photo compressing under the byte threshold looks like from the classifier's side.
    let screenshot = EmailFixtureCorpus.solidColorPNG(width: 800, height: 600)
    #expect(!InlineImageClassifier.isDecorative(screenshot))
}

@Test func heavyRegardlessOfDimensionsIsNotDecorative() {
    let heavy = Data(repeating: 0x42, count: 60_000)
    #expect(!InlineImageClassifier.isDecorative(heavy))
}

@Test func undecodableBytesAreNeverTreatedAsDecorative() {
    let undecodable = Data("hello".utf8)
    #expect(!InlineImageClassifier.isDecorative(undecodable))
}
