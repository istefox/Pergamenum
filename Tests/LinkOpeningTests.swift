import Testing
@testable import Pergamenum

/// R-21 (ADR-0083 §D2): the click variants are read in the Coordinator through one pure function,
/// so the four Shift/Option combinations are a table and the order of the two modifiers is pinned
/// once. Option wins over Shift because "the other column" is the stronger move and a person
/// holding both meant more, not less.
@Suite struct LinkOpeningTests {
    struct Combination: Sendable, CustomTestStringConvertible {
        let shift: Bool
        let option: Bool
        let expected: LinkOpening

        var testDescription: String { "shift: \(shift), option: \(option)" }
    }

    @Test(arguments: [
        Combination(shift: false, option: false, expected: .replace),
        Combination(shift: true, option: false, expected: .newTab),
        Combination(shift: false, option: true, expected: .otherColumn),
        Combination(shift: true, option: true, expected: .otherColumn),
    ])
    func eachShiftAndOptionCombinationMapsToOneHow(_ combination: Combination) {
        #expect(
            LinkOpening.forClick(shift: combination.shift, option: combination.option)
                == combination.expected
        )
    }

    @Test func optionWinsOverShiftWhenBothAreHeld() {
        #expect(LinkOpening.forClick(shift: true, option: true) == .otherColumn)
        #expect(LinkOpening.forClick(shift: true, option: true) != .newTab)
    }
}
