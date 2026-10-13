import AppKit
import Testing
@testable import Pergamenum

// ADR-0081 §D1 to §D7, plan `docs/plans/pg-385-n2-page.md`, Task 6 (R-13, R-14).
//
// The geometry of the gutter, measured through a real layout. One hosted editor per case
// (`ScrolledEditorFixture`), and for every case the same question twice: where does the first
// content character sit with the caret elsewhere (the marker concealed), and where with the
// caret in the paragraph (the marker revealed, `applyReveal` run)? The two must agree within
// 0.5 pt, and each must sit where the ADR says the content column is.
//
// The content origin is the `x`, in the text view's coordinates, of the first content character:
// the text segment's frame in the layout manager after `ensureLayout` for that range, plus the
// text container's origin. `firstRect` is not used (CLAUDE.md: a zero rectangle for a range
// TextKit 2 has not laid out can pass an assertion by accident). `bodyColumnIsTodaysAtReadableWidth`
// is the check that this measurement is the right one: it is green on today's tree.
//
// G is 48 pt (`Theme.emergency`, which the fixture styles with). The `H2` badge is not pinned:
// G2 declined it (2026-10-07).

private let gutterWidth: CGFloat = Theme.emergency.spacing(.gutter)
private let tolerance: CGFloat = 0.5

// MARK: - The hosted page

@MainActor
private struct Page {
    let fixture: ScrolledEditorFixture
    let note: String

    init(_ note: String, width: CGFloat, readableWidth: Bool = true) {
        self.note = note
        self.fixture = ScrolledEditorFixture(text: note, width: width, readableWidth: readableWidth)
    }

    var textView: CompletingTextView { fixture.textView }
    var layout: NSTextLayoutManager { textView.textLayoutManager! }
    var content: NSTextContentStorage { textView.textContentStorage! }
    var decorations: EditorDecorationDelegate { fixture.coordinator.decorations }

    /// The width the readable-width arithmetic is run against: the clip view's own.
    var viewWidth: CGFloat { fixture.scrollView.contentView.bounds.width }
    var padding: CGFloat { textView.textContainer?.lineFragmentPadding ?? 5 }

    func offset(of needle: String, occurrence: Int = 0) -> Int {
        var from = 0
        var found = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            found = (note as NSString).range(
                of: needle, range: NSRange(location: from, length: (note as NSString).length - from)
            )
            from = NSMaxRange(found)
        }
        return found.location
    }

    /// Moves the caret and runs the reveal pass, the way a key or a click would.
    func place(caretAt location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        fixture.coordinator.applyReveal(to: textView)
    }

    func isRevealed(_ paragraphOffset: Int) -> Bool {
        decorations.revealedParagraphs.contains(paragraphOffset)
    }

    private func textRange(_ offset: Int, length: Int = 1) -> NSTextRange? {
        guard let start = content.location(content.documentRange.location, offsetBy: offset),
              let end = content.location(start, offsetBy: length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// The `x` of the character at `offset`, in the text view's coordinates, laid out first.
    func originX(ofOffset offset: Int) -> CGFloat? {
        guard let range = textRange(offset) else { return nil }
        layout.ensureLayout(for: range)
        var x: CGFloat?
        layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
            x = frame.minX
            return false
        }
        return x.map { $0 + textView.textContainerOrigin.x }
    }

    /// The offset at which the paragraph's second line begins, or nil if it does not wrap.
    func secondLineStart(ofParagraphAt paragraphOffset: Int) -> Int? {
        guard let range = textRange(paragraphOffset) else { return nil }
        layout.ensureLayout(for: layout.documentRange)
        var start: Int?
        layout.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) { fragment in
            let lines = fragment.textLineFragments
            if lines.count > 1 { start = paragraphOffset + lines[1].characterRange.location }
            return false
        }
        return start
    }
}

/// One content origin measured both ways. `concealed` has the caret in the last paragraph;
/// `revealed` has it in the paragraph under test.
@MainActor
private struct Measured {
    let concealed: CGFloat
    let revealed: CGFloat
}

