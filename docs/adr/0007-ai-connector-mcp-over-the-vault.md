# ADR-0007: The AI connector is a local process over the vault, not a feature of the app

- Status: accepted
- Date: 2026-08-15
- Supersedes: nothing. Adds a capability SPEC v2.2 does not describe, and diverges from
  ADR-0001 §D1 on the target count.

## Context

An assistant should be able to search this vault, read a note, capture a task with the
`>date` and `!date` markers of SPEC §7.1, block out a day, and tell whether a note obeys
the harness conventions. Everything needed to do any of that already exists and is
tested - and all of it is locked inside `Pergamenum.app`, where no other process can
reach it.

Two things constrain every answer. The first is principle 2 of SPEC §3: no network call
in any feature, no server, no account, no telemetry. The second is principle 1: the files
are the product, and the app is one reader of them among others.

The second principle also decides most of the design. A vault is markdown on disk. An
assistant that works on the files needs the app only for the things that are not files -
which, after looking, turn out to be very few. Time blocks are lines under a `## Timeline`
heading in the daily note (`VaultController+TimeBlocks`). Tasks are markdown lines that
get rewritten in place. The diary, the canvas and the daily notes are files. What is *not*
a file is Apple Calendar, Apple Reminders, the thumbnail cache, and where the cursor
happens to be.

## Decision

**D1. The connector is a separate local process, and the model lives outside it.**
An MCP server speaking stdio, started by Claude Code or Claude Desktop, plus a CLI for
everything a shell can drive. Neither opens a socket. The client owns the connection to
the model, chooses what to send, and is where the user grants or refuses it.

Principle 2 is therefore untouched, and the distinction matters more than it may look:
"Pergamenum makes no network call" stays literally true, verifiable by reading the code
and by watching the process. An AI pane inside the app would have made it false, and
would have needed this ADR to amend §3 rather than to leave it standing. That option was
considered and rejected on those grounds.

**D2. One set of source files, three binaries.** `perg` and `pergamenum-mcp` are Tuist
`.commandLineTool` targets whose `sources:` name the same files on disk as the app -
`Sources/Core/**` plus the pure files under `Sources/Vault` and `Sources/Index`. Not a
framework, not an SPM module.

This diverges from ADR-0001 §D1, which says layering is expressed as folders and not as
targets. The reason that rule existed is still respected: there is no module boundary,
nothing became `public`, and the dependency direction is unchanged. What changes is only
how many binaries compile the same folders. The alternative - a shared module - would
have meant an access-level pass over roughly two hundred types for no behavioural gain.

The arrangement has a property worth keeping deliberately: `Sources/Core` is supposed to
depend on nothing but the standard library, and now a stray `import SwiftUI` there breaks
the CLI build. The rule enforces itself instead of being remembered.

Compiling the same files is not by itself enough to keep two connectors saying the same
thing, and the implementation found where: the JSON `perg --json` produced was defined
inside the CLI, out of the server's reach, so each would have grown its own idea of what
a note looks like. `Sources/Connector/` holds the answer shapes and the operations over
them - the reads, the writes with their guardrails, and the lookups that turn a string
into a date, a view or a task. Both binaries encode the same payloads through the same
encoder; what is left in `Sources/CLI` and `Sources/MCPServer` is how each is spoken to.

**D3. The orchestration moves out of `VaultController`.** Creating a note, capturing a
task, rewriting a task line, writing a day's blocks and running the linter live in
extensions on a `@MainActor @Observable` type that imports SwiftUI, so no headless process
can call them. They move to a `VaultSession` that depends on Foundation alone, and
`VaultController` becomes the observable facade over it.

Re-implementing them in the CLI was the cheaper option and is refused: the conventions of
principle 5 are exactly the thing that must have one implementation. Two copies of the
naming rule would disagree eventually, and the conformance linter exists because that kind
of disagreement is expensive to find.

**D4. EventKit is not linked into the connector.** TCC attributes a command-line tool's
calendar access to the process that launched it - the terminal, or Claude Code - not to
Pergamenum, so a CLI reading the calendar would prompt for a grant against the wrong
identity and hold it there. Apple Calendar and Reminders stay app-only.

Nothing important is lost. What a person means by "block out my afternoon" is a time
block, and a time block is a line in the daily note.

**D5. Acting on the running app goes through `pergamenum://`.** The routes of SPEC §9
already open a note, jump to a day, run a search and capture text, and they launch the app
when it is closed. `perg app open` shells out to them. No new IPC channel is introduced,
and none is needed until something wants to *read* live app state - at which point it gets
its own ADR, and `Product.xpc` is where it would start.

**D6. Writing is off by default, reversible, and never silent.** Three rules, each for a
failure that would otherwise be unrecoverable:

- The MCP server registers write tools only when started with `--allow-write`. A
  connection made to look at something cannot change it.
- Every mutating command takes `--dry-run` and prints a unified diff; every write tool
  takes a `dryRun` argument that **defaults to true**, so a model that omits it gets a
  diff back rather than a modified vault. `lint --fix` refuses to act without `--apply`.
- Every write is journalled to `.pergamenum/ai-journal/` with the path, the hash before,
  the hash after and the previous text. `perg journal undo <id>` restores, and refuses
  when the file's current hash is not the one it wrote - undoing onto somebody's later
  edit is worse than declining to undo at all.

**Amendment (ADR-0016).** This ADR originally excluded `note rename|move|trash` from
both connectors, because they rewrote links across many notes through `NoteFileOperations`
directly, outside `VaultSession.write`, and the journal above had no way to describe a
move or a removal. ADR-0016 gives the journal that vocabulary and routes all three
through it as one journalled gesture, so the exclusion no longer holds and both
connectors carry the three verbs.

The journal lives under `.pergamenum/` with the rest of the disposable state. Losing it
loses nothing that the vault does not still hold.

## Consequences

- `VaultController` stops being where behaviour lives and becomes where observable state
  lives. Every extension on it shrinks. This is a refactor of working code, and the test
  suite is the only thing that makes it safe: the count must not move.
- The repository takes its first SPM dependency, `modelcontextprotocol/swift-sdk`, for the
  MCP target only. It is 0.12.1 (7 May 2026) and implements spec revision 2025-11-25 while
  the current revision is 2026-07-28. The spec keeps `server/discover` usable as a
  backwards-compatibility probe on stdio, so this works with current clients; it is a 0.x
  that lags, and the CLI is deliberately independent of it so that a client which stops
  probing costs the MCP layer and nothing else.
- The MCP protocol layer cannot be reached from `PergamenumTests`: its sources compile
  into a tool that links the SDK, and pulling them into the test bundle would mean linking
  that SDK into the app to satisfy an `import`. Everything underneath is covered by the
  suite, and the protocol itself by `scripts/mcp-smoke.py`, which drives a real server
  over stdio against a vault it makes and throws away. Not as good as a unit test, and
  said out loud rather than left as an apparent gap in coverage.
- An assistant writing to a note the editor has open with unsaved changes raises the
  external-change prompt of ADR-0001 §D3.4. That is the correct behaviour and it will
  happen more often than it does today.
- The vault is reachable by a second writer. The watcher already tells the app's own
  writes from external ones by content hash rather than by timing, so this needs no new
  mechanism - but the vault is no longer edited by one program at a time, and every
  assumption that rested on that is now worth doubting rather than trusting.
