import AppKit
import UniformTypeIdentifiers

/// One embed's resolved picture, or the fact that it could not be drawn (ADR-0018 slice
/// 3, Step 2).
///
/// No `.pending` case, on purpose: `EmbedTable.renditions` simply carries no entry yet
/// for an embed whose render has not landed - the same "absence is the third state"
/// `EmbeddedFileView` reads through `hasLooked`, a `@State` flip there and a missing
/// dictionary key here.
enum EmbedRendition: Equatable {
    case drawn(NSImage)
    case missing(name: String)

    static func == (lhs: EmbedRendition, rhs: EmbedRendition) -> Bool {
        switch (lhs, rhs) {
        case let (.drawn(left), .drawn(right)): left === right
        case let (.missing(left), .missing(right)): left == right
        default: false
        }
    }
}

/// Resolves the editor's `![[file.est]]`/`![alt](file.est)` lines to a picture, and keeps
/// the table `EditorDecorationDelegate` will read once it grows to draw one (Step 3).
///
/// A small object of its own rather than more stored properties directly on the
/// Coordinator, matching the shape `decorations` already has: `NoteTextView.Coordinator`
/// owns one, `applyEmbeds` below is the only thing that calls into it, and nothing about
/// resolving a file needs the rest of the Coordinator's state.
///
/// `@MainActor`, unlike `EditorDecorationDelegate`: nothing here conforms to the
/// `NSTextContentStorageDelegate`/`NSTextLayoutManagerDelegate` protocols Swift 6 refuses
/// on the main actor, so there is no reason to give up the isolation the rest of the
/// Coordinator already has. `ThumbnailStore` is the actor this table calls, always with
/// `await` from here and never from the delegate - Step 3's delegate only ever reads a
/// finished `EmbedRendition`, the same shape `renditions`/`apply(renditions:)` already
/// give it for transclusions.
@MainActor
final class EmbedTable {
    /// One embed's rendition, by the paragraph-start offset of the line that names it -
    /// the same key space `EditorDecorationDelegate`'s own tables use.
    private(set) var renditions: [Int: EmbedRendition] = [:]
    /// Renditions by resolved vault-relative path and width bucket, so a picture embedded
    /// on several lines - or restyled on the next keystroke - renders once. Not keyed by
    /// paragraph offset: an edit above an embed moves every offset below it, and a cache
    /// keyed that way would miss on every keystroke that touches an earlier line.
    private var renderCache: [String: EmbedRendition] = [:]
    /// A target's resolved vault-relative path, or nil when it could not be found - by
    /// note path and the written target together, since the same file name resolves
    /// differently beside a different note. Without this, an embed that does not resolve
    /// directly falls through `Attachment.resolve`'s vault-wide search on every keystroke
    /// anywhere in the note, not only on the line naming it: `applyStyling` restyles the
    /// whole note each time. The trade-off is explicit: a file created after a failed
    /// lookup resolves again only once the note is reopened, which is what would rebuild
    /// this table from empty. Wiring a scan generation the way `TransclusionSource`
    /// already has one is the fix, if this ever bites - out of scope for Step 2, which
    /// adds no such input to `NoteTextView`.
    private var resolutionCache: [String: String?] = [:]
    /// Paragraph offsets waiting on a still-pending render, by the same key
    /// `renderCache` uses - what a render's completion updates, all at once, when it
    /// lands.
    private var pending: [String: Set<Int>] = [:]
    /// The text view a pending render invalidates when it lands. Weak: this table
    /// outlives no `NSTextView` on purpose, the same as `Coordinator.textView`.
    private weak var textView: NSTextView?

    /// The width every embed renders at, matching `EmbeddedFileView.renderWidth` bit for
    /// bit. `ThumbnailStore` quantises internally, so requesting the same value here is
    /// what makes one file cost one render shared between the editor and reading mode,
    /// rather than a second cache entry for the same picture.
    private static let renderWidth: CGFloat = 720

    /// Resolves every embed line `applyStyling` just found, from the cache when it is
    /// already there and by starting a render when it is not.
    ///
    /// Never blocks: a cache miss leaves that offset out of the table for this pass -
    /// the "pending" state `EmbedRendition` has no case for - and the table updates
    /// itself later, from `requestRender`'s own completion, once the render lands.
    func apply(
        runs: [NSRange],
        notePath: String,
        root: URL?,
        thumbnails: ThumbnailStore?,
        in textView: NSTextView
    ) {
        self.textView = textView
        let text = textView.string as NSString
        guard let root, let thumbnails else {
            setRenditions([:], text: text)
            return
        }

        var next: [Int: EmbedRendition] = [:]
        for range in runs where NSMaxRange(range) <= text.length {
            let offset = text.paragraphRange(for: NSRange(location: range.location, length: 0)).location
            guard let rendition = rendition(
                forSyntax: text.substring(with: range),
                notePath: notePath, root: root, thumbnails: thumbnails, offset: offset
            ) else { continue }
            next[offset] = rendition
        }
        setRenditions(next, text: text)
    }