@MainActor
private func measure(
    _ page: Page, paragraph: Int, content: Int, awayFrom away: Int, sourceLocation: SourceLocation = #_sourceLocation
) -> Measured? {
    page.place(caretAt: away)
    #expect(
        !page.isRevealed(paragraph), "il paragrafo e gia rivelato con il cursore altrove",
        sourceLocation: sourceLocation
    )
    guard let concealed = page.originX(ofOffset: content) else {
        Issue.record("nessun segmento per il contenuto a \(content)", sourceLocation: sourceLocation)
        return nil
    }
    page.place(caretAt: content)
    #expect(
        page.isRevealed(paragraph), "il paragrafo non e rivelato con il cursore dentro",
        sourceLocation: sourceLocation
    )
    guard let revealed = page.originX(ofOffset: content) else {
        Issue.record("nessun segmento per il contenuto a \(content) (rivelato)", sourceLocation: sourceLocation)
        return nil
    }
    return Measured(concealed: concealed, revealed: revealed)
}

/// The three widths of G0 item 8: narrow (600), readable (1200), and readable off at 1200.
private struct Width {
    let label: String
    let width: CGFloat
    let readable: Bool
}

private let widths = [
    Width(label: "600 pt, larghezza leggibile", width: 600, readable: true),
    Width(label: "1200 pt, larghezza leggibile", width: 1200, readable: true),
    Width(label: "1200 pt, senza larghezza leggibile", width: 1200, readable: false)
]

// MARK: - The body column (§D1)

@MainActor
@Suite struct GutterBodyColumn {
    private static let note = "Corpo del testo\n\nfine\n"

    /// At a readable width nothing a person can see moves (§D1's first row): the body's content
    /// `x` is today's `(W - 720) / 2 + 5`. Green on today's tree, and it has to stay so; it is also
    /// the check that `originX(ofOffset:)` measures what it claims to.
    @Test func bodyColumnIsTodaysAtReadableWidth() { // (n2-page R-13)
        let page = Page(Self.note, width: 1200)
        let x = page.originX(ofOffset: 0)
        let expected = (page.viewWidth - 720) / 2 + 5
        #expect(x != nil)
        #expect(abs((x ?? -1) - expected) <= tolerance, "x \(x ?? -1) invece di \(expected)")
    }

    /// Narrow, or with readable width off: the whole column shifts once, by the gutter's net amount,
    /// to `G + 5` (G1, 2026-10-07: accepted as drawn in the mockup).
    @Test func bodyColumnIsTheGutterPlusPaddingWhenNarrow() { // (n2-page R-13)
        for entry in widths where !(entry.width == 1200 && entry.readable) {
            let (label, width, readable) = (entry.label, entry.width, entry.readable)
            let page = Page(Self.note, width: width, readableWidth: readable)
            let x = page.originX(ofOffset: 0)
            #expect(
                abs((x ?? -1) - (gutterWidth + 5)) <= tolerance,
                "\(label): x \(x ?? -1) invece di \(gutterWidth + 5)"
            )
        }
    }

    /// The band between 768 and 816 pt: the readable inset is 24...48, below the gutter, so the
    /// column sits at the gutter (§D1's second row, `53`), not at today's `(W - 720) / 2 + 5`.
    @Test func bodyColumnAtTheBoundaryBandIsTheGutterPlusPadding() { // (n2-page R-13)
        let page = Page(Self.note, width: 800)
        let x = page.originX(ofOffset: 0)
        #expect(abs((x ?? -1) - (gutterWidth + 5)) <= tolerance, "x \(x ?? -1)")
    }

    /// The pass hands the delegate the gutter and the marker face, beside `checkboxFont`
    /// (Task 7's "Tokens and the base style"); the card never pushes either.
    @Test func applyStylingPushesTheGutterAndTheMarkerFaceToTheDelegate() { // (n2-page R-13)
        let page = Page(Self.note, width: 900)
        #expect(page.decorations.gutter == gutterWidth)
        #expect(page.decorations.markerFont == ProseTypography.gutterMarker(.emergency))
    }

    /// Every paragraph the editor styles carries the gutter as its base indents (§D1): body and
    /// heading alike, since a heading's style is composed onto the base.
    @Test func everyStyledParagraphCarriesTheGutterIndents() { // (n2-page R-13)
        let note = "Corpo\n\n## Titolo\n\nancora corpo\n"
        let page = Page(note, width: 900)
        guard let storage = page.textView.textStorage else {
            Issue.record("nessuno storage")
            return
        }
        for needle in ["Corpo", "Titolo", "ancora"] {
            let location = (note as NSString).range(of: needle).location
            let style = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
            #expect(
                style?.firstLineHeadIndent == gutterWidth,
                "\(needle): firstLineHeadIndent \(style?.firstLineHeadIndent ?? -1)"
            )
            #expect(style?.headIndent == gutterWidth, "\(needle): headIndent \(style?.headIndent ?? -1)")
            #expect(style?.tailIndent == -gutterWidth, "\(needle): tailIndent \(style?.tailIndent ?? -1)")
        }
    }

    /// The card has no gutter: its delegate keeps `gutter == 0` and no marker face (§D6). Green
    /// already, on purpose.
    @Test func aCardsDelegateKeepsNoGutter() {
        let view = CardTextView(
            text: .constant("- primo\n"), theme: .emergency, style: CardTextStyle(color: nil, alignment: nil),
            isEditable: true, hidesMarkup: true, revealsInlineSpans: false
        )
        let coordinator = view.makeCoordinator()
        #expect(coordinator.decorations.gutter == 0)
        #expect(coordinator.decorations.markerFont == nil)
    }
}

