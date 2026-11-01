import AppKit
import Foundation
import Testing
@testable import Pergamenum

// PG-391, the code half of PG-384 R-22's light-theme hand check. n1-seams R-14 (`spacing.paragraph`
// after every prose and heading line, in the note editor only) and R-15 (H6 in the regular prose
// face, in `textSecondary`; H5 keeps the bold title face, in `textPrimary`) are pinned elsewhere
// against `Theme.emergency` (`ProseParagraphSpacingTests`, `ProseTypographyTests`). This suite runs
// the same two styling paths, the editor's storage and the Workspace card's styled text, through
// each bundled theme as `ThemeEngine` loads it, light as well as dark. It proves what the attributes
// say; how the page looks in either theme is still a hand check on a Debug build.

private let pageTypographyBundledIDs = ["pergamenum-light", "pergamenum-dark"]

@MainActor
@Suite struct BundledThemePageTypographyTests {
    private static let text = "# Titolo\n\nUna riga di prosa.\n\n##### Sezione\n\n###### Nota\n\n- voce di elenco\n"

    private func bundled(_ id: String) throws -> Theme {
        let defaults = ScratchDefaults.make()
        let engine = ThemeEngine(defaults: defaults)
        #expect(engine.problems.isEmpty, "\(engine.problems)")
        return try #require(engine.themes.first { $0.id == id }, "\(id) is not loaded")
    }

    /// The editor's text view styled by the coordinator's own pass with `theme`, as the app styles it.
    private func styledEditor(_ theme: Theme) -> EmbedEditorFixtures.Fixture {
        let fixture = EmbedEditorFixtures.editor(text: Self.text, hidesMarkup: false, root: nil, thumbnails: nil)
        fixture.coordinator.applyStyling(to: fixture.textView, theme: theme)
        return fixture
    }

    private static func attribute<Value>(
        _ key: NSAttributedString.Key, in string: NSAttributedString?, atLineContaining needle: String
    ) -> Value? {
        let location = (Self.text as NSString).range(of: needle).location
        guard let string, location != NSNotFound else { return nil }
        return string.attribute(key, at: location, effectiveRange: nil) as? Value
    }

    private static func isBold(_ font: NSFont?) -> Bool? {
        font.map { $0.fontDescriptor.symbolicTraits.contains(.bold) }
    }

    // MARK: - spacing.paragraph (n1-seams R-14)

    @Test(arguments: pageTypographyBundledIDs)
    func theEditorSpacesProseAndHeadingLinesByTheThemesParagraphToken(id: String) throws {
        let theme = try bundled(id)
        #expect(theme.spacing(.paragraph) == 8, "\(id): spacing.paragraph")
        let fixture = styledEditor(theme)
        let storage = fixture.textView.textStorage
        for needle in ["Una riga di prosa.", "Titolo", "Sezione", "Nota"] {
            let style: NSParagraphStyle? = Self.attribute(.paragraphStyle, in: storage, atLineContaining: needle)
            #expect(style?.paragraphSpacing == 8, "\(id): «\(needle)»")
        }
        let list: NSParagraphStyle? = Self.attribute(.paragraphStyle, in: storage, atLineContaining: "voce di elenco")
        #expect(list?.paragraphSpacing == 0, "\(id): a list line keeps its own spacing")
    }

    @Test(arguments: pageTypographyBundledIDs)
    func theCardAddsNoParagraphSpacing(id: String) throws {
        // R-14 is the note editor only: the card's styled text keeps today's paragraphs in both themes.
        let theme = try bundled(id)
        let styled = CardTextAttributes.attributed(Self.text, theme: theme)
        let style: NSParagraphStyle? = Self.attribute(
            .paragraphStyle, in: styled, atLineContaining: "Una riga di prosa."
        )
        #expect((style?.paragraphSpacing ?? 0) == 0, "\(id)")
    }

    // MARK: - H5 and H6 (n1-seams R-15)

    @Test(arguments: pageTypographyBundledIDs)
    func theEditorDrawsHeadingSixRegularInSecondaryAndHeadingFiveBoldInPrimary(id: String) throws {
        let theme = try bundled(id)
        let fixture = styledEditor(theme)
        Self.expectHeadingFiveAndSix(in: fixture.textView.textStorage, theme: theme, id: id)
    }

    @Test(arguments: pageTypographyBundledIDs)
    func theCardDrawsHeadingSixRegularInSecondaryAndHeadingFiveBoldInPrimary(id: String) throws {
        let theme = try bundled(id)
        Self.expectHeadingFiveAndSix(
            in: CardTextAttributes.attributed(Self.text, theme: theme), theme: theme, id: id
        )
    }

    private static func expectHeadingFiveAndSix(in string: NSAttributedString?, theme: Theme, id: String) {
        let primary = theme.rawColor(.textPrimary)
        let secondary = theme.rawColor(.textSecondary)
        #expect(primary != secondary, "\(id): textSecondary must be a colour of its own")

        let h6Font: NSFont? = attribute(.font, in: string, atLineContaining: "Nota")
        let h5Font: NSFont? = attribute(.font, in: string, atLineContaining: "Sezione")
        #expect(isBold(h6Font) == false, "\(id): H6 is the regular prose face")
        #expect(isBold(h5Font) == true, "\(id): H5 keeps the bold title face")
        #expect(h6Font?.pointSize == ProseTypography.heading(level: 6, theme).pointSize, "\(id): H6 size")

        let h6Colour: NSColor? = attribute(.foregroundColor, in: string, atLineContaining: "Nota")
        let h5Colour: NSColor? = attribute(.foregroundColor, in: string, atLineContaining: "Sezione")
        #expect(h6Colour == NSColor(theme.color(.textSecondary)), "\(id): H6 colour")
        #expect(h5Colour == NSColor(theme.color(.textPrimary)), "\(id): H5 colour")
    }
}
