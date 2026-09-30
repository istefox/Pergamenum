import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

// PG-298, ADR-0070 §D4 (`docs/plans/pg-298-timeline-backspace-exclude.md`, Task 3) - R-08,
// R-09.
//
// Pins the Quick Look host's focus-claim opt-out. Applies only because Task 1 measured
// outcome A: the host claims first responder unconditionally at appearance and on every
// update, and a row click in the pratica timeline never takes it back (ADR-0070 §D4). The
// default (`claimsFocus == true`) must keep doing exactly what production does today on the
// Workspace board and the editor (R-09); the timeline opts out (R-08), wired in Task 5.
//
// Expected red until Task 5: `claimsFocusOnUpdate` and the record-and-hand-back pair
// (`claimFocusForPresentation`/`handBackFocus`) are still the stub bodies Task 3 declared.
//
// Measured, not assumed (this file's own header obligation): `HostedView`'s never-shown,
// never-key window still answers `window.firstResponder` correctly and still runs the
// `DispatchQueue.main.async` hop `QuickLookTarget.makeNSView` schedules once `settle()` pumps
// the run loop - confirmed with a throwaway probe before this file was written (responder
// read back as `QuickLookHostView` with the default `claimsFocus`). The third group below is
// kept on that measurement.

/// One row of `QuickLookClaimsFocusOnUpdateTests`'s truth table.
private struct ClaimsFocusOnUpdateCase {
    let claimsFocus: Bool
    let hasURLs: Bool
    let firstResponderIsText: Bool
    let isFirstResponder: Bool
    let expected: Bool
}

@MainActor
@Suite struct QuickLookClaimsFocusOnUpdateTests {
    private static let cases: [ClaimsFocusOnUpdateCase] = [
        // Today's Workspace/editor behaviour (R-09): claim, URLs present, no text field
        // holding focus, not already first responder.
        ClaimsFocusOnUpdateCase(
            claimsFocus: true, hasURLs: true, firstResponderIsText: false, isFirstResponder: false,
            expected: true
        ),
        ClaimsFocusOnUpdateCase(
            claimsFocus: true, hasURLs: false, firstResponderIsText: false, isFirstResponder: false,
            expected: false
        ),
        ClaimsFocusOnUpdateCase(
            claimsFocus: true, hasURLs: true, firstResponderIsText: true, isFirstResponder: false,
            expected: false
        ),
        ClaimsFocusOnUpdateCase(
            claimsFocus: true, hasURLs: true, firstResponderIsText: false, isFirstResponder: true,
            expected: false
        ),
        // Every claimsFocus == false answer is false, regardless of the rest.
        ClaimsFocusOnUpdateCase(
            claimsFocus: false, hasURLs: true, firstResponderIsText: false, isFirstResponder: false,
            expected: false
        ),
        ClaimsFocusOnUpdateCase(
            claimsFocus: false, hasURLs: false, firstResponderIsText: false, isFirstResponder: false,
            expected: false
        ),
        ClaimsFocusOnUpdateCase(
            claimsFocus: false, hasURLs: true, firstResponderIsText: true, isFirstResponder: false,
            expected: false
        ),
        ClaimsFocusOnUpdateCase(
            claimsFocus: false, hasURLs: true, firstResponderIsText: false, isFirstResponder: true,
            expected: false
        ),
    ]

    @Test func truthTable() {
        for testCase in Self.cases {
            let answer = QuickLookTarget.claimsFocusOnUpdate(
                claimsFocus: testCase.claimsFocus, hasURLs: testCase.hasURLs,
                firstResponderIsText: testCase.firstResponderIsText, isFirstResponder: testCase.isFirstResponder
            )
            #expect(
                answer == testCase.expected,
                """
                claimsFocus=\(testCase.claimsFocus) hasURLs=\(testCase.hasURLs) \
                firstResponderIsText=\(testCase.firstResponderIsText) \
                isFirstResponder=\(testCase.isFirstResponder)
                """
            )
        }
    }
}

