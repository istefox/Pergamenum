import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D1/§D2, plan
// docs/plans/contenitore.md, Task 2 - R-02, R-17.

/// What a scheda's frontmatter says about its document, as the index keeps it (ADR-0071 §D2).
///
/// Present on a `NoteRecord` only when the note carries `pergamenum-contenitore: 1`. Whether
/// the note also sits under the Contenitore root is a setting, evaluated at read time
/// (`IndexSnapshot.schede(underRoot:)`), never stored here.
struct ContenitoreFacts: Equatable, Sendable, Codable {
    /// The companion file's name, the target of the `pergamenum-contenitore-file` wikilink:
    /// `20260929 preventivo.pdf`. Empty when the key is missing or unreadable.
    var fileName: String
    /// The name the file had in the drop folder.
    var originalName: String
    /// The file's SHA-256 at import, lowercase hex, or nil when the key is absent.
    var sha256: String?
    /// The colour, when `rawColour` names one of the six presets.
    var colour: ContenitoreColour?
    /// The colour value as written, kept even when it names no preset: an unrecognised value
    /// reads as no colour and stays on disk until the colour is set again (§D1).
    var rawColour: String?
}

/// Renders and reads a scheda's `pergamenum-contenitore*` keys (ADR-0071 §D1).
///
/// One pure type for both directions, so the lines a scheda is recognised by are written and
/// read in one place. Edits to an existing scheda go through `NoteDocument`, so a change to one
/// key rewrites that key's line and leaves every other byte of the block as it was read
/// (ADR-0065 §D2).
enum ContenitoreScheda {
    static let schemaKey = "pergamenum-contenitore"
    static let fileKey = "pergamenum-contenitore-file"
    static let originalKey = "pergamenum-contenitore-original"
    static let sha256Key = "pergamenum-contenitore-sha256"
    static let colourKey = "pergamenum-contenitore-color"

    /// The schema value this version writes and recognises. Any other value leaves the note an
    /// ordinary note, its keys preserved byte for byte.
    static let schemaVersion = 1

    /// A new scheda's whole text: `date` (the import day), `tags: [type-note, status-inbox]`,
    /// the four keys that are always written, and an empty body. It passes the linter as
    /// written, because `status-inbox` exempts the `topic-*` requirement.
    static func render(date: CalendarDate, fileName: String, originalName: String, sha256: String) -> String {
        var frontmatter = Frontmatter.empty
        frontmatter.date = date
        frontmatter.tags = TagRules.initialTags(for: .capture)
        frontmatter.foreignKeys = [
            Frontmatter.ForeignKey(name: schemaKey, lines: ["\(schemaKey): \(schemaVersion)"]),
            Frontmatter.ForeignKey(name: fileKey, lines: ["\(fileKey): \(quoted("[[\(fileName)]]"))"]),
            Frontmatter.ForeignKey(name: originalKey, lines: ["\(originalKey): \(quoted(originalName))"]),
            Frontmatter.ForeignKey(name: sha256Key, lines: ["\(sha256Key): \(quoted(sha256.lowercased()))"]),
        ]
        return FrontmatterSerializer.render(frontmatter)
    }

    /// The scheda facts a note's foreign keys carry, or nil unless `pergamenum-contenitore` is
    /// exactly `1`. A duplicated key is read at its last occurrence, the governing one
    /// (ADR-0065 §D2).
    static func facts(in foreignKeys: [Frontmatter.ForeignKey]) -> ContenitoreFacts? {
        guard let schema = value(of: schemaKey, in: foreignKeys).map(unquoted),
              Int(schema) == schemaVersion
        else { return nil }

        let fileValue = value(of: fileKey, in: foreignKeys).map(unquoted) ?? ""
        let fileName = WikilinkParser.links(in: fileValue).first?.target ?? fileValue
        let sha256 = value(of: sha256Key, in: foreignKeys).map(unquoted)?.lowercased()
        let rawColour = value(of: colourKey, in: foreignKeys).map(unquoted)
        return ContenitoreFacts(
            fileName: fileName.trimmingCharacters(in: .whitespaces),
            originalName: value(of: originalKey, in: foreignKeys).map(unquoted) ?? "",
            sha256: sha256?.isEmpty == false ? sha256 : nil,
            colour: rawColour.flatMap { ContenitoreColour(rawValue: $0.lowercased()) },
            rawColour: rawColour?.isEmpty == false ? rawColour : nil
        )
    }

