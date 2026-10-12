import AppKit
import Foundation
@testable import Pergamenum

// ADR-0093 §D9, plan docs/plans/scoped-layout-followup.md, Task 7 (R-13).
//
// The four edits that change structure beyond their line, so the restyle falls back to a wide one:
// a fence opened with no fence below, a fence opened above later fences, `[[` typed with no `]]`
// below, and `]]` typed with the last `]]` far above. The shape of `FallbackScenario`: each is
// prepared before any measurement, typed once per run and taken back. Printed by the bench script
// with `--structural`, never asserted on time. Kept apart from `RestyleBudgetSupport.swift` for
// `file_length`.

/// A hosted editor prepared for one structural keystroke, which it types and takes back.
///
/// Where each path lands, in the note as the budget builds it:
/// - `fence-open-last`: a line holding two backticks is appended after the note's last line, and the
///   keystroke is the third, so no fence is below it;
/// - `fence-open-above`: the same line is inserted after the first group's paragraph, so every later
///   fence of the `fences` variant pairs differently once the keystroke is typed;
/// - `wikilink-open`: a line holding one `[` is appended and the keystroke is the second `[`, so no
///   `]]` is below it;
/// - `wikilink-close-far`: a line holding `[[abc]` is appended and the keystroke is the second `]`.
///   The note's own `[[` and `]]` from its middle on are written `((` and `))` (same length), so the
///   last `]]` above the edit is half a note away.
@MainActor
struct StructuralScenario {
    /// How the coordinator's styling counters moved across one keystroke.
    struct Outcome {
        var before: RestyleLog
        var after: RestyleLog
        /// The note's length after the keystroke, which a full restyle covers.
        var textLength: Int
        var fulls: Int { after.full - before.full }
        var incrementals: Int { after.incremental - before.incremental }
        /// What the restyle covered: the note for a full one, the dirty range otherwise.
        var dirty: Int { fulls >= 1 ? textLength : (after.lastDirtyRange?.length ?? 0) }
    }

    let fixture: ScrolledEditorFixture
    let path: RestyleBudget.StructuralPath
    /// Where the keystroke lands, in the note as prepared.
    let location: Int
    /// The one character the keystroke types.
    let typed: String
    /// The note as prepared, before the keystroke.
    let prepared: String
    /// What a scope built from `prepared` decides for the keystroke: replayed on the pure type, so the
    /// reason is read without a hook in the coordinator.
    let expectedDecision: RestyleScope.Decision?
    /// The length of the note as prepared, which `restore()` returns to.
    private let baseLength: Int

    init(_ c: RestyleBudget.Case, path: RestyleBudget.StructuralPath) {
        var note = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        if path == .wikilinkCloseFar { note = Self.withoutLinksInTheSecondHalf(note) }
        let ns = note as NSString
        let fixture = ScrolledEditorFixture(text: note)
        var location = ns.length
        var typed = "`"
        switch path {
        case .fenceOpenLast:
            fixture.replace(NSRange(location: ns.length, length: 0), with: "\n``")
            location = ns.length + 3
        case .fenceOpenAbove:
            let first = ns.range(of: "Altro testo con")
            let at = first.location == NSNotFound ? 0 : ns.lineRange(for: first).upperBound - 1
            fixture.replace(NSRange(location: at, length: 0), with: "\n\n``")
            location = at + 2
        case .wikilinkOpen:
            fixture.replace(NSRange(location: ns.length, length: 0), with: "\n[")
            location = ns.length + 2
            typed = "["
        case .wikilinkCloseFar:
            fixture.replace(NSRange(location: ns.length, length: 0), with: "\n[[abc]")
            location = ns.length + 7
            typed = "]"
        }
        fixture.openLikeTheApp()
        self.fixture = fixture
        self.path = path
        self.location = location
        self.typed = typed
        let text = fixture.textView.string
        prepared = text
        baseLength = (text as NSString).length
        expectedDecision = Self.decision(for: typed, at: location, in: text)
    }

    /// The note with its `[[` and `]]` from the middle on written `((` and `))`: the same length and
    /// lines, and no `]]` after the middle.
    static func withoutLinksInTheSecondHalf(_ note: String) -> String {
        let ns = note as NSString
        let middle = ns.length / 2
        let tail = NSRange(location: middle, length: ns.length - middle)
        let opened = ns.replacingOccurrences(of: "[[", with: "((", options: [], range: tail)
        let closed = (opened as NSString).replacingOccurrences(of: "]]", with: "))", options: [], range: tail)
        return closed
    }

    /// The decision a fresh scope over `text` takes for `string` typed at `location`.
    static func decision(for string: String, at location: Int, in text: String) -> RestyleScope.Decision? {
        var scope = RestyleScope(text: text)
        let length = (string as NSString).length
        let after = (text as NSString).replacingCharacters(in: NSRange(location: location, length: 0), with: string)
        scope.record(StorageEdit(range: NSRange(location: location, length: length), delta: length), in: after as NSString)
        return scope.take()
    }

    /// The measured keystroke.
    func keystroke() {
        fixture.type(typed, at: location)
    }

    /// Takes back whatever the keystroke inserted, so the next run starts from the prepared note.
    /// Nothing when the note is as it was prepared.
    func restore() {
        let extra = (fixture.textView.string as NSString).length - baseLength
        guard extra > 0 else { return }
        fixture.replace(NSRange(location: location, length: extra), with: "")
    }

    /// One keystroke, and how it moved the styling counters; the note is restored afterwards.
    func outcome() -> Outcome {
        restore()
        let before = fixture.coordinator.restyleLog
        keystroke()
        let after = fixture.coordinator.restyleLog
        let length = (fixture.textView.string as NSString).length
        restore()
        return Outcome(before: before, after: after, textLength: length)
    }
}
