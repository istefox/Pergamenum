import Foundation
import Testing
@testable import Pergamenum

// ADR-0074 §D9, plan pg-144 Task 2 (R-01, R-02). Pins the line-scan primitives in
// `Sources/Core/Editor/LineScan.swift` that `ListContinuation` and `LineFormat` share.

struct LineScanTests {
    private func spans(_ text: String) -> [[Int]] {
        LineScan.lines(in: text as NSString).map { [$0.start, $0.contentEnd, $0.end] }
    }

    @Test func emptyTextYieldsOneEmptyLine() {
        #expect(spans("") == [[0, 0, 0]])
    }

    @Test func linesSplitOnNewlines() {
        #expect(spans("ab\ncd") == [[0, 2, 3], [3, 5, 5]])
    }

    @Test func crlfIsOneTerminator() {
        #expect(spans("ab\r\ncd") == [[0, 2, 4], [4, 6, 6]])
    }

    @Test func trailingTerminatorYieldsTrailingEmptyLine() {
        #expect(spans("ab\n") == [[0, 2, 3], [3, 3, 3]])
        #expect(spans("ab\r\n") == [[0, 2, 4], [4, 4, 4]])
    }

    @Test func indentCountsSpacesAndTabs() {
        let text = " \t x" as NSString
        let line = LineScan.Line(start: 0, contentEnd: text.length, end: text.length)
        #expect(LineScan.indentLength(on: line, in: text) == 3)
    }

    @Test func indentStopsAtContentEndAndIsZeroWithoutIndent() {
        let text = "x  \n" as NSString
        #expect(LineScan.indentLength(on: LineScan.Line(start: 0, contentEnd: 3, end: 4), in: text) == 0)
        let blank = "   " as NSString
        #expect(LineScan.indentLength(on: LineScan.Line(start: 0, contentEnd: 2, end: 3), in: blank) == 2)
    }

    @Test(arguments: [" ", "x", "X", ">", "-"])
    func checklistStatesAreAccepted(_ state: String) {
        let text = "[\(state)]" as NSString
        #expect(LineScan.isChecklistMarker(in: text, at: 0, limit: text.length))
    }

    @Test(arguments: ["a", "?", "*", "y"])
    func otherChecklistStatesAreRefused(_ state: String) {
        let text = "[\(state)]" as NSString
        #expect(!LineScan.isChecklistMarker(in: text, at: 0, limit: text.length))
    }

    @Test func checklistRefusesMalformedAndBeyondLimit() {
        let text = "[x] a" as NSString
        #expect(LineScan.isChecklistMarker(in: text, at: 0, limit: 3))
        #expect(!LineScan.isChecklistMarker(in: text, at: 0, limit: 2))
        #expect(!LineScan.isChecklistMarker(in: "(x)" as NSString, at: 0, limit: 3))
        #expect(!LineScan.isChecklistMarker(in: "[x)" as NSString, at: 0, limit: 3))
    }

    @Test func matchesFindsNeedleAtIndex() {
        let text = "ab- cd" as NSString
        #expect(LineScan.matches("- ", in: text, at: 2, limit: text.length))
        #expect(!LineScan.matches("- ", in: text, at: 1, limit: text.length))
    }

    @Test func matchesRefusesPastLimit() {
        let text = "ab- cd" as NSString
        #expect(!LineScan.matches("- ", in: text, at: 2, limit: 3))
        #expect(LineScan.matches("- ", in: text, at: 2, limit: 4))
    }

    @Test func isDigitIsZeroToNineOnly() {
        for code in UInt16(0x30)...UInt16(0x39) { #expect(LineScan.isDigit(code)) }
        #expect(!LineScan.isDigit(0x2F))
        #expect(!LineScan.isDigit(0x3A))
        #expect(!LineScan.isDigit(0x61))
    }
}