// MARK: - Lists (§D2, R-13)

@MainActor
@Suite struct GutterListGeometry {
    private struct Case {
        let label: String
        let note: String
        let level: Int
        /// The paragraph under test and the first content character, as offsets in `note`.
        let paragraph: Int
        let content: Int
        let away: Int
    }

    /// `intro`, the item lines (each ending `\n`), then `fine`, where the caret rests when it is
    /// "elsewhere".
    private static func make(
        _ label: String, lines: [String], target: Int, markerLength: Int, indent: Int = 0
    ) -> Case {
        let intro = "Intro\n\n"
        let body = lines.joined()
        let note = intro + body + "\nfine\n"
        let paragraph = (intro as NSString).length + lines.prefix(target).reduce(0) { $0 + ($1 as NSString).length }
        return Case(
            label: label, note: note, level: target + 1,
            paragraph: paragraph, content: paragraph + indent + markerLength,
            away: (note as NSString).range(of: "fine").location
        )
    }

    private static func bullets() -> [Case] {
        var cases: [Case] = []
        for marker in ["-", "*", "+"] {
            for level in 1...3 {
                let lines = (1...level).map { depth in
                    String(repeating: " ", count: 2 * (depth - 1)) + "\(marker) voce\(depth)\n"
                }
                cases.append(make(
                    "\(marker) livello \(level)", lines: lines, target: level - 1,
                    markerLength: 2, indent: 2 * (level - 1)
                ))
            }
        }
        return cases
    }

    private static func ordered() -> [Case] {
        [
            make("1.", lines: ["1. uno\n"], target: 0, markerLength: 3),
            make("10.", lines: ["10. dieci\n"], target: 0, markerLength: 4),
            make("12)", lines: ["12) dodici\n"], target: 0, markerLength: 4)
        ]
    }

