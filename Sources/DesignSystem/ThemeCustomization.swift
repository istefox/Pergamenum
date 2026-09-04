import Foundation

/// The colours the user picked, as a token file in the vault.
///
/// Choosing a colour in Settings does not set a value in memory: it writes a real
/// DTCG file into `.pergamenum/themes/`, the same directory a hand-written theme
/// lives in and the same format `ThemeEngine` already reads. The customisation is
/// therefore a theme like any other — it travels with the vault, it can be edited in
/// a text editor, and deleting the file undoes it completely (SPEC §11.3, and the
/// file-over-app principle of §3).
///
/// Only the tokens the user actually changed are written. Everything else inherits
/// from the bundled theme whose appearance this one declares, which is why a file of
/// three colours is a valid theme rather than a broken one.
enum ThemeCustomization {
    /// The id, and so the file name, of the theme Settings writes.
    static let id = "personalizzato"
    static let displayName = "Personalizzato"

    /// What is in the file: which bundled theme it builds on, and the overrides.
    struct Draft: Equatable, Sendable {
        var appearance: ThemeAppearance
        var colors: [ColorToken: RGBA]
        /// The prose face overrides (ADR-0030 §D9): `.prose`/`.proseTitle` only, but
        /// keyed by the whole `FontToken` rather than a narrower pair type, the same
        /// way `colors` is keyed by the whole `ColorToken` rather than the subset a
        /// given theme happens to override. Defaulted so every existing call site
        /// that only ever set colours keeps compiling unchanged.
        var fonts: [FontToken: TypographyValue] = [:]

        var isEmpty: Bool { colors.isEmpty && fonts.isEmpty }
    }

    static func url(in directory: URL) -> URL {
        directory.appending(path: "\(id).json", directoryHint: .notDirectory)
    }

    // MARK: Reading

    /// Reads back what Settings wrote, so the colour wells open on the user's own
    /// values rather than resetting to the base theme every time the pane appears.
    static func load(from directory: URL) -> Draft? {
        guard let data = try? Data(contentsOf: url(in: directory)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Both shapes are read: the token form this writes, and the bare string a
        // person editing the file by hand is likely to type.
        let meta = root["meta"] as? [String: Any]
        let declared = ((meta?["appearance"] as? [String: Any])?["$value"] as? String)
            ?? (meta?["appearance"] as? String)
            ?? ""
        var colors: [ColorToken: RGBA] = [:]
        for token in ColorToken.allCases {
            guard let raw = value(at: token.path, in: root) as? String,
                  let rgba = RGBA(hex: raw) else { continue }
            colors[token] = rgba
        }
        // Coder-owned (ADR-0155 §D1, Task 7): read `.prose`/`.proseTitle` back from
        // the `font.*` group the way the loop above reads `color.*`, into `fonts`.
        // Left empty for now, which is also the correct answer for a file an older
        // build wrote with no `font` section at all (R-12).
        let fonts: [FontToken: TypographyValue] = [:]
        return Draft(appearance: ThemeAppearance(rawValue: declared) ?? .light, colors: colors, fonts: fonts)
    }

    /// Follows a dotted token path down the nested object and returns its `$value`.
    private static func value(at path: String, in root: [String: Any]) -> Any? {
        var node: Any? = root
        for component in path.split(separator: ".") {
            guard let object = node as? [String: Any] else { return nil }
            node = object[String(component)]
        }
        return (node as? [String: Any])?["$value"]
    }

    // MARK: Writing

    static func write(_ draft: Draft, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: object(from: draft),
            // Sorted and pretty for the same reason the canvas writer is: a file that
            // did not change in content must not change on disk, or every colour pick
            // produces a diff across the whole file.
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url(in: directory), options: .atomic)
    }

    /// Removes the file, which is the whole of "back to the base theme".
    static func remove(from directory: URL) throws {
        let file = url(in: directory)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: file)
    }

    static func object(from draft: Draft) -> [String: Any] {
        // `meta` is written as DTCG tokens, not as bare strings, because that is how
        // the reader takes it: a plain `"appearance": "dark"` is not a token node, so
        // the engine never saw the declared appearance, inherited from the light base
        // whatever the user had chosen, and logged two "expected a token or a group"
        // problems into Settings for good measure.
        var root: [String: Any] = [
            "meta": [
                "name": ["$type": "string", "$value": displayName],
                "appearance": ["$type": "string", "$value": draft.appearance.rawValue],
            ],
        ]
        // Sorted, so the nesting is built in a stable order and two runs that picked
        // the same colours produce byte-identical files.
        for token in draft.colors.keys.sorted(by: { $0.path < $1.path }) {
            guard let rgba = draft.colors[token] else { continue }
            insert(
                ["$type": "color", "$value": rgba.hexString],
                at: token.path.split(separator: ".").map(String.init),
                into: &root
            )
        }
        // Coder-owned (ADR-0155 §D1, Task 7): a typography branch mirroring the
        // colour loop above, sorted the same way for the same byte-stability
        // guarantee, writing `draft.fonts` as `$type: "typography"` nodes with
        // `fontFamily`/`fontSize`/`fontWeight`/`lineHeight` (`TypographyValue.Family`'s
        // `rawValue` round trip, Task 1). `draft.fonts` is deliberately unread here —
        // that omission is what keeps the round-trip test red.
        return root
    }

    /// Grows the nested object a dotted path describes, without disturbing siblings
    /// already written at the same level.
    private static func insert(_ leaf: [String: Any], at path: [String], into node: inout [String: Any]) {
        guard let head = path.first else { return }
        if path.count == 1 {
            node[head] = leaf
            return
        }
        var child = node[head] as? [String: Any] ?? [:]
        insert(leaf, at: Array(path.dropFirst()), into: &child)
        node[head] = child
    }
}
