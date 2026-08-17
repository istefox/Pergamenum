#!/usr/bin/env python3
"""
Drives pergamenum-mcp over stdio and checks what comes back.

The protocol layer cannot be reached from the app's test bundle: its sources compile into
a command-line tool that links the MCP SDK, and pulling them into PergamenumTests would
mean linking that SDK into the app. So the tools, the write gate and the guardrails are
verified here, against a vault this script makes and throws away.

    scripts/mcp-smoke.py [percorso del binario]

Without an argument it looks for a Debug build in DerivedData. Exits 0 when everything
holds, 1 on the first thing that does not, naming it.
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading

NOTE = """---
date: 2026-08-11
tags:
  - type-note
---

Corpo.

- [ ] Alfa >2026-08-20
"""

failures = []


def check(condition, description):
    print(("  ok   " if condition else "  FALLITO  ") + description)
    if not condition:
        failures.append(description)


def find_binary():
    if len(sys.argv) > 1:
        return sys.argv[1]
    pattern = os.path.expanduser(
        "~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Debug/pergamenum-mcp")
    found = sorted(glob.glob(pattern), key=os.path.getmtime)
    if not found:
        sys.exit("nessun binario: compila lo schema pergamenum-mcp, o passami un percorso")
    return found[-1]


class Server:
    """One server process, spoken to one request at a time."""

    def __init__(self, binary, vault, allow_write):
        arguments = [binary, "--vault", vault] + (["--allow-write"] if allow_write else [])
        self.process = subprocess.Popen(
            arguments, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True)
        self.identifier = 0
        # Drained rather than ignored: a full stderr pipe would block the server.
        threading.Thread(target=lambda: [None for _ in self.process.stderr], daemon=True).start()
        self.send("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                                 "clientInfo": {"name": "mcp-smoke", "version": "0"}})
        self.notify("notifications/initialized")

    def send(self, method, params):
        self.identifier += 1
        self.process.stdin.write(json.dumps(
            {"jsonrpc": "2.0", "id": self.identifier, "method": method, "params": params}) + "\n")
        self.process.stdin.flush()
        line = self.process.stdout.readline()
        if not line:
            sys.exit("il server non ha risposto a %s: è morto?" % method)
        return json.loads(line)

    def notify(self, method):
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method}) + "\n")
        self.process.stdin.flush()

    def call(self, name, arguments=None):
        return self.send("tools/call", {"name": name, "arguments": arguments or {}})["result"]

    def payload(self, name, arguments=None):
        """A tool's JSON answer, decoded. Fails loudly when the tool refused."""
        result = self.call(name, arguments)
        if result.get("isError"):
            return {"isError": True, "text": result["content"][0]["text"]}
        return json.loads(result["content"][0]["text"])

    def close(self):
        self.process.stdin.close()
        self.process.terminate()


def read_only(binary, vault):
    print("sola lettura")
    server = Server(binary, vault, allow_write=False)
    try:
        tools = server.send("tools/list", {})["result"]["tools"]
        names = [tool["name"] for tool in tools]
        check("read_note" in names, "gli strumenti di lettura ci sono")
        check(not any(name.startswith(("create_", "add_", "append_", "complete_", "undo_"))
                      for name in names),
              "gli strumenti che scrivono non sono nemmeno elencati")
        check(all(tool.get("annotations", {}).get("readOnlyHint") for tool in tools),
              "ogni strumento pubblicato si dichiara di sola lettura")

        refusal = server.payload("add_task", {"text": "Non deve passare", "dryRun": False})
        check(refusal.get("isError") is True, "chiamare uno strumento di scrittura è rifiutato")
        check("--allow-write" in refusal.get("text", ""), "il rifiuto dice come si abilita")

        stats = server.payload("vault_stats")
        check(stats["notes"] == 1, "vault_stats conta la nota del vault di prova")

        unknown = server.call("strumento_inventato")
        check(unknown.get("isError") is True, "uno strumento inesistente è un errore parlante")
    finally:
        server.close()