    private func check(_ item: Case, width: CGFloat, label: String) {
        let page = Page(item.note, width: width)
        guard let measured = measure(page, paragraph: item.paragraph, content: item.content, awayFrom: item.away)
        else { return }
        #expect(
            abs(measured.concealed - measured.revealed) <= tolerance,
            "\(item.label) a \(label): nascosto \(measured.concealed), rivelato \(measured.revealed)"
        )
        // And both at the column: the view's left edge, the padding, then C(L).
        let column = ListMarkerRendering.contentColumn(
            level: item.level, font: ProseTypography.prose(.emergency), gutter: gutterWidth
        )
        let expected = page.textView.textContainerOrigin.x + page.padding + column
        #expect(
            abs(measured.concealed - expected) <= tolerance,
            "\(item.label) a \(label): nascosto \(measured.concealed) invece di \(expected)"
        )
        #expect(
            abs(measured.revealed - expected) <= tolerance,
            "\(item.label) a \(label): rivelato \(measured.revealed) invece di \(expected)"
        )
    }

    @Test func aBulletsContentDoesNotMoveWhenItsMarkerIsRevealed() { // (n2-page R-13)
        for item in Self.bullets() {
            for entry in widths where entry.readable { check(item, width: entry.width, label: entry.label) }
        }
    }

    @Test func anOrderedItemsContentDoesNotMoveWhenItsMarkerIsRevealed() { // (n2-page R-13)
        for item in Self.ordered() {
            for entry in widths where entry.readable { check(item, width: entry.width, label: entry.label) }
        }
    }

    /// A wrapped item: the second line sits at the first line's content, in both states.
    @Test func aWrappedItemsSecondLineSitsAtTheFirstLinesContent() { // (n2-page R-13)
        let item = Self.make(
            "voce lunga", lines: ["- " + String(repeating: "parola ", count: 60) + "\n"],
            target: 0, markerLength: 2
        )
        for entry in widths where entry.readable {
            let (label, width) = (entry.label, entry.width)
            let page = Page(item.note, width: width)
            var firstLines: [CGFloat] = []
            var secondLines: [CGFloat] = []
            for caret in [item.away, item.content] {
                page.place(caretAt: caret)
                guard let first = page.originX(ofOffset: item.content),
                      let second = page.secondLineStart(ofParagraphAt: item.paragraph),
                      let secondX = page.originX(ofOffset: second)
                else {
                    Issue.record("\(label): la voce non va a capo o non e misurabile")
                    return
                }
                firstLines.append(first)
                secondLines.append(secondX)
            }
            #expect(
                abs(firstLines[0] - secondLines[0]) <= tolerance,
                "\(label), nascosto: prima riga \(firstLines[0]), seconda \(secondLines[0])"
            )
            #expect(
                abs(firstLines[1] - secondLines[1]) <= tolerance,
                "\(label), rivelato: prima riga \(firstLines[1]), seconda \(secondLines[1])"
            )
            #expect(abs(firstLines[0] - firstLines[1]) <= tolerance, "\(label): la prima riga si muove")
            #expect(abs(secondLines[0] - secondLines[1]) <= tolerance, "\(label): la seconda riga si muove")
        }
    }

    /// A task line is not a list line and its checkbox is never revealed: its content does not
    /// move, and it is shifted by the gutter like every paragraph (§D2, last paragraph).
    @Test func aTaskLineDoesNotMoveAndIsShiftedByTheGutter() { // (n2-page R-13)
        let note = "Intro\n\n- [ ] fai\n\nfine\n"
        let paragraph = (note as NSString).range(of: "- [ ]").location
        let content = paragraph + 6
        let away = (note as NSString).range(of: "fine").location

        let page = Page(note, width: 600)
        guard let measured = measure(page, paragraph: paragraph, content: content, awayFrom: away) else { return }
        #expect(abs(measured.concealed - measured.revealed) <= tolerance)

        page.place(caretAt: away)
        let first = page.originX(ofOffset: paragraph)
        #expect(
            abs((first ?? -1) - (gutterWidth + page.padding)) <= tolerance,
            "la riga attivita parte a \(first ?? -1) invece che a \(gutterWidth + page.padding)"
        )
    }
}

// MARK: - Headings and quotes (§D3, §D4, R-14)

@MainActor
@Suite struct GutterHeadingAndQuoteGeometry {
    private static func note(_ block: String) -> String { "Intro\n\n\(block)\n\nfine\n" }