    /// The vault-relative path of the file the scheda at `schedaPath` owns, from the file name its
    /// key holds: in the scheda's own folder, with the scheda's own stem. Nil when the key names
    /// nothing, names a path, names a note, or names some other stem.
    ///
    /// The stem check is a guard, not a formality: a key edited by hand to name some other file
    /// must not make a rename of the scheda rename that file too, and a scheda renamed alone in the
    /// Finder no longer owns the file its key still names. This is the one place the rule lives:
    /// `VaultSession.companion(ofScheda:)` adds only the existence check, and the pane's rows
    /// derive their file path and their «file mancante» from the same answer. Pure, so it needs
    /// no file system.
    static func companionPath(ofSchedaAt schedaPath: String, fileName: String) -> String? {
        guard !fileName.isEmpty, !fileName.contains("/") else { return nil }

        let stem = NoteName.title(fromFileName: (schedaPath as NSString).lastPathComponent).lowercased()
        let lowered = fileName.lowercased()
        guard lowered == stem || lowered.hasPrefix(stem + "."), !lowered.hasSuffix(".md") else { return nil }

        let folder = (schedaPath as NSString).deletingLastPathComponent
        return folder.isEmpty ? fileName : "\(folder)/\(fileName)"
    }

    /// `text` with its colour key set to `colour`, or removed when `colour` is nil. Only that
    /// key's line changes; a new key is added as the block's last line.
    static func settingColour(_ colour: ContenitoreColour?, in text: String) -> String {
        var document = NoteDocument.parse(text)
        var keys = document.frontmatter.foreignKeys
        if let colour {
            let key = Frontmatter.ForeignKey(name: colourKey, lines: ["\(colourKey): \(colour.rawValue)"])
            if let governing = keys.lastIndex(where: { $0.name == colourKey }) {
                keys[governing] = key
            } else {
                keys.append(key)
            }
        } else {
            keys.removeAll { $0.name == colourKey }
        }
        document.frontmatter.foreignKeys = keys
        return document.serialized()
    }

    /// `text` with its governing `pergamenum-contenitore-file` key naming `fileName`, or `text`
    /// unchanged when it has no such key. The pair rename uses it for the scheda's own key, which
    /// names its companion by definition and so follows a rename even when the old file name is
    /// ambiguous elsewhere in the vault (ADR-0071 §D6).
    static func settingFileName(_ fileName: String, in text: String) -> String {
        var document = NoteDocument.parse(text)
        var keys = document.frontmatter.foreignKeys
        guard let governing = keys.lastIndex(where: { $0.name == fileKey }) else { return text }
        let line = "\(fileKey): \(quoted("[[\(fileName)]]"))"
        guard keys[governing].lines != [line] else { return text }
        keys[governing] = Frontmatter.ForeignKey(name: fileKey, lines: [line])
        document.frontmatter.foreignKeys = keys
        return document.serialized()
    }

    // MARK: - Scalars

    /// The inline value of the last occurrence of `key`, trimmed, or nil when absent.
    private static func value(of key: String, in foreignKeys: [Frontmatter.ForeignKey]) -> String? {
        guard let line = foreignKeys.last(where: { $0.name == key })?.lines.first,
              let colon = line.firstIndex(of: ":")
        else { return nil }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    /// A double-quoted YAML scalar, `DossierYAML`'s escaping (ADR-0065 §D13.2): an original
    /// name is text somebody else chose, and a `"` or a line break in it must not end the value.
    private static func quoted(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }

    /// The exact inverse of `quoted`; a single-quoted value is only stripped, and a bare value
    /// is returned as written.
    private static func unquoted(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard scalars.count >= 2, let first = scalars.first, let last = scalars.last else { return value }
        if first == "'" && last == "'" { return String(value.dropFirst().dropLast()) }
        guard first == "\"" && last == "\"" else { return value }

        var result = String.UnicodeScalarView()
        var pendingBackslash = false
        for scalar in scalars.dropFirst().dropLast() {
            if pendingBackslash {
                pendingBackslash = false
                if let decoded = unescaped(scalar) {
                    result.append(decoded)
                } else {
                    result.append("\\")
                    result.append(scalar)
                }
            } else if scalar == "\\" {
                pendingBackslash = true
            } else {
                result.append(scalar)
            }
        }
        if pendingBackslash { result.append("\\") }
        return String(result)
    }

    /// What a backslash followed by `scalar` stands for in `quoted`'s output, or nil for a pair
    /// `quoted` never writes, which `unquoted` keeps as written.
    private static func unescaped(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        switch scalar {
        case "\\": "\\"
        case "\"": "\""
        case "n": "\n"
        case "r": "\r"
        default: nil
        }
    }
}
