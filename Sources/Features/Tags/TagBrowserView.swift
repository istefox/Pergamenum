import SwiftUI

/// The tag browser (ADR-0012, slice 3; mockup approved on 2026-08-19).
///
/// The tags on the left, grouped by the namespaces SPEC §4.4 closes the grammar to, each with
/// the number of notes carrying it; the notes that survive the choice on the right. Choosing a
/// second tag **narrows**: what is left carries all of them, because a tag added that took
/// nothing away would not be narrowing anything.
///
/// Everything here is read off `IndexSnapshot.tagUsage()` and `allNotes`, computed per draw.
/// No new structure in the index and no new column in the cache: `IndexCache`'s schema version
/// is spent by M11 (ADR-0009 §D2) and this milestone must not touch it. A vault of a few
/// thousand notes counts its tags in a dictionary pass, which is cheaper than the scan that
/// produced the snapshot in the first place.
struct TagBrowserView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    @Environment(ThemeEngine.self) private var themeEngine

    /// The chosen tags. View state: a filter being held is a fact about looking, not about the
    /// vault, and it does not deserve to outlive the window.
    @State private var chosen: Set<Tag> = []
    /// Which namespaces are open. All of them at first: a browser that opens closed asks for a
    /// click before it says anything.
    @State private var openNamespaces: Set<TagNamespace> = Set(TagNamespace.allCases)
    /// The tag the rename sheet is about (ADR-0012 D7). Wrapped, because `sheet(item:)` wants
    /// an `Identifiable` and `Tag` is a schema type from `Sources/Core` - a view's need for an
    /// id is not a reason to widen it.
    /// What the last rename did, kept only so it can be put back. Cleared by the undo, by the
    /// next rename, and by nothing else: an offer to undo that outlives the intention behind it
    /// is a button waiting to surprise somebody.
    @State private var lastRename: FinishedRename?

    @State private var renaming: RenamingTag?

    private struct RenamingTag: Identifiable {
        let id = UUID()
        let tag: Tag
    }

    private struct FinishedRename: Equatable {
        let old: Tag
        let new: Tag
        let journalIDs: [String]
        let failures: [String]
    }

    var body: some View {
        HSplitView {
            tagColumn
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
            noteColumn
                .frame(minWidth: 320)
        }
        .background(theme.color(.backgroundPrimary))
        .safeAreaInset(edge: .bottom) { renameBanner }
        .sheet(item: $renaming) { subject in
            TagRenameSheet(old: subject.tag) { new in
                perform(renameOf: subject.tag, to: new)
            } onCancel: {
                renaming = nil
            }
        }
        .toolbar { ToolbarItemGroup(placement: .primaryAction) { themeToggleToolbarItem(themeEngine) } }
    }

    /// What the rename left behind, and the only way back. Shown until it is used or replaced.
    @ViewBuilder
    private var renameBanner: some View {
        if let done = lastRename {
            let count = done.journalIDs.count
            TagRenameBanner(
                summary: "«\(done.old)» è diventato «\(done.new)» in \(count) note",
                failures: done.failures,
                onUndo: undoLastRename,
                onDismiss: { lastRename = nil }
            )
        }
    }

    // MARK: I tag

    private var tagColumn: some View {
        // Counted once per redraw and handed down, never read again from the rows: every
        // access to `usage` runs `tagUsage()` and rebuilds the dictionary, and the pinned
        // rows, the namespaces, their rows and their totals all want the same answer.
        let usage = self.usage
        return VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            List {
                if !vault.pinnedTags.isEmpty {
                    Section {
                        ForEach(vault.pinnedTags, id: \.self) { tag in
                            row(tag, count: usage[tag] ?? 0, isPinned: true)
                        }
                    } header: {
                        Text("APPUNTATI").themedText(.caption, color: .textTertiary)
                    }
                }
                ForEach(namespacesInUse(usage), id: \.self) { namespace in
                    Section {
                        if openNamespaces.contains(namespace) {
                            // The glyph rides the copy inside the namespace too: this is where
                            // being already pinned is not otherwise visible.
                            ForEach(tags(in: namespace, usage: usage), id: \.self) { tag in
                                row(tag, count: usage[tag] ?? 0, isPinned: vault.isPinned(tag))
                            }
                        }
                    } header: {
                        namespaceHeader(namespace, usage: usage)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("tag-list")
        }
        .background(theme.color(.backgroundSecondary))
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("TAG").themedText(.caption, color: .textTertiary)
            Spacer()
            if !chosen.isEmpty {
                Button("Azzera") { chosen = [] }
                    .buttonStyle(.plain)
                    .themedText(.caption, color: .accentPrimary)
                    .accessibilityIdentifier("clear-tags")
            }
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
    }

    private func namespaceHeader(_ namespace: TagNamespace, usage: [Tag: Int]) -> some View {
        Button { toggle(namespace) } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: openNamespaces.contains(namespace) ? "chevron.down" : "chevron.right")
                    .themedText(.caption, color: .textTertiary)
                Text(namespace.rawValue).themedText(.caption, color: .textSecondary)
                Spacer()
                Text("\(total(in: namespace, usage: usage))").themedText(.caption, color: .textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One tag. Filled with the accent when it is in the filter, which is the marking approved
    /// on 2026-08-19: it reads across the room in both themes and adds no glyph to a row that
    /// already carries a name and a number.
    private func row(_ tag: Tag, count: Int, isPinned: Bool) -> some View {
        let isChosen = chosen.contains(tag)
        return HStack(spacing: theme.spacing(.xs)) {
            // Always drawn and hidden when it does not apply, rather than conditional: a row
            // that grows a glyph shifts its own name sideways, and a list where the names do
            // not line up reads as broken before it reads as informative.
            Image(systemName: "pin.fill")
                .themedText(.caption, color: .accentPrimary)
                .opacity(isPinned ? 1 : 0)
                .frame(width: 11, alignment: .leading)
            Text(tag.description)
                .themedText(.body, color: isChosen ? .textPrimary : .textSecondary)
                .lineLimit(1)
            Spacer()
            Text("\(count)").themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(theme.color(isChosen ? .accentMuted : .backgroundSecondary))
        )
        // **A tap gesture and not a `Button`.** A right click on a button fires its action as
        // well as opening the menu, so pinning a chosen tag also unchose it - seen on screen on
        // 2026-08-19, and invisible to every test that calls `togglePin` directly. Safe here
        // where it was not on a note row: this list carries no selection binding to compete
        // with the tap.
        .contentShape(Rectangle())
        .onTapGesture { choose(tag) }
        .contextMenu {
            Button(vault.isPinned(tag) ? "Togli dagli appuntati" : "Appunta in cima") {
                vault.togglePin(tag)
            }
            Divider()
            Button("Rinomina in tutto il vault…") { renaming = RenamingTag(tag: tag) }
        }
        .accessibilityIdentifier("tag-row")
    }

    // MARK: Le note

    private var noteColumn: some View {
        // The same reason as `tagColumn`'s `usage`: every read of `notes` walks the index
        // for the notes carrying all the chosen tags, and the title, the emptiness check
        // and the list itself each used to ask separately.
        let notes = self.notes
        return VStack(alignment: .leading, spacing: 0) {
            Text(noteColumnTitle(count: notes.count)).themedText(.caption, color: .textTertiary)
                .padding(.horizontal, theme.spacing(.m))
                .padding(.vertical, theme.spacing(.s))
            Divider()
            if chosen.isEmpty {
                empty("Scegli un tag per vedere le note che lo portano.")
            } else if notes.isEmpty {
                empty("Nessuna nota porta tutti i tag scelti.")
            } else {
                List {
                    ForEach(notes, id: \.relativePath) { note in
                        noteRow(note)
                    }
                }
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("tag-notes")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundPrimary))
    }

    private func noteRow(_ note: NoteRecord) -> some View {
        Button { open(note) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title).themedText(.body).lineLimit(1)
                Text(subtitle(note)).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tag-note")
    }

    private func empty(_ message: String) -> some View {
        Text(message)
            .themedText(.caption, color: .textTertiary)
            .padding(theme.spacing(.m))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Cosa c'è dentro

    private var usage: [Tag: Int] {
        Dictionary(uniqueKeysWithValues: vault.index.tagUsage().map { ($0.tag, $0.count) })
    }

    /// Only the namespaces this vault actually uses: eight headings, five of them empty, is a
    /// browser describing the grammar rather than the notes.
    private func namespacesInUse(_ usage: [Tag: Int]) -> [TagNamespace] {
        let used = Set(usage.keys.map(\.namespace))
        return TagNamespace.allCases.filter { used.contains($0) }
    }

    private func tags(in namespace: TagNamespace, usage: [Tag: Int]) -> [Tag] {
        usage.keys.filter { $0.namespace == namespace }.sorted()
    }

    private func total(in namespace: TagNamespace, usage: [Tag: Int]) -> Int {
        usage.filter { $0.key.namespace == namespace }.values.reduce(0, +)
    }

    /// The notes carrying **every** chosen tag. AND and not OR: approved on 2026-08-19, and the
    /// only reading under which a second tag narrows anything.
    private var notes: [NoteRecord] { vault.index.notes(carryingAll: chosen) }

    private func noteColumnTitle(count: Int) -> String {
        guard !chosen.isEmpty else { return "NOTE" }
        let names = chosen.sorted().map(\.description).joined(separator: " + ")
        return "NOTE · \(names) (\(count))"
    }

    private func subtitle(_ note: NoteRecord) -> String {
        let folder = note.folder.isEmpty ? "(radice)" : note.folder
        guard let date = note.frontmatter.date else { return folder }
        return "\(folder) · \(date.description)"
    }

    // MARK: I gesti

    private func choose(_ tag: Tag) {
        if chosen.contains(tag) {
            chosen.remove(tag)
        } else {
            chosen.insert(tag)
        }
    }

    private func toggle(_ namespace: TagNamespace) {
        if openNamespaces.contains(namespace) {
            openNamespaces.remove(namespace)
        } else {
            openNamespaces.insert(namespace)
        }
    }

    /// Performs the rename and keeps what it takes to put it back.
    ///
    /// The chosen tags are rewritten as well: a filter still naming the old spelling would show
    /// no notes at all, which reads as "the rename lost them".
    private func perform(renameOf old: Tag, to new: Tag) {
        renaming = nil
        Task { @MainActor in
            let outcome = await vault.renameTag(old, to: new)
            guard !outcome.journalIDs.isEmpty || !outcome.failures.isEmpty else { return }
            if chosen.remove(old) != nil { chosen.insert(new) }
            if vault.isPinned(old) {
                vault.togglePin(old)
                vault.togglePin(new)
            }
            lastRename = FinishedRename(
                old: old, new: new, journalIDs: outcome.journalIDs, failures: outcome.failures
            )
        }
    }

    private func undoLastRename() {
        guard let done = lastRename else { return }
        Task { @MainActor in
            let outcome = await vault.undoJournalledWrites(done.journalIDs)
            lastRename = nil
            if chosen.remove(done.new) != nil { chosen.insert(done.old) }
            if vault.isPinned(done.new) {
                vault.togglePin(done.new)
                vault.togglePin(done.old)
            }
            // A note that had moved on keeps its own text and is named here rather than
            // swallowed.
            if !outcome.failures.isEmpty {
                vault.recordProblem(outcome.failures.joined(separator: "; "))
            }
        }
    }

    /// Opens the note where notes are read. The editor lives in the Note pane and this is a
    /// browser: leaving the person on a list they have just used is leaving them a click short.
    private func open(_ note: NoteRecord) {
        vault.openNote(at: note.relativePath)
        navigation.pane = .notes
    }
}

/// The bar under the browser after a rename: what happened, and the way back.
///
/// A view of its own because the browser is already at the length SwiftLint warns about, and
/// because this is the whole of D7's group undo as a person meets it.
private struct TagRenameBanner: View {
    @Environment(\.theme) private var theme
    let summary: String
    let failures: [String]
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text(summary).themedText(.caption, color: .textSecondary)
            if !failures.isEmpty {
                Text("\(failures.count) non scritte")
                    .themedText(.caption, color: .taskOverdue)
                    .help(failures.joined(separator: "\n"))
            }
            Spacer()
            Button("Annulla la rinomina", action: onUndo)
                .accessibilityIdentifier("undo-tag-rename")
            Button("Chiudi", action: onDismiss)
                .buttonStyle(.plain)
                .themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
        .background(theme.color(.backgroundSecondary))
        .overlay(alignment: .top) { Divider() }
    }
}
