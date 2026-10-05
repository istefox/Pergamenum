import Foundation

/// The title a capture «Nota nuova» gives its note (ADR-0080 §D3).
///
/// Capture is the one surface that derives a title instead of refusing one: it is
/// fire-and-forget over another application, and a refusal there costs the moment the
/// text was captured in. `VaultSession.createNote` itself still refuses an invalid
/// title; this function only ever hands it one `NoteName.validate` accepts.
///
/// One function serves the panel's «Titolo: …» caption and the file the capture
/// writes, so the two cannot disagree.
struct CaptureTitle: Equatable, Sendable {
    /// The title the note will carry.
    let title: String
    /// Whether `title` is not the line the person typed. When it is not, the whole
    /// capture goes to the body, so nothing typed is lost.
    let differsFromTyped: Bool

    /// The first line of a capture, trimmed of outer whitespace.
    ///
    /// Ends at the first `endsTypedLine` character, so `"\r\n"` is one break and leaves no
    /// `"\r"` on the title (PG-327).
    static func typedLine(of text: String) -> String {
        let end = text.firstIndex(where: endsTypedLine) ?? text.endIndex
        return text[..<end].trimmingCharacters(in: .whitespaces)
    }

    /// Whether a character ends a capture's typed line: what `LineBreak.isTerminator` reads
    /// as a break, plus a lone `"\r"`, which would otherwise reach a file name. Capture splits
    /// its body at the same character, so the line and the body never disagree on where the
    /// first line stops.
    static func endsTypedLine(_ character: Character) -> Bool {
        LineBreak.isTerminator(character) || character == "\r"
    }

    /// The title for a typed first line, derived when `NoteName.validate` refuses it.
    ///
    /// A legal line is the title unchanged. Otherwise the derivation steps repeat until
    /// the result stops changing, so a cut that exposes a version token or a leading dot
    /// is repaired too. When nothing survives, the title is `YYYYMMDD HHmm Cattura` in
    /// `calendar`'s time zone at `now`.
    static func derive(fromTypedLine typed: String, now: Date, calendar: Calendar) -> CaptureTitle {
        if NoteName.validate(typed).isEmpty {
            return CaptureTitle(title: typed, differsFromTyped: false)
        }
        var current = typed
        while true {
            let next = derivationPass(current)
            if next == current { break }
            current = next
        }
        // The steps above already give a legal name or nothing; this guard holds the
        // promise even if a later rule in `NoteName` outgrows them.
        let title = !current.isEmpty && NoteName.validate(current).isEmpty
            ? current
            : fallbackTitle(now: now, calendar: calendar)
        return CaptureTitle(title: title, differsFromTyped: title != typed)
    }

    /// One pass of ADR-0080 §D3's steps, in order.
    private static func derivationPass(_ text: String) -> String {
        // Forbidden characters become spaces, so `3/10` does not become `310`.
        let spaced = String(text.map { NoteName.forbiddenCharacters.contains($0) ? " " : $0 })
        var result = collapsingWhitespace(spaced)
        result = String(result.drop { $0 == "." }).trimmingCharacters(in: .whitespaces)
        if let token = NoteName.versionSuffix(in: result) {
            result = removingTrailingVersionToken(token, from: result)
        }
        if result.count > NoteName.maximumLength {
            result = ImportNaming.truncatedAtSpace(result, toFit: NoteName.maximumLength)
        }
        return result
    }

    /// Each run of whitespace becomes one space, then the ends are trimmed.
    private static func collapsingWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Removes `token`, the trailing version token `NoteName.versionSuffix(in:)` found,
    /// together with the separator in front of it.
    private static func removingTrailingVersionToken(_ token: String, from text: String) -> String {
        let separators: Set<Character> = [" ", "_", "-"]
        var result = Substring(text)
        while let last = result.last, separators.contains(last) { result = result.dropLast() }
        guard result.hasSuffix(token) else { return text }
        result = result.dropLast(token.count)
        while let last = result.last, separators.contains(last) { result = result.dropLast() }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// `YYYYMMDD HHmm Cattura`, read from the components rather than a formatter so the
    /// digits never depend on a locale.
    private static func fallbackTitle(now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        func padded(_ value: Int?, _ width: Int) -> String {
            let digits = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        let day = padded(parts.year, 4) + padded(parts.month, 2) + padded(parts.day, 2)
        let time = padded(parts.hour, 2) + padded(parts.minute, 2)
        return "\(day) \(time) Cattura"
    }
}
