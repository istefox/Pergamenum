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

VIEW_NOTE = """---
date: 2026-08-20
tags:
  - type-note
---

```pergamenum-view
where: tag("type-note")
render: table
columns: [title, tags]
```

```pergamenum-view
sort: created desc
render: table
```
"""

# One pratica as a sync would have left it, minus the sync: the `pergamenum-dossier`
# keys are what make the folder a pratica at all (ADR-0036 R-01), and the `##` heading
# is a manual entry, the one kind of timeline row that exists without a message file.
PRATICA_NOTE = """---
date: 2026-09-01
tags:
  - type-note
  - topic-pratica
  - client-rossi
  - status-active
  - source-email
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
pergamenum-dossier-conversations: [112409]
---

Appunti pratica.

## 2026-06-10 14:06 Telefonata · Mario Rossi

Richiamare lunedì.
"""

# One message with no linked note yet, the fixture `pratiche_links` collects and
# unlinks (ADR-0049 §D6).
MESSAGE_NOTE = """---
date: 2026-06-10
tags:
  - type-note
  - type-email
pergamenum-mail: 1
pergamenum-mail-message-id: "<abc@rossi-spa.it>"
pergamenum-mail-direction: received
pergamenum-mail-date: 2026-06-10T14:06:00+02:00
pergamenum-mail-from: "Mario Rossi <m.rossi@rossi-spa.it>"
pergamenum-mail-subject: "Richiesta offerta"
pergamenum-mail-body: complete
---

Buongiorno,
"""

# One registered category ("collaudi") and one task tagged with a slug the registry
# does not know ("fantasma") - the R-04 implicit-category case, read here through the
# connector rather than the sidebar.
CATEGORY_NOTE = """---
date: 2026-08-11
tags:
  - type-note
---

- [ ] Preventivo #project-collaudi
- [ ] Non registrato #project-fantasma
"""

def make_check(failures):
    """A `check` that records into `failures`, so the list belongs to one run and not to the module."""

    def check(condition, description):
        print(("  ok   " if condition else "  FALLITO  ") + description)
        if not condition:
            failures.append(description)

    return check


def find_binary(argv):
    if len(argv) > 1:
        return argv[1]
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


def read_only(binary, vault, check):
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


def writing(binary, vault, check):
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


def views(binary, vault, check):
    """ADR-0009 D4: a view answers a model with the rows the window draws."""
    print("viste")
    server = Server(binary, vault, allow_write=False)
    view_note = os.path.join(vault, "Viste.md")
    try:
        with open(view_note, "w", encoding="utf-8") as handle:
            handle.write(VIEW_NOTE)

        listed = server.payload("list_views")
        check(len(listed) == 2, "list_views trova i due blocchi della nota")
        check(listed[0]["render"] == "table", "il primo si disegna come tabella")
        # A block that does not parse is listed with its reason, never dropped: a listing
        # that hid it would be the empty result D1 refuses, told through another channel.
        check(listed[1]["error"] is not None, "il blocco rotto è elencato con il motivo")
        check("riga" in listed[1]["error"], "il motivo nomina la riga")

        run = server.payload("run_view", {"path": "Viste.md", "ordinal": 0})
        # Two, not one: a view is a note, so a view filtering on `type-note` and carrying it
        # appears in its own results. ADR-0009 predicted this would look like a bug.
        check(run["total"] == 2, "run_view conta le note che rispondono, la vista compresa")
        rows = run["groups"][0]["rows"]
        check(rows[0]["title"] == "Nota", "e la nomina")
        check(rows[0]["values"]["tags"] == "type-note", "le celle sono quelle che l'app disegna")

        broken = server.payload("run_view", {"path": "Viste.md", "ordinal": 1})
        check(broken.get("isError") is True, "eseguire il blocco rotto è un errore")

        ambiguous = server.payload("run_view", {"path": "Viste.md"})
        check(ambiguous.get("isError") is True, "senza ordinal su due viste non indovina")
    finally:
        server.close()


