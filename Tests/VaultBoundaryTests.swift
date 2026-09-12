import Foundation
import Testing
@testable import Pergamenum

/// R-01/R-02 integration contract from Task 1's brief. These tests exercise the
/// existing store until the coder declares VaultBoundary in the production target.
/// Direct resolver/contains tests and the policy for empty and dot paths remain
/// pending that declaration. No test-local replacement shadows the production API.
@Suite("Vault boundary integration: R-01, R-02")
struct VaultBoundaryTests {
    @Test("Traversal preserves the original path and cannot read or overwrite a sibling",
          arguments: ["../../etc/passwd", "../sibling/x.md", "a/../../x.md", "a/b/../../../x.md"])
    func refusesTraversal(path: String) throws {
        let fixture = try BoundaryFixture()
        let outside = fixture.root.appending(path: path).standardizedFileURL
        try fixture.seed("outside sentinel", at: outside)
        let store = NoteStore(root: fixture.root)

        expectOutsideVault(path) {
            _ = try store.read(path)
        }
        expectOutsideVault(path) {
            _ = try store.write("must not overwrite", to: path)
        }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside sentinel")
    }

    @Test("Absolute reads are rejected as boundary violations", arguments: ["/etc/passwd", "/x.md"])
    func refusesAbsoluteReads(path: String) throws {
        let fixture = try BoundaryFixture()
        expectOutsideVault(path) {
            _ = try NoteStore(root: fixture.root).read(path)
        }
    }

    @Test("An absolute write cannot modify an outside file or create an inside copy")
    func refusesAbsoluteWrite() throws {
        let fixture = try BoundaryFixture()
        let outside = fixture.container.appending(path: "outside.md")
        try fixture.seed("outside sentinel", at: outside)
        let path = outside.path(percentEncoded: false)

        expectOutsideVault(path) {
            _ = try NoteStore(root: fixture.root).write("must not write", to: path)
        }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside sentinel")
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appending(path: path).path))
    }

    @Test("An internal parent component is legal and resolves to the expected note")
    func acceptsInternalParent() throws {
        let fixture = try BoundaryFixture()
        try FileManager.default.createDirectory(
            at: fixture.root.appending(path: "a"), withIntermediateDirectories: true
        )
        let store = NoteStore(root: fixture.root)

        _ = try store.write("inside", to: "a/../b.md")

        #expect(try store.read("b.md").text == "inside")
        #expect(try store.read("a/../b.md").text == "inside")
        #expect(store.url(for: "a/../b.md").standardizedFileURL.path ==
                fixture.root.appending(path: "b.md").path)
    }

    /// Task 1 explicitly permits choosing a policy for ./x.md: accept it as x.md.
    /// Empty and dot-only paths await the coder's resolver policy; NoteStore.read
    /// cannot distinguish a resolver decision from a subsequent directory-I/O error.
    @Test("Legal filenames remain literal and inside the vault",
          arguments: ["./x.md", "Note/Perché 日本語.md", "%2e%2e/x.md"])
    func acceptsLiteralNames(path: String) throws {
        let fixture = try BoundaryFixture()
        let store = NoteStore(root: fixture.root)

        _ = try store.write("literal contents", to: path)

        #expect(try store.read(path).text == "literal contents")
        let expected = fixture.root.appending(path: path).standardizedFileURL
        #expect(try String(contentsOf: expected, encoding: .utf8) == "literal contents")
    }

    @Test("A real symlink root allows creating a note that does not exist yet")
    func createsNewNoteThroughSymlink() throws {
        let fixture = try BoundaryFixture()
        let link = fixture.container.appending(path: "linked-vault")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.root)
        let destination = fixture.root.appending(path: "Nuova.md")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let store = NoteStore(root: link)

        #expect(store.root.path == fixture.root.path)
        #expect(store.url(for: "Nuova.md").path == destination.path)
        _ = try store.write("new note", to: "Nuova.md")

        #expect(try store.read("Nuova.md").text == "new note")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "new note")
    }
}

private func expectOutsideVault(
    _ path: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    operation: () throws -> Void
) {
    do {
        try operation()
        Issue.record("Expected outsideVault for \(path)", sourceLocation: sourceLocation)
    } catch NoteStore.StoreError.outsideVault(let originalPath) {
        #expect(originalPath == path, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Expected outsideVault for \(path), received \(error)", sourceLocation: sourceLocation)
    }
}

/// All adversarial paths, including ../../etc/passwd, land in this unique container
/// if the guard regresses. Sentinel setup never touches a real vault or system file.
private struct BoundaryFixture: ~Copyable {
    let container: URL
    let root: URL

    init() throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-boundary-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath().standardizedFileURL
        let root = container.appending(path: "level/vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.container = container
        self.root = root
    }

    func seed(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    deinit {
        try? FileManager.default.removeItem(at: container)
    }
}