    private func check(
        block: String, title: String, label: String, expectedColumn: (Page) -> CGFloat
    ) {
        let note = Self.note(block)
        for entry in widths {
            let (widthLabel, width, readable) = (entry.label, entry.width, entry.readable)
            let page = Page(note, width: width, readableWidth: readable)
            let paragraph = page.offset(of: block)
            let content = paragraph + (block as NSString).range(of: title).location
            let away = page.offset(of: "fine")
            guard let measured = measure(page, paragraph: paragraph, content: content, awayFrom: away) else { continue }
            #expect(
                abs(measured.concealed - measured.revealed) <= tolerance,
                "\(label) a \(widthLabel): nascosto \(measured.concealed), rivelato \(measured.revealed)"
            )
            let expected = page.textView.textContainerOrigin.x + page.padding + expectedColumn(page)
            #expect(
                abs(measured.concealed - expected) <= tolerance,
                "\(label) a \(widthLabel): nascosto \(measured.concealed) invece di \(expected)"
            )
            #expect(
                abs(measured.revealed - expected) <= tolerance,
                "\(label) a \(widthLabel): rivelato \(measured.revealed) invece di \(expected)"
            )
        }
    }

    @Test func aHeadingsTitleDoesNotMoveWhenItsMarkerIsRevealed() { // (n2-page R-14)
        for level in 1...6 {
            let block = String(repeating: "#", count: level) + " Titolo"
            check(block: block, title: "Titolo", label: "H\(level)") { _ in gutterWidth }
        }
    }

    @Test func aQuotesContentDoesNotMoveWhenItsMarkerIsRevealed() { // (n2-page R-14)
        for level in 1...2 {
            let block = String(repeating: ">", count: level) + " citazione"
            check(block: block, title: "citazione", label: "citazione livello \(level)") { page in
                EditorGutter.quoteColumn(
                    level: level, font: page.decorations.proseFont, gutter: gutterWidth
                )
            }
        }
    }

    /// G0 item 10: a heading with no title (`#`, `######`) must not trap when the caret reaches it at
    /// a gutter, and the file's text and the stored length are untouched. This is all that is pinned.
    /// The plan's other half, "hangs its run when revealed and draws nothing when concealed", cannot
    /// be asserted as written: `MarkdownStyler` records no heading marker for a heading with no title
    /// (`MarkdownStyler.swift:266-271`), so the delegate has no `.heading` entry to conceal or hang,
    /// and the hook answers `nil` in both states. That is reported as a gap, not pinned here.
    @Test func aHeadingWithNoTitleDoesNotTrapWhenRevealedAtAGutter() { // (n2-page R-14)
        for block in ["#", "######"] {
            let note = Self.note(block)
            let page = Page(note, width: 600)
            let paragraph = page.offset(of: block)
            let range = (note as NSString).paragraphRange(for: NSRange(location: paragraph, length: 0))

            for caret in [page.offset(of: "fine"), paragraph] {
                page.place(caretAt: caret)
                let displayed = page.decorations.textContentStorage(page.content, textParagraphWith: range)
                if let displayed {
                    #expect(displayed.attributedString.length == range.length, "«\(block)»: la lunghezza cambia")
                }
                _ = page.originX(ofOffset: paragraph)
            }
            #expect(page.isRevealed(paragraph), "«\(block)»")
            #expect(page.textView.string == note, "«\(block)»: il testo del file cambia")
        }
    }
}

// MARK: - Decorations (§D7)

@MainActor
@Suite struct GutterDecorationGeometry {
    /// The widest inked row of the hosted text view as it is really drawn: how many points it inked,
    /// and where it starts and ends, in the text view's coordinates. The view is rendered whole
    /// (`cacheDisplay`), so `draw(at:in:)` is called by TextKit with the `point` the app gives it, and
    /// nothing here chooses that point. The rule is black and everything else on the page is a theme
    /// colour that is not, so on a page whose only black ink is the rule the widest black row is it.
    private static func inkSpan(of textView: NSTextView) -> (count: CGFloat, minX: CGFloat, maxX: CGFloat)? {
        textView.layoutSubtreeIfNeeded()
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        textView.displayIfNeeded()
        guard let bitmap = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else { return nil }
        textView.cacheDisplay(in: textView.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / textView.bounds.width

        var widest = (count: 0, minX: 0, maxX: 0)
        for y in 0..<bitmap.pixelsHigh {
            var inkedX: [Int] = []
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.25, color.redComponent < 0.15, color.greenComponent < 0.15,
                   color.blueComponent < 0.15 { inkedX.append(x) }
            }
            if inkedX.count > widest.count, let first = inkedX.first, let last = inkedX.last {
                widest = (inkedX.count, first, last + 1)
            }
        }
        return (CGFloat(widest.count) / scale, CGFloat(widest.minX) / scale, CGFloat(widest.maxX) / scale)
    }