def pratiche(binary, vault, check):
    """ADR-0036 R-36: the two pratiche tools answer from what a sync left on disk.

    Nothing here goes near Mail: the fixture is a folder this script writes, and a
    connector that tried to open the store would be refusing to compile long before it
    got here (`SharedSourcesPurityTests`). What only a real server can show is that both
    tools are declared read-only, that the payload keys survive the JSON crossing, and
    that an unknown pratica comes back as a sentence rather than as a dead pipe.
    """
    print("pratiche")
    folder = os.path.join(vault, "01 Progetti", "Rossi", "Offerta")
    os.makedirs(folder)
    with open(os.path.join(folder, "pratica.md"), "w", encoding="utf-8") as handle:
        handle.write(PRATICA_NOTE)

    server = Server(binary, vault, allow_write=False)
    try:
        tools = server.send("tools/list", {})["result"]["tools"]
        declared = {tool["name"]: tool for tool in tools}
        check("pratiche" in declared and "pratica" in declared,
              "i due strumenti delle pratiche sono elencati")

        listed = server.payload("pratiche")
        check(len(listed) == 1, "pratiche trova la pratica del vault di prova")
        check(listed[0]["path"] == "01 Progetti/Rossi/Offerta", "e la nomina col suo percorso")
        # The client is the folder above the pratica, never a field somebody typed.
        check(listed[0]["client"] == "Rossi", "il cliente è la cartella che la contiene")
        check(listed[0]["status"] == "active", "lo stato viene dal tag status-*")
        check(listed[0]["counterparts"] == ["m.rossi@rossi-spa.it"], "la controparte è quella del dossier")
        # Zero, and said out loud: no sync has ever run against this vault.
        check(listed[0]["messageCount"] == 0, "senza sincronizzazione non c'è nessun messaggio")

        timeline = server.payload("pratica", {"pratica": "Offerta"})
        check(timeline["path"] == "01 Progetti/Rossi/Offerta", "pratica risolve il titolo alla cartella")
        check(len(timeline["entries"]) == 1, "la timeline ha la sola voce scritta a mano")
        check(timeline["entries"][0]["kind"] == "call", "e la riconosce come telefonata")
        check("Richiamare" in timeline["entries"][0]["body"], "col testo che il file porta")

        missing = server.payload("pratica", {"pratica": "Non esiste"})
        check(missing.get("isError") is True, "una pratica che non c'è è un errore parlante")
    finally:
        server.close()


def pratiche_links(binary, vault, check):
    """ADR-0049 §D12, R-10: the pratica/message link tools are reachable from MCP
    too, absent without --allow-write, and a write with dryRun true changes nothing.

    Everything else about the shape of a link - resolution states, the message's
    replace-not-append rule, create-then-link ordering - is `Tests/
    PraticheLinksConnectorTests.swift`'s job; what only a real server can show is
    that these specific tool names are declared, listed correctly, and callable.
    """
    print("collegamenti pratiche")
    folder = os.path.join(vault, "01 Progetti", "Rossi", "Offerta")
    os.makedirs(os.path.join(folder, "email"))
    pratica_path = os.path.join(folder, "pratica.md")
    with open(pratica_path, "w", encoding="utf-8") as handle:
        handle.write(PRATICA_NOTE)
    message_path = os.path.join(folder, "email", "msg.md")
    with open(message_path, "w", encoding="utf-8") as handle:
        handle.write(MESSAGE_NOTE)

    read_server = Server(binary, vault, allow_write=False)
    try:
        names = [tool["name"] for tool in read_server.send("tools/list", {})["result"]["tools"]]
        check("pratica_links" in names, "lo strumento di lettura dei collegamenti è elencato")
        check(not any(name.startswith(("pratica_link_", "pratica_unlink_", "pratica_create_",
                                        "message_link_", "message_unlink_", "message_create_"))
                      for name in names),
              "gli strumenti che scrivono i collegamenti non sono elencati senza --allow-write")

        links = read_server.payload("pratica_links", {"pratica": "Offerta"})
        check(links["notes"] == [] and links["tasks"] == [] and links["boards"] == [],
              "una pratica senza collegamenti torna tre elenchi vuoti")
    finally:
        read_server.close()

    server = Server(binary, vault, allow_write=True)
    try:
        names = [tool["name"] for tool in server.send("tools/list", {})["result"]["tools"]]
        check("pratica_link_note" in names and "message_link_note" in names,
              "gli strumenti che scrivono i collegamenti ci sono con --allow-write")

        rehearsal = server.payload("pratica_link_note", {"pratica": "Offerta", "title": "Preventivo 2026"})
        check(rehearsal["applied"] is False, "senza dryRun non si applica niente")
        check("pergamenum-dossier-links-notes" in (rehearsal.get("diff") or ""),
              "la prova mostra la nuova chiave nel diff")
        with open(pratica_path, encoding="utf-8") as handle:
            check("Preventivo 2026" not in handle.read(), "il file non è stato toccato dalla prova")

        applied = server.payload(
            "pratica_link_note", {"pratica": "Offerta", "title": "Preventivo 2026", "dryRun": False})
        check(applied["applied"] is True, "con dryRun false si scrive")

        links = server.payload("pratica_links", {"pratica": "Offerta"})
        check(any(note["reference"] == "[[Preventivo 2026]]" for note in links["notes"]),
              "il collegamento è sulla pratica")
        check(links["notes"][0]["state"] == "missing", "la nota collegata non esiste ancora: non risolve")

        message = os.path.relpath(message_path, vault)
        linked = server.payload(
            "message_link_note", {"message": message, "title": "Contratto 2026", "dryRun": False})
        check(linked["applied"] is True, "il messaggio si collega a una nota")
        with open(message_path, encoding="utf-8") as handle:
            check("pergamenum-mail-note" in handle.read(), "la chiave è sul file del messaggio")
    finally:
        server.close()


