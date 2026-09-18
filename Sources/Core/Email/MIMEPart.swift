import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-05.

/// One decoded part of a (possibly multipart) message, as `MIMEDecoder.decode(_:)`
/// walks it.
struct MIMEPart: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case textPlain
        case textHTML
        /// Referenced from the body by `cid:<contentID>` (the angle brackets stripped,
        /// matching `EmailHeaders.messageID`'s own convention).
        case inlineImage(contentID: String)
        case attachment(filename: String?)
    }

    var kind: Kind
    /// The part's own `Content-Type`, lowercased, without parameters - `"text/html"`,
    /// never `"text/html; charset=utf-8"`.
    var contentType: String
    /// This part's header fields, unfolded - what `contentType`/`kind` are derived
    /// from, kept for anything this app does not model (mirrors
    /// `EmailHeaders.all`).
    var headers: [(name: String, value: String)]
    /// Present for `.textPlain`/`.textHTML`, decoded through the part's
    /// `Content-Transfer-Encoding` and charset (R-05).
    var decodedText: String?
    /// Present for `.inlineImage`/`.attachment`, decoded through the part's transfer
    /// encoding but never charset-interpreted.
    var decodedData: Data?
    var filename: String?
    /// This part's position in Mail's own IMAP-style (RFC 3501) body-part numbering: a
    /// multipart container's immediate children are numbered `1, 2, 3…` in document
    /// order, *including* nested container parts themselves (which consume a number
    /// but produce no `MIMEPart` of their own); a child that is itself a `multipart/*`
    /// container has its own children numbered `<parent>.1`, `<parent>.2`, …,
    /// recursively. A non-multipart message's single part is `"1"`. This is the number
    /// Mail's sibling `Attachments/<rowID>/<part>/` directory is keyed by (ADR-0048) -
    /// not the flat index this array's own decode order carries, which diverges from
    /// it as soon as any part nests or a non-attachment leaf precedes the attachment.
    var partNumber: String

    static func == (lhs: MIMEPart, rhs: MIMEPart) -> Bool {
        lhs.kind == rhs.kind && lhs.contentType == rhs.contentType
            && lhs.headers.map(\.name) == rhs.headers.map(\.name)
            && lhs.headers.map(\.value) == rhs.headers.map(\.value)
            && lhs.decodedText == rhs.decodedText && lhs.decodedData == rhs.decodedData
            && lhs.filename == rhs.filename && lhs.partNumber == rhs.partNumber
    }
}
