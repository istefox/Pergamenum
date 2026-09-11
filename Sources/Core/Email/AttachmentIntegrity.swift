import Foundation

// ADR-0040 (Pratiche attachment reliability bugs) §D1, §D2, plan
// docs/superpowers/plans/2026-09-11-pratiche-attachment-reliability-bugs.md, Task 1 -
// R-01, R-02, R-03.
//
// Tester-declared interface (ADR-0155 §D1): the signature below is final, the bodies
// are placeholders for the coder to replace with ADR-0040 §D2's six-rule table. Every
// body here returns `.usable` unconditionally, which is obviously wrong for most of
// `Tests/AttachmentIntegrityTests.swift` - that is what keeps those assertions red.
//
// It joins the file family `EMLXReader`/`MIMEDecoder`/`EMLXLocator`/`InlineImageClassifier`
// already form (§D1) - Foundation only, no ImageIO, no UTType, no NSWorkspace, so a file
// under `Sources/Core/**` that imports AppKit or SwiftUI never happens here and both
// connector builds (`perg`, `pergamenum-mcp`) stay unaffected (ADR-0001 §D1).
enum AttachmentIntegrity {
    /// Why an attachment's bytes are not the file the sender attached. `.usable` is the
    /// only verdict that may be hashed, placed or opened.
    enum Verdict: Equatable, Sendable {
        case usable
        /// Nothing at all: Mail has the part's headers and none of its bytes.
        case empty
        /// A signature is known for this part's declared type or extension and the
        /// leading bytes are not it.
        case signatureMismatch
        /// The head signature matched and the format's own terminator is missing -
        /// the download stopped part way (§D2).
        case truncated
    }

    /// Decides on bytes already in memory. `contentType` is the part's declared
    /// `Content-Type` base form (`"application/pdf"`), `name` its declared filename -
    /// either may be `nil`, and a part that offers neither is judged on emptiness alone.
    ///
    /// - TODO(coder, ADR-0040 §D2): replace this placeholder with the six-rule table.
    static func verdict(of bytes: Data, named name: String?, contentType: String?) -> Verdict {
        .usable
    }

    /// Decides on a file already on disk without reading it whole: the size, the first
    /// `signatureWindow` bytes and the last `terminatorWindow` bytes. A 400 MB store
    /// reference must not be slurped to draw a chip (§D8, R-07, R-09).
    ///
    /// - TODO(coder, ADR-0040 §D2): replace this placeholder. The real implementation
    ///   reads the size through `URL.resourceValues(forKeys: [.fileSizeKey])` and two
    ///   windows through a `FileHandle` (`read(upToCount:)` from the start,
    ///   `seek(toOffset:)` + `readToEnd()` for the tail) - never Foundation's whole-file
    ///   `Data` loader.
    static func verdict(ofFileAt url: URL, named name: String?) -> Verdict {
        .usable
    }
}
