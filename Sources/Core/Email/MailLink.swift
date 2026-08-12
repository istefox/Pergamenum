import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// The `message://` link of the message selected in Apple Mail (SPEC §10, Inserisci).
///
/// AppleScript is the only way in: Mail has no other public interface, and a link
/// typed by hand from the message id is exactly the kind of thing nobody does. The
/// first call raises the Automation consent dialog, which only the user can answer -
/// so a refusal is reported, never treated as "no message selected".
enum MailLink {
    struct Link: Equatable, Sendable {
        var subject: String
        var url: String
    }

    /// Why Mail could not be asked, in words the user can act on.
    struct Failure: Error, Equatable, Sendable, CustomStringConvertible {
        var description: String
    }

    /// Builds the URL from a message id, escaping the angle brackets Mail expects.
    ///
    /// RFC 5322 writes a message id inside `<…>`, and `message://` requires them
    /// percent-encoded; a link without them opens nothing.
    static func url(forMessageID messageID: String) -> String? {
        let trimmed = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "%"))
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        return "message://%3C\(encoded)%3E"
    }

    /// Parses what the AppleScript returns: the id on the first line, the subject on
    /// the rest, since a subject may contain anything including a newline.
    static func parse(scriptOutput: String) -> Link? {
        let lines = scriptOutput.components(separatedBy: "\n")
        guard let first = lines.first, let url = url(forMessageID: first) else { return nil }
        let subject = lines.dropFirst().joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Link(subject: subject.isEmpty ? "Email" : subject, url: url)
    }

    #if canImport(AppKit)
    private static let script = """
    tell application "Mail"
        set chosen to selection
        if (count of chosen) is 0 then return ""
        set theMessage to item 1 of chosen
        return (message id of theMessage) & "\\n" & (subject of theMessage)
    end tell
    """

    /// Asks Mail for its current selection.
    @MainActor
    static func selectedMessage() -> Result<Link, Failure> {
        guard let apple = NSAppleScript(source: script) else {
            return .failure(Failure(description: "lo script per Mail non è compilabile"))
        }
        var error: NSDictionary?
        let output = apple.executeAndReturnError(&error)

        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            return .failure(Failure(description: "Mail: \(message)"))
        }
        guard let text = output.stringValue, !text.isEmpty else {
            return .failure(Failure(description: "nessun messaggio selezionato in Mail"))
        }
        guard let link = parse(scriptOutput: text) else {
            return .failure(Failure(description: "il messaggio selezionato non ha un id utilizzabile"))
        }
        return .success(link)
    }
    #endif
}
