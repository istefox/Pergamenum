import SwiftUI

/// The visual builder for a `pergamenum-view` fence (ADR-0034): a `ViewQueryDraft` composed
/// through seven sections, in `ViewBlock`'s own key order, and committed through the anchor
/// the sheet was opened on (`onCommit`, `ViewQueryEditRequest.commit`'s exact shape) rather
/// than a second write path.
///
/// The draft can never disagree with the note (§D7): everything "Fatto" is able to write is
/// text `ViewBlock.parse` has already accepted, because `validation(of:)` *is* that parser,
/// reached through its one public entry point, and nothing here re-implements what it
/// decides.
struct ViewQueryBuilderSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The fence's body at the moment the sheet opened — what the draft is seeded from.
    let source: String
    /// Nil where there is no vault behind the sheet (a preview, a test): the live match
    /// count (Task 7) then stays absent rather than reading as zero matches.
    var queries: ViewQuerySource?
    /// The written body, in; `true` when the note was rewritten. A `false` is a refused
    /// commit (the fence moved on out from under the sheet, ADR §D3) — "Fatto" being
    /// disabled already rules out a validation failure ever reaching this closure.
    var onCommit: (String) -> Bool
    /// Called once, when the sheet closes without a successful write — «Annulla», or a
    /// refused commit's own eventual dismissal. Never called after "Fatto" actually wrote.
    var onCancel: () -> Void = {}

    @State private var draft: ViewQueryDraft
    @State private var refusedReason: String?

    init(
        source: String,
        queries: ViewQuerySource? = nil,
        onCommit: @escaping (String) -> Bool,
        onCancel: @escaping () -> Void = {}
    ) {
        self.source = source
        self.queries = queries
        self.onCommit = onCommit
        self.onCancel = onCancel
        _draft = State(initialValue: .seed(from: source))
    }

    private var validationResult: Result<ViewBlock, ViewBlockError> {
        Self.validation(of: draft)
    }

    private var isValid: Bool {
        if case .success = validationResult { return true }
        return false
    }

    /// «Fatto»'s own inline reason: the refused-commit message when there is one,
    /// otherwise the validator's `ViewBlockError.description`, already «riga N: motivo» in
    /// the app's language.
    private var reason: String? {
        if let refusedReason { return refusedReason }
        if case .failure(let error) = validationResult { return error.description }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Modifica query").themedText(.title)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    ViewQueryScopeSection(draft: draft)
                    ViewQueryFilterSection(draft: draft)
                    ViewQuerySortSection(draft: draft)
                    // R-08: present only for a board, and never restated as a requirement
                    // here — §D7's round trip through `ViewBlock.parse` is what turns a
                    // board with no group into `assemble`'s own error.
                    if draft.render == .board {
                        ViewQueryGroupSection(draft: draft)
                    }
                    ViewQueryRenderSection(draft: draft)
                    ViewQueryColumnsSection(draft: draft)
                    ViewQueryLimitSection(draft: draft)
                }
            }
            .frame(maxHeight: 420)

            if let reason {
                Text(reason)
                    .themedText(.caption, color: .taskOverdue)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("view-query-reason")
            }

            HStack {
                Spacer()
                Button("Annulla") { cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("view-query-cancel")
                Button("Fatto") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
                    .accessibilityIdentifier("view-query-done")
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 560)
        .background(theme.color(.surfaceCard))
        .accessibilityIdentifier("view-query-builder")
    }

    private func cancel() {
        onCancel()
        dismiss()
    }

    private func commit() {
        guard isValid else { return }
        if onCommit(ViewQueryText.body(of: draft)) {
            dismiss()
        } else {
            // The SPEC's edge case (ADR §D3): the fence moved on under the sheet. The
            // sheet stays open and says so, rather than closing on a write that never
            // happened.
            refusedReason = "la vista è cambiata da quando è stata aperta: riprova"
        }
    }
}

extension ViewQueryBuilderSheet {
    /// Whether `draft` is a fence `ViewBlock.parse` would accept, and what it says when it
    /// is not — the single computation "Fatto", its inline reason and the live count (Task
    /// 7) all consult (ADR-0034 §D7). The draft is written out and handed to the real
    /// parser, so the sheet can never disagree with the note: not a second checker,
    /// `ViewBlock.parse` itself, reached through its one entry point.
    static func validation(of draft: ViewQueryDraft) -> Result<ViewBlock, ViewBlockError> {
        if let incomplete = incompleteTermError(in: draft) {
            return .failure(incomplete)
        }
        do {
            return .success(try ViewBlock.parse(ViewQueryText.body(of: draft)))
        } catch let error as ViewBlockError {
            return .failure(error)
        } catch {
            return .failure(ViewBlockError(line: 1, reason: "\(error)"))
        }
    }

    /// §D7's named exception: the writer omits an unfinished term row rather than write
    /// `tag("")` (`ViewQueryText.isComplete`), so a draft holding one still writes a body
    /// `ViewBlock.parse` accepts — and would validate `.success` on that alone, silently
    /// dropping the row the person is still composing. Checked before the round trip, so
    /// its own reason — never the parser's, which never sees the omitted row — is what
    /// disables "Fatto".
    private static func incompleteTermError(in draft: ViewQueryDraft) -> ViewBlockError? {
        guard draft.rawWhere == nil else { return nil }
        guard let index = draft.terms.firstIndex(where: { !ViewQueryText.isComplete($0) }) else {
            return nil
        }
        return ViewBlockError(line: index + 1, reason: "una riga del filtro non ha ancora un argomento")
    }
}