def writing(binary, vault):
    print("scrittura abilitata")
    server = Server(binary, vault, allow_write=True)
    path = os.path.join(vault, "Nota.md")
    try:
        names = [tool["name"] for tool in server.send("tools/list", {})["result"]["tools"]]
        check("add_task" in names and "undo_write" in names, "gli strumenti che scrivono ci sono")

        # No dryRun at all: the default has to be the safe one.
        rehearsal = server.payload("add_task", {"text": "Beta", "note": "Nota.md"})
        check(rehearsal["applied"] is False, "senza dryRun non si applica niente")
        check("+- [ ] Beta" in (rehearsal.get("diff") or ""), "la prova torna il diff")
        with open(path, encoding="utf-8") as handle:
            check("Beta" not in handle.read(), "il file non è stato toccato dalla prova")

        applied = server.payload(
            "add_task", {"text": "Beta", "note": "Nota.md", "dryRun": False})
        check(applied["applied"] is True, "con dryRun false si scrive")
        with open(path, encoding="utf-8") as handle:
            check("- [ ] Beta" in handle.read(), "il task è sul file")

        log = server.payload("journal_log")
        check(len(log) == 1 and log[0]["command"] == "add_task", "la scrittura è nel journal")

        undone = server.payload("undo_write", {"id": log[0]["id"], "dryRun": False})
        check(undone["applied"] is True, "undo_write applica")
        with open(path, encoding="utf-8") as handle:
            check("Beta" not in handle.read(), "il file è tornato com'era")

        # A block on an hour that is already taken has to move rather than overlap.
        server.payload("add_time_block",
                       {"title": "Primo", "at": "09:00", "minutes": 60,
                        "day": "2026-08-20", "dryRun": False})
        moved = server.payload("add_time_block",
                               {"title": "Secondo", "at": "09:00", "minutes": 30,
                                "day": "2026-08-20", "dryRun": False})
        check(moved.get("note") is not None, "un blocco su un'ora occupata scala e lo dice")

        refusal = server.payload("create_note", {"title": "questo/non va", "dryRun": False})
        check(refusal.get("isError") is True, "un titolo non conforme è rifiutato")
        check("Pergamenum." not in refusal.get("text", ""),
              "il rifiuto è una frase, non un dump del modulo")

        # Capture (ADR-0008). The unit suite covers what it writes; what only a real
        # server can show is that the tool is declared, that its dryRun defaults the
        # safe way like every other write, and that a bad destination comes back as a
        # sentence rather than as a crash on the other side of stdio.
        check("capture" in names, "capture è fra gli strumenti che scrivono")

        rehearsal = server.payload("capture", {"text": "Appunto", "destination": "today"})
        check(rehearsal["applied"] is False, "capture senza dryRun non applica")

        captured = server.payload(
            "capture", {"text": "Appunto", "destination": "today", "dryRun": False})
        day_note = os.path.join(vault, captured["path"])
        with open(day_note, encoding="utf-8") as handle:
            check("Appunto" in handle.read(), "la cattura è sulla nota del giorno")

        refusal = server.payload(
            "capture", {"text": "x", "destination": "lunatica", "dryRun": False})
        check(refusal.get("isError") is True, "una destinazione inventata è rifiutata")

        # A date belongs to a task and to nothing else: dropping it silently would
        # leave the model believing the deadline is there.
        refusal = server.payload(
            "capture", {"text": "x", "destination": "today", "due": "2026-08-25",
                        "dryRun": False})
        check(refusal.get("isError") is True, "una data fuori da un task è rifiutata")
    finally:
        server.close()


def resources(binary, vault):
    print("risorse")
    server = Server(binary, vault, allow_write=False)
    try:
        listing = server.send("resources/list", {})["result"]
        uris = [resource["uri"] for resource in listing["resources"]]
        check(any(uri.startswith("pergamenum://note?file=") for uri in uris),
              "le note sono esposte come link pergamenum://")

        contents = server.send("resources/read", {"uri": uris[0]})["result"]["contents"]
        check(contents[0]["mimeType"] == "text/markdown", "una nota si legge come markdown")
        check(contents[0]["text"].startswith("---"), "torna il file com'è, frontmatter compreso")

        broken = server.send("resources/read", {"uri": "pergamenum://canvas?file=X.canvas"})
        check("error" in broken, "una risorsa che non è una nota è rifiutata")
    finally:
        server.close()


binary = find_binary()
print("binario: %s\n" % binary)

for stage in (read_only, writing, resources):
    vault = tempfile.mkdtemp(prefix="pergamenum-smoke-")
    try:
        with open(os.path.join(vault, "Nota.md"), "w", encoding="utf-8") as handle:
            handle.write(NOTE)
        stage(binary, vault)
    finally:
        shutil.rmtree(vault, ignore_errors=True)
    print()

if failures:
    print("%d controlli falliti:" % len(failures))
    for failure in failures:
        print("  - " + failure)
    sys.exit(1)
print("tutto a posto")