    private static func ruleFragment(in page: Page) -> HorizontalRuleFragment? {
        var rule: HorizontalRuleFragment?
        page.layout.enumerateTextLayoutFragments(
            from: page.layout.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            if let found = fragment as? HorizontalRuleFragment { rule = found }
            return true
        }
        return rule
    }

    /// The convention every full-width decoration draws by (§D7), measured rather than assumed: a
    /// paragraph's layout fragment starts at `lineFragmentPadding + headIndent` from the container's
    /// edge, so the `point` it is drawn at already is the column's start. A decoration that adds the
    /// column's leading offset to it counts the padding and the indent twice (the rule and the
    /// transcluded picture did, and ran out over the right margin). `MessageAnchorFragment` draws at
    /// `point.x` on this convention.
    @Test func aFragmentStartsAtTheColumnNotAtTheContainersEdge() { // (n2-page R-14)
        let note = "Intro\n\n---\n\nfine\n"
        let page = Page(note, width: 600)
        page.place(caretAt: page.offset(of: "fine"))
        page.layout.ensureLayout(for: page.layout.documentRange)
        let style = page.textView.textStorage?
            .attribute(.paragraphStyle, at: page.offset(of: "fine"), effectiveRange: nil) as? NSParagraphStyle
        let head = style?.headIndent ?? 0
        #expect(head >= gutterWidth - tolerance, "il paragrafo non ha la grondaia nell'indentazione: \(head)")

        var seen = 0
        page.layout.enumerateTextLayoutFragments(
            from: page.layout.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            seen += 1
            #expect(
                abs(fragment.layoutFragmentFrame.minX - (page.padding + head)) <= tolerance,
                "\(type(of: fragment)): origine \(fragment.layoutFragmentFrame.minX) invece di \(page.padding + head)"
            )
            return true
        }
        #expect(seen > 0)
    }

    /// A rule is drawn across the column between the indents, not across the container (§D7):
    /// rendered by the hosted view, its widest row is `columnSpan`'s width, starts at the column and
    /// stays out of the two gutter bands.
    @Test func aRuleIsDrawnAcrossTheColumnAndNotTheContainer() { // (n2-page R-14)
        let note = "Intro\n\n---\n\nfine\n"
        let page = Page(note, width: 600)
        page.place(caretAt: page.offset(of: "fine"))
        page.layout.ensureLayout(for: page.layout.documentRange)

        guard let container = page.textView.textContainer else { return }
        guard let rule = Self.ruleFragment(in: page) else {
            Issue.record("nessun HorizontalRuleFragment per la riga ---")
            return
        }
        rule.ruleColor = .black

        guard let widest = Self.inkSpan(of: page.textView) else {
            Issue.record("nessuna bitmap")
            return
        }

        let style = page.textView.textStorage?
            .attribute(.paragraphStyle, at: page.offset(of: "---"), effectiveRange: nil) as? NSParagraphStyle
        let span = EditorGutter.columnSpan(
            containerWidth: container.size.width, padding: container.lineFragmentPadding, style: style
        )
        let origin = page.textView.textContainerOrigin.x
        let expectedWidth = container.size.width - 2 * container.lineFragmentPadding - 2 * gutterWidth
        #expect(widest.count > 0, "la riga non ha disegnato nulla")
        #expect(
            abs(widest.maxX - widest.minX - expectedWidth) <= 1,
            "la riga e larga \(widest.maxX - widest.minX) pt invece di \(expectedWidth)"
        )
        #expect(
            abs(widest.maxX - widest.minX - span.width) <= 1,
            "la riga e larga \(widest.maxX - widest.minX) pt, columnSpan dice \(span.width)"
        )
        #expect(
            abs(widest.minX - (origin + span.leading)) <= 1,
            "la riga comincia a \(widest.minX) invece che alla colonna, \(origin + span.leading)"
        )
        #expect(
            widest.minX >= origin + container.lineFragmentPadding + gutterWidth - 1,
            "la riga entra nella grondaia di sinistra: \(widest.minX)"
        )
        #expect(
            widest.maxX <= origin + container.size.width - container.lineFragmentPadding - gutterWidth + 1,
            "la riga entra nella grondaia di destra: \(widest.maxX)"
        )
    }

    /// A table attachment narrower than the column draws inside it (§D7: whether the proposed line
    /// fragment already excludes the indents is not known from the headers, so this measures it).
    /// Only a narrow grid: `TableGridView` is content-sized, so a grid wider than the column is
    /// out of §D7's reach (ADR-0081 Implementation notes) and the next test pins where it starts.
    @Test func aTableNarrowerThanTheColumnStaysInsideIt() { // (n2-page R-14)
        let note = "prima\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\ndopo\n"
        guard case let (page, grid)? = Self.hostedTable(note) else { return }
        expectInsideTheColumn(grid, in: page, what: "la tabella")
    }

    /// A grid wider than the column still starts at the column, not at the container's edge or in
    /// the gutter: where it starts is what the gutter decides; its width is the table's own.
    @Test func aTableWiderThanTheColumnStillStartsAtTheColumn() { // (n2-page R-14)
        let cell = "una cella con parecchio testo dentro"
        let row = "| " + Array(repeating: cell, count: 4).joined(separator: " | ") + " |"
        let note = "prima\n\(row)\n|---|---|---|---|\n\(row)\ndopo\n"
        guard case let (page, grid)? = Self.hostedTable(note),
              let container = page.textView.textContainer
        else { return }
        let frame = grid.convert(grid.bounds, to: page.textView)
        let column = container.size.width - 2 * container.lineFragmentPadding - 2 * gutterWidth
        let left = page.textView.textContainerOrigin.x + container.lineFragmentPadding + gutterWidth
        #expect(frame.width > column, "la tabella non e piu larga della colonna: \(frame.width) <= \(column)")
        #expect(abs(frame.minX - left) <= tolerance, "la tabella comincia a \(frame.minX) invece di \(left)")
    }

    /// A 600 pt page with `note`, the caret on `dopo`, laid out, and the grid of its table at offset 6.
    private static func hostedTable(_ note: String) -> (Page, NSView)? {
        let page = Page(note, width: 600)
        page.place(caretAt: page.offset(of: "dopo"))
        page.textView.layoutSubtreeIfNeeded()
        page.layout.ensureLayout(for: page.layout.documentRange)
        page.layout.textViewportLayoutController.layoutViewport()

        guard let grid = page.decorations.tableViews[6] else {
            Issue.record("la griglia della tabella non e stata costruita")
            return nil
        }
        return (page, grid)
    }

    /// The same for a view block's host (`render: table` needs no query source to be hosted).
    @Test func aViewBlocksHostStaysInsideTheColumn() { // (n2-page R-14)
        let note = "prima\n```pergamenum-view\nrender: table\n```\ndopo\n"
        let page = Page(note, width: 600)
        page.place(caretAt: page.offset(of: "dopo"))
        page.textView.layoutSubtreeIfNeeded()
        page.layout.ensureLayout(for: page.layout.documentRange)
        page.layout.textViewportLayoutController.layoutViewport()

        guard let host = page.decorations.viewBlockHosts[6] else {
            Issue.record("il blocco vista non ha un host")
            return
        }
        expectInsideTheColumn(host, in: page, what: "il blocco vista")
    }

    private func expectInsideTheColumn(_ view: NSView, in page: Page, what: String) {
        guard let container = page.textView.textContainer else { return }
        let frame = view.convert(view.bounds, to: page.textView)
        let origin = page.textView.textContainerOrigin.x
        let left = origin + container.lineFragmentPadding + gutterWidth
        let right = origin + container.size.width - container.lineFragmentPadding - gutterWidth
        #expect(frame.width > 0, "\(what): cornice vuota")
        #expect(frame.minX >= left - tolerance, "\(what) esce a sinistra: \(frame.minX) < \(left)")
        #expect(frame.maxX <= right + tolerance, "\(what) esce a destra: \(frame.maxX) > \(right)")
    }
}