/// A plain focusable `NSView`. Unlike `NSTextField`, `-makeFirstResponder:` makes this view
/// itself the window's first responder rather than a shared field editor - which is exactly
/// what makes `=== elsewhere`/`=== another` a meaningful assertion below (a field editor
/// swap is pinned separately, by `QuickLookRecordAndHandBackFocusFieldEditorTests`).
private final class FocusableView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
@Suite struct QuickLookRecordAndHandBackFocusTests {
    /// The shape `Tests/NoteFindTests.swift:280-293` already uses: a real, unshown window
    /// with a plain focusable view and the real `QuickLookHostView`, so first responder is
    /// AppKit's own decision rather than a value this test could get right by construction.
    private func fixture() -> (window: NSWindow, elsewhere: NSView, host: QuickLookHostView) {
        let elsewhere = FocusableView(frame: NSRect(x: 0, y: 100, width: 200, height: 24))
        let host = QuickLookHostView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 140))
        container.addSubview(host)
        container.addSubview(elsewhere)
        let window = NSWindow(
            contentRect: container.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = container
        window.makeFirstResponder(elsewhere)
        return (window, elsewhere, host)
    }

    @Test func claimFocusForPresentationMakesTheHostFirstResponder() {
        let (window, _, host) = fixture()
        defer { window.orderOut(nil) }

        host.claimFocusForPresentation()

        #expect(window.firstResponder === host)
    }

    @Test func handBackFocusRestoresWhatWasRecordedBeforeTheClaim() {
        let (window, elsewhere, host) = fixture()
        defer { window.orderOut(nil) }

        host.claimFocusForPresentation()
        host.handBackFocus()

        #expect(window.firstResponder === elsewhere)
    }

    @Test func handBackFocusLeavesAnInterveningResponderAlone() {
        let (window, _, host) = fixture()
        defer { window.orderOut(nil) }
        let another = FocusableView(frame: NSRect(x: 0, y: 40, width: 200, height: 24))
        window.contentView?.addSubview(another)

        host.claimFocusForPresentation()
        window.makeFirstResponder(another)
        host.handBackFocus()

        #expect(window.firstResponder === another)
    }

    /// PG-307: nobody held the keyboard before the preview (the window is first responder),
    /// so the host keeps it once the panel is gone and a bare space can reopen the panel.
    @Test func handBackFocusKeepsTheHostWhenNobodyHeldTheKeyboard() {
        let (window, _, host) = fixture()
        defer { window.orderOut(nil) }
        window.makeFirstResponder(nil)
        #expect(window.firstResponder === window)

        host.claimFocusForPresentation()
        host.handBackFocus()

        #expect(window.firstResponder === host)
    }

    /// PG-306: the editor's shape. The note's text view holds the keyboard (a plain
    /// `NSTextView`, not a field editor), so an embed preview claims first responder for the
    /// panel and gives the keyboard back to the text view when the panel closes.
    @Test func handBackFocusRestoresATextViewThatWasEditing() {
        let (window, _, host) = fixture()
        defer { window.orderOut(nil) }
        let textView = NSTextView(frame: NSRect(x: 0, y: 40, width: 200, height: 24))
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        #expect(window.firstResponder === textView)

        host.claimFocusForPresentation()
        #expect(window.firstResponder === host)
        host.handBackFocus()

        #expect(window.firstResponder === textView)
    }

    @Test func handBackFocusDoesNothingWhenTheRecordedViewLeftTheWindow() {
        let (window, elsewhere, host) = fixture()
        defer { window.orderOut(nil) }

        host.claimFocusForPresentation()
        elsewhere.removeFromSuperview()
        window.makeFirstResponder(host)
        host.handBackFocus()

        #expect(window.firstResponder === host)
    }
}

/// Pins `QuickLookHostView.handBackTarget(for:)`: what is actually recorded and handed
/// back while an `NSTextField` is being edited is the field itself, not the window's
/// shared field editor - `NSTextField`'s own `-makeFirstResponder:` makes the field
/// editor first responder with its `delegate` set to the field, which is what
/// `QuickLookRecordAndHandBackFocusTests` above deliberately avoids asserting on with a
/// plain `FocusableView` fixture instead.
@MainActor
@Suite struct QuickLookHandBackFocusFieldEditorTests {
    @Test func handBackFocusRestoresEditingInAFieldThatWasBeingEdited() {
        let field = NSTextField(frame: NSRect(x: 0, y: 100, width: 200, height: 24))
        let host = QuickLookHostView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 140))
        container.addSubview(host)
        container.addSubview(field)
        let window = NSWindow(
            contentRect: container.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = container
        window.makeFirstResponder(field)
        defer { window.orderOut(nil) }

        host.claimFocusForPresentation()
        host.handBackFocus()

        #expect((window.firstResponder as? NSTextView)?.delegate === field)
    }
}

/// R-09: the default keeps doing exactly what production does today, pinned in-process
/// rather than only by review (ADR-0070 §D4's own condition for this group).
@MainActor
@Suite struct QuickLookDefaultClaimStaysUnchangedHostedTests {
    private func tempFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "pg298-quicklook-\(UUID().uuidString).txt"
        )
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func theDefaultClaimsFirstResponderAtAppearance() async throws {
        let host = HostedView(
            Color.clear.quickLook(urls: [try tempFile()], isPresented: .constant(false)),
            size: CGSize(width: 100, height: 100)
        )
        defer { host.tearDown() }
        await host.settle()

        #expect(host.window.firstResponder is QuickLookHostView)
        #expect(host.neverShown)
    }

    @Test func claimsFocusFalseNeverTakesFirstResponder() async throws {
        let host = HostedView(
            Color.clear.quickLook(urls: [try tempFile()], isPresented: .constant(false), claimsFocus: false),
            size: CGSize(width: 100, height: 100)
        )
        defer { host.tearDown() }
        await host.settle()

        #expect(!(host.window.firstResponder is QuickLookHostView))
        #expect(host.neverShown)
    }
}
