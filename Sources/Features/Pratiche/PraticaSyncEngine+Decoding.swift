import Foundation

extension PraticaSyncEngine {
    // MARK: - Reading the message

    /// `EmailHeaderParser` stops at the first blank line, but it splits on `.newlines`,
    /// where a bare `\r\n` yields an empty component - the same normalisation
    /// `MIMEDecoder` does before calling it, and without which every CRLF message
    /// parses as having no headers at all.
    ///
    /// Not `private`, on this member and every other one below down to `tags(for:)`
    /// except `normalised(_:)`: `PraticaSyncEngine+Messages.swift`'s `prepare(_:request:
    /// reader:folder:)` is an extension of this actor in a separate file, and is their
    /// only caller.
    static func headerText(of rfc822: Data) -> String {
        let end = EMLXReader.headerBodySeparator(in: rfc822) ?? rfc822.endIndex
        return String(decoding: rfc822[rfc822.startIndex..<end], as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }

    /// SPEC "Sync algorithm": «text/plain preferred, else HTML→markdown».
    static func bodyText(of parts: [MIMEPart]) -> String {
        let plain = parts.first { $0.kind == .textPlain }?.decodedText ?? ""
        if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalised(plain)
        }
        guard let html = parts.first(where: { $0.kind == .textHTML })?.decodedText else {
            return normalised(plain)
        }
        return normalised(HTMLTextReducer.reduce(html))
    }

    /// A note in this vault has Unix line endings; a message off the wire has CRLF.
    /// `private`: only `bodyText(of:)` above, in this same file, reads it.
    private static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .newlines)
    }

    static func addresses(of name: String, in headers: EmailHeaders) -> [EmailAddress] {
        guard let raw = headers.all.first(where: { $0.name.lowercased() == name })?.value
        else { return [] }
        return EmailHeaderParser.parseAddressList(raw)
    }

    /// `Mario Rossi <m.rossi@rossi-spa.it>`, the form the SPEC's own frontmatter
    /// example carries.
    static func headerForm(_ address: EmailAddress) -> String {
        guard let name = address.name, !name.isEmpty else { return address.address }
        return "\(name) <\(address.address)>"
    }

    static func time(of date: Date) -> TaskTime {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TaskTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    /// ADR §D11's tag set for a message file: `type-note` (what `missingRequired`
    /// demands of every non-daily note - two `type-*` tags is legal, only `status` is
    /// limited to one), `type-email`, `topic-pratica`, the pratica's own
    /// `client-<slug>` when the folder layout gives one, and `source-email`.
    static func tags(for request: SyncRequest) -> [Tag] {
        [
            Tag("type-note"),
            Tag("type-email"),
            Tag("topic-pratica"),
            PraticaNaming.clientTag(
                forPraticaAt: request.praticaFolder, root: request.settings.rootFolder
            ),
            Tag("source-email"),
        ].compactMap { $0 }
    }
}
