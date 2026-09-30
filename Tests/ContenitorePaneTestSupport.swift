import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder), plan
// docs/plans/contenitore.md, Tasks 6 and 7: what the controller, route, list, inspector, command
// and hosted-view suites share. The suites of Tasks 2-5 keep their own private helpers.

/// The first bytes of a PDF: enough for a companion file that exists.
let contenitorePDFBytes = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A, 0xFF, 0x00, 0xE2])

enum ContenitoreFixture {
    static let hash = String(repeating: "cd", count: 32)
    static let inbox = Tag(namespace: .status, value: "inbox")
    static let typeNote = Tag(namespace: .type, value: "note")

    /// A scheda's text for `fileName`, with its tags replaced and its colour set when given.
    static func schedaText(
        fileName: String, date: String = "2026-03-14", tags: [Pergamenum.Tag]? = nil,
        colour: ContenitoreColour? = nil, sha256: String = hash
    ) throws -> String {
        let day = try #require(CalendarDate(iso: date))
        var text = ContenitoreScheda.render(date: day, fileName: fileName, originalName: "Scansione.pdf", sha256: sha256)
        if let tags {
            var document = NoteDocument.parse(text)
            document.frontmatter.tags = tags
            text = document.serialized()
        }
        if let colour { text = ContenitoreScheda.settingColour(colour, in: text) }
        return text
    }

    /// A scheda at `folder/stem.md` and, unless `withFile` is false, its PDF beside it. Returns
    /// the scheda's vault-relative path.
    @discardableResult
    static func seed(
        stem: String, in folder: String, date: String = "2026-03-14", tags: [Pergamenum.Tag]? = nil,
        colour: ContenitoreColour? = nil, sha256: String = hash, withFile: Bool = true,
        vault: borrowing TemporaryVault
    ) throws -> String {
        let text = try schedaText(fileName: "\(stem).pdf", date: date, tags: tags, colour: colour, sha256: sha256)
        try vault.write(text, to: "\(folder)/\(stem).md")
        if withFile {
            let url = vault.root.appending(path: "\(folder)/\(stem).pdf", directoryHint: .notDirectory)
            try contenitorePDFBytes.write(to: url)
        }
        return "\(folder)/\(stem).md"
    }

    /// A classified scheda's tags: `type-note` and one topic.
    static let classified: [Pergamenum.Tag] = [typeNote, Tag(namespace: .topic, value: "fatture")]

    static func text(_ relativePath: String, in root: URL) throws -> String {
        try String(contentsOf: root.appending(path: relativePath, directoryHint: .notDirectory), encoding: .utf8)
    }

    /// Takes what a test sent to the Finder Trash back out of it.
    static func removeFromTrash(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }
}

/// An extractor that finds no text, at once: the queue runs, nothing is recognised.
struct ContenitoreNoTextExtractor: TextExtracting {
    func extract(_ url: URL, progress: @Sendable (Int, Int) -> Void) async throws -> ExtractedText {
        progress(1, 1)
        return ExtractedText(method: .none, status: .done, text: "", pagesDone: 1, pageCount: 1)
    }
}

/// What the controller's Finder seam was handed.
@MainActor
final class ContenitoreRevealRecorder {
    var revealed: [[URL]] = []
    var opened: [URL] = []
}

/// A vault opened by a `VaultController`, a `ContenitoreController` on it that is not isolated,
/// watches nothing and schedules nothing, and the pane's command runner.
@MainActor
struct ContenitoreHarness {
    let vault: VaultController
    let contenitore: ContenitoreController
    let navigation: Navigation
    let recorder: ContenitoreRevealRecorder

    var actions: ContenitoreCommandActions {
        ContenitoreCommandActions(vault: vault, navigation: navigation, contenitore: contenitore)
    }

    /// `home` stands in for the home folder, so the default drop folder `~/Pergamenum Drop`
    /// resolves inside the test's own state base, never in the person's home.
    static func make(root: URL, home: URL) async throws -> ContenitoreHarness {
        let vault = VaultController(recents: .volatile(), openTabs: .volatile())
        await vault.open(root)
        let defaults = try #require(UserDefaults(suiteName: "pergamenum-contenitore-tests-\(UUID().uuidString)"))
        let day = try #require(CalendarDate(year: 2026, month: 9, day: 29))
        let contenitore = ContenitoreController(
            vault: vault, home: home, today: { day }, extractor: ContenitoreNoTextExtractor(),
            pasteboard: .volatile(), defaults: defaults, isTestHost: false,
            followUpDelay: nil, watchesDropFolder: false
        )
        let recorder = ContenitoreRevealRecorder()
        contenitore.revealFiles = { recorder.revealed.append($0) }
        contenitore.openFile = { recorder.opened.append($0) }
        return ContenitoreHarness(vault: vault, contenitore: contenitore, navigation: Navigation(), recorder: recorder)
    }

    /// The app's `CommandActions`, wired to this controller, as the menu bar holds it.
    func commandActions() -> CommandActions {
        let calendarStore = EventKitStore()
        let capture = CaptureController()
        let vault = self.vault
        return CommandActions(
            navigation: navigation,
            vault: vault,
            day: DayController(store: calendarStore, vault: vault),
            calendar: calendarStore,
            capturePanel: CapturePanel(
                controller: capture,
                session: { vault.session },
                theme: { ThemeEngine().current },
                shortcutCaption: { nil }
            ),
            history: NavigationHistory(),
            pasteboard: .volatile(),
            contenitore: contenitore
        )
    }
}
