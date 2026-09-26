import Foundation
import Testing
@testable import Pergamenum

// The command-line grammar both connectors parse before they dispatch anything
// (ADR-0063 §D3). A refused command line is a command that cannot write: `perg` answers
// with usage and `pergamenum-mcp` exits 1, both before any vault is touched.

// MARK: - A value-taking option never eats the next flag (R-08)

@Test func anOptionFollowedByAFlagIsAMissingValue() {
    // Before: `--folder` took `--dry-run` as its value and the write was real, into a
    // folder named `--dry-run`.
    #expect(throws: Arguments.ParseError.missingValue("folder")) {
        try Arguments(["note", "new", "T", "--folder", "--dry-run"])
    }
}

@Test func anOptionFollowedByAnotherOptionIsAMissingValue() {
    #expect(throws: Arguments.ParseError.missingValue("folder")) {
        try Arguments(["--folder", "--title", "x"])
    }
}

// MARK: - Two shapes that are refused outright (R-09)

@Test func aFlagSpelledWithAValueIsRefused() {
    // Before: `--dry-run=true` landed among the options, `has("dry-run")` missed it and
    // the write was real.
    #expect(throws: Arguments.ParseError.flagTakesNoValue("dry-run")) {
        try Arguments(["note", "new", "T", "--dry-run=true"])
    }
    #expect(throws: Arguments.ParseError.flagTakesNoValue("json")) {
        try Arguments(["--json=1"])
    }
}

@Test func aBareDoubleDashIsRefused() {
    #expect(throws: Arguments.ParseError.unknownFlagSyntax("--")) {
        try Arguments(["note", "--", "x"])
    }
}

// MARK: - What stays legal (R-10)

@Test func anEqualsValueMayStartWithDoubleDash() throws {
    // The escape hatch for a value that really does begin with `--`.
    let arguments = try Arguments(["note", "new", "--title=--strange"])
    #expect(arguments["title"] == "--strange")
}

@Test func aNegativeNumberIsAnOrdinaryValue() throws {
    // A single dash is not the start of an option, so `-1` reaches the limit rule, which
    // refuses it with its own sentence (ADR-0063 §D1).
    let arguments = try Arguments(["journal", "log", "--limit", "-1"])
    #expect(arguments["limit"] == "-1")
}

@Test func aTrailingOptionIsAMissingValue() {
    #expect(throws: Arguments.ParseError.missingValue("folder")) {
        try Arguments(["--folder"])
    }
}

@Test func flagsAndOptionsStillParse() throws {
    let arguments = try Arguments(["note", "new", "T", "--folder", "A", "--dry-run", "--json"])
    #expect(arguments.words == ["note", "new", "T"])
    #expect(arguments["folder"] == "A")
    #expect(arguments.has("dry-run"))
    #expect(arguments.has("json"))
}