    /// One embed's rendition, synchronously from the cache, or nil while a render is
    /// still in flight - never nil for a reason `EditorDecorationDelegate` would need to
    /// draw differently, since a missing file is `.missing`, not an absent entry.
    private func rendition(
        forSyntax syntax: String,
        notePath: String,
        root: URL,
        thumbnails: ThumbnailStore,
        offset: Int
    ) -> EmbedRendition? {
        guard let embed = Attachment.embed(inLine: syntax) else { return nil }
        guard let relativePath = resolvedPath(for: embed.target, notePath: notePath, root: root) else {
            return .missing(name: embed.target)
        }
        // Only a picture or a PDF is drawable here (D3). Anything else is not entered as
        // `.missing` either - it stays plain, unresolved text once Step 3 exists, the
        // same as a line still waiting on its first render.
        guard Self.isRenderableType(of: relativePath) else { return nil }

        let key = "\(relativePath)@\(Int(Self.renderWidth))"
        if let cached = renderCache[key] { return cached }
        requestRender(
            relativePath: relativePath, key: key, thumbnails: thumbnails,
            fallbackName: embed.target, offset: offset
        )
        return nil
    }

    /// `Attachment.resolve`, cached by note path and target - see `resolutionCache`'s own
    /// comment for why.
    private func resolvedPath(for target: String, notePath: String, root: URL) -> String? {
        let key = "\(notePath)|\(target)"
        if let cached = resolutionCache[key] { return cached }
        let resolved = Attachment.resolve(target, nearNoteAt: notePath, inVaultAt: root)
        resolutionCache[key] = resolved
        return resolved
    }

    /// Starts a render, unless one for the same file at the same width is already on its
    /// way - `pending[key]` gaining its first waiter is what tells the two apart, so two
    /// embeds of the same picture start one render between them.
    private func requestRender(
        relativePath: String,
        key: String,
        thumbnails: ThumbnailStore,
        fallbackName: String,
        offset: Int
    ) {
        let isFirstWaiter = pending[key, default: []].isEmpty
        pending[key, default: []].insert(offset)
        guard isFirstWaiter else { return }

        // Starts on the main actor, this table's own isolation, and returns to it after
        // `await`ing the actor hop into `ThumbnailStore` - never the reverse, and never a
        // reference to the actor handed anywhere else (ADR-0018 slice 3, Step 2).
        Task { @MainActor [weak self] in
            let render = await thumbnails.thumbnail(for: relativePath, width: Self.renderWidth)
            let image = await render.value
            guard let self else { return }
            let rendition: EmbedRendition = image.map(EmbedRendition.drawn) ?? .missing(name: fallbackName)
            self.renderCache[key] = rendition
            let waiters = self.pending.removeValue(forKey: key) ?? []
            guard let textView = self.textView, !waiters.isEmpty else { return }
            var updated = self.renditions
            for waitingOffset in waiters { updated[waitingOffset] = rendition }
            self.setRenditions(updated, text: textView.string as NSString)
        }
    }

    /// Replaces the table and invalidates only the paragraphs whose rendition actually
    /// changed - never the whole document, the same restraint `NoteTextView+Reveal.swift`
    /// takes for the same reason: a note can embed more than one file, and this runs on
    /// every keystroke as well as every render's completion.
    ///
    /// Nothing reads `renditions` yet - `EditorDecorationDelegate` grows to draw from it
    /// in Step 3 - so today this asks the layout to re-run its enumeration over
    /// paragraphs whose attributes have not visibly changed. Wired in now rather than
    /// left for Step 3 to add, the same way `applyStyling` already calls
    /// `decorations.apply(hiddenMarkers:...)` before anything drew from it.
    private func setRenditions(_ next: [Int: EmbedRendition], text: NSString) {
        let changed = Set(next.keys).union(renditions.keys).filter { next[$0] != renditions[$0] }
        renditions = next
        guard !changed.isEmpty, let textView, let storage = textView.textStorage else { return }
        storage.beginEditing()
        for offset in changed where offset < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: offset, length: 0))
            storage.edited(.editedAttributes, range: paragraph, changeInLength: 0)
        }
        storage.endEditing()
    }

    /// Whether `relativePath`'s extension names a picture or a PDF (D3) - decided from
    /// the name alone, never by opening the file: this is a question about what the
    /// editor layer draws, not one `Attachment` (Core) needs an opinion on.
    private static func isRenderableType(of relativePath: String) -> Bool {
        guard let type = UTType(filenameExtension: (relativePath as NSString).pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .pdf)
    }
}

extension NoteTextView.Coordinator {
    /// Resolves every embed `applyStyling` just found to a picture (ADR-0018 slice 3,
    /// Step 2). Never a second parse of the note: `embedRuns` is exactly what the same
    /// `MarkdownStyler.spans(in:)` walk `applyStyling` already made found, and this only
    /// walks it.
    func applyEmbeds(to textView: NSTextView) {
        embeds.apply(
            runs: embedRuns,
            notePath: parent.notePath,
            root: parent.vaultRoot,
            thumbnails: parent.thumbnails,
            in: textView
        )
    }
}