def categories(binary, vault, check):
    """ADR-0047 §D9 (R-09): the registry read, implicit categories folded in, and one
    category's rolled-up, grouped task list - both read-only, neither writes.
    """
    print("categorie")
    pergamenum_dir = os.path.join(vault, ".pergamenum")
    os.makedirs(pergamenum_dir, exist_ok=True)
    with open(os.path.join(pergamenum_dir, "categories.json"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps({
            "version": 1,
            "entries": [{"slug": "collaudi", "name": "Collaudi", "color": "verde",
                         "order": 0, "archived": False}],
        }))
    with open(os.path.join(vault, "Progetto.md"), "w", encoding="utf-8") as handle:
        handle.write(CATEGORY_NOTE)

    server = Server(binary, vault, allow_write=False)
    try:
        tools = server.send("tools/list", {})["result"]["tools"]
        names = [tool["name"] for tool in tools]
        check("list_categories" in names and "category_tasks" in names,
              "i due strumenti delle categorie sono elencati")

        listed = server.payload("list_categories")
        by_slug = {entry["slug"]: entry for entry in listed}
        check("collaudi" in by_slug and by_slug["collaudi"]["implicit"] is False,
              "la categoria registrata torna con implicit false")
        check("fantasma" in by_slug and by_slug["fantasma"]["implicit"] is True,
              "il tag senza voce nel registro torna come categoria implicita")
        check(by_slug["collaudi"]["progress"]["total"] == 1,
              "il progresso conta solo i task di quella categoria")

        tasks = server.payload("category_tasks", {"slug": "collaudi"})
        check(tasks["groups"][0]["tasks"][0]["text"] == "Preventivo",
              "category_tasks torna i task della categoria, raggruppati come la vista")

        refusal = server.payload("category_tasks", {"slug": "non-esiste"})
        check(refusal.get("isError") is True,
              "uno slug né registrato né implicito è un errore parlante")
    finally:
        server.close()


def resources(binary, vault, check):
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


def hardening(binary, vault, check):
    """ADR-0063: malformed numbers and cursors are refused as sentences, never as a dead
    process, and `pratica_create_board` honours dryRun and the journal.

    Last in the stage list on purpose: before the fix several of these calls killed the
    server, and `send()`'s own `sys.exit` is the crash assertion - placed last, it stops
    the run only once every other stage has reported.
    """
    print("input malformati")
    folder = os.path.join(vault, "01 Progetti", "Rossi", "Offerta")
    os.makedirs(folder)
    with open(os.path.join(folder, "pratica.md"), "w", encoding="utf-8") as handle:
        handle.write(PRATICA_NOTE)

    server = Server(binary, vault, allow_write=True)
    try:
        # The sentence the shared layer says for a bad limit, read off the first refusal
        # so every later one is compared with the same words.
        refused = server.payload("journal_log", {"limit": -1})
        check(refused.get("isError") is True, "journal_log con limit -1 è rifiutato, il server vive")
        sentence = refused.get("text", "")
        check("limit" in sentence and "-1" in sentence, "il rifiuto nomina limit e il valore")

        refused = server.payload("search_vault", {"query": "Corpo", "limit": -1})
        check(refused.get("isError") is True and refused.get("text") == sentence,
              "search_vault con limit -1 dice la stessa frase")

        for tool, extra in (("search_vault", {"query": "Corpo"}), ("journal_log", {})):
            for raw in ("abc", ""):
                refused = server.payload(tool, dict(extra, limit=raw))
                check(refused.get("isError") is True
                      and refused.get("text") == sentence.replace("-1", raw),
                      "%s con limit %r è la stessa frase" % (tool, raw))

        refused = server.payload("search_vault", {"query": "Corpo", "limit": 1e300})
        check(refused.get("isError") is True, "un limit fuori dall'intervallo di Int è rifiutato")
        check(server.payload("vault_stats").get("notes") is not None, "e la richiesta dopo risponde")

        server.call("run_view", {"path": "Nota.md", "ordinal": 1e300})
        check(server.payload("vault_stats").get("notes") is not None,
              "un ordinal enorme non fa morire il server")

        check(server.payload("search_vault", {"query": "Corpo", "limit": 0}) == [],
              "search_vault con limit 0 risponde vuoto")
        check(server.payload("journal_log", {"limit": 0}) == [], "journal_log con limit 0 risponde vuoto")

        for cursor in ("-1", "abc"):
            answer = server.send("resources/list", {"cursor": cursor})
            check(answer.get("error", {}).get("code") == -32602,
                  "un cursore %r è -32602" % cursor)
            check("result" in server.send("resources/list", {}), "e l'elenco dopo risponde")

        for cursor in ("100000", "9223372036854775807"):
            answer = server.send("resources/list", {"cursor": cursor}).get("result", {})
            check(answer.get("resources") == [] and "nextCursor" not in answer,
                  "un cursore %s oltre la fine è una pagina vuota senza seguito" % cursor)

        canvas = os.path.join(vault, "Preventivo.canvas")
        rehearsal = server.payload("pratica_create_board", {"pratica": "Offerta", "name": "Preventivo"})
        check(rehearsal.get("applied") is False, "pratica_create_board senza dryRun non applica")
        check("Preventivo.canvas" in (rehearsal.get("note") or ""), "la prova nomina la board che creerebbe")
        check(not os.path.exists(canvas), "la prova non crea nessun .canvas")

        applied = server.payload(
            "pratica_create_board", {"pratica": "Offerta", "name": "Preventivo", "dryRun": False})
        check(applied.get("applied") is True, "con dryRun false la board si crea")
        check(os.path.exists(canvas), "il .canvas è sul disco")
        log = server.payload("journal_log")
        check(any(row["path"] == "Preventivo.canvas" and row["created"] is True
                  and row["command"] == "pratica_create_board" for row in log),
              "la creazione della board è nel journal")
    finally:
        server.close()


def main(argv):
    binary = find_binary(argv)
    print("binario: %s\n" % binary)

    failures = []
    check = make_check(failures)
    for stage in (read_only, writing, views, pratiche, pratiche_links, categories, resources,
                  hardening):
        vault = tempfile.mkdtemp(prefix="pergamenum-smoke-")
        try:
            with open(os.path.join(vault, "Nota.md"), "w", encoding="utf-8") as handle:
                handle.write(NOTE)
            stage(binary, vault, check)
        finally:
            shutil.rmtree(vault, ignore_errors=True)
        print()

    if failures:
        print("%d controlli falliti:" % len(failures))
        for failure in failures:
            print("  - " + failure)
        return 1
    print("tutto a posto")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
