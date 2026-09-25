#!/usr/bin/env python3
"""Trova un merge che ha scartato in silenzio il contenuto di un genitore.

ADR-0061, causa radice di PG-240 (issue #522). Il 2026-09-25 il branch
`chore/todo-sync-509`, tagliato da `main` prima che PR #515 fosse mersa, ha
unito `main` in un commit (14d8851) il cui messaggio parlava di risolvere un
conflitto in TODO.md — e il cui diff contro il primo genitore mostrava solo
TODO.md. Ma l'albero risultante teneva la versione stantia del branch per
altri 15 file che PR #515 aveva già cambiato: nessun conflitto reale li
riguardava, eppure sono stati scartati come se un intero lato fosse stato
scelto in blocco (`git checkout --ours .` o `-X ours`, non una risoluzione
file per file). PR #519 ha poi merso quel branch in `main` senza che git
avesse nulla da segnalare, perché `main` non aveva più toccato quei file da
#515: la perdita è sembrata un bug dell'algoritmo di merge, ma non lo era.

La regola qui: per un merge a due genitori, `git merge-tree --write-tree`
(merge reale, non triviale) dice cosa git stesso avrebbe prodotto. Un path
dove il commit effettivo differisce da quel calcolo, e che git non elenca fra
i conflitti, è un path preso in blocco da un lato senza che nessuno lo
decidesse davvero. Fra questi, un path il cui blob committato è identico
byte per byte a quello di un genitore è uno "side-pick": l'incidente PG-240
ne aveva 13, tutti byte-identici al branch stantio. Un path con contenuto
nuovo rispetto a entrambi i genitori è un "evil merge" legittimo — qualcuno
ha corretto a mano una rottura semantica mentre risolveva — e viene solo
segnalato, mai bloccato: misurato sui 433 merge a due genitori della storia
di questo repository, la sola sottrazione dei conflitti segnalava 6 merge,
la classificazione per blob la riduce a 2, entrambi reali (14d8851 e un
secondo caso dell'11 settembre, tracciato separatamente).

Via d'uscita: un trailer sul messaggio del merge commit locale,
`Merge-override: <path>` (ripetibile) più un `Merge-override-reason:`
obbligatorio. Funziona perché ogni commit che questo controllo ispeziona è
stato scritto in locale — il messaggio auto-generato di GitHub esiste solo
sul merge commit della PR, che l'intervallo base..head esclude sempre.
`Merge-override: all` senza elencare i path è rifiutato: nominare cosa si
sta scartando è ciò che rende l'eccezione rivedibile.

ADR-0062 (PG-242, issue #535) chiude il buco che ADR-0061 §D5 aveva nominato:
uno squash o un rebase non lascia alcun merge commit da ispezionare. Il
controllo di landing (`--landing BASE HEAD`) non guarda la forma della storia
ma il contenuto che atterrerebbe: un path che torna a un blob che la storia
first-parent di BASE ha già tenuto e poi superato è un restore, e fallisce.
Le cancellazioni sono solo contesto. Via d'uscita: `Restore-override: <path>`
più `Restore-override-reason:` su un commit qualunque del range BASE..HEAD,
chiave separata da Merge-override. `--landings RANGE` valuta ogni commit
first-parent del range come landing a sé: è la misura di ADR-0062 resa un
comando.

Uso:
    scripts/check-merge-integrity.py [--range A..B] [--verbose]
    scripts/check-merge-integrity.py --pr-base <sha> --pr-head <sha>
    scripts/check-merge-integrity.py --landing <base> <head>
    scripts/check-merge-integrity.py --landings A..B [--verbose]
    scripts/check-merge-integrity.py --self-test

Uscita: 0 pulito, 1 side-pick o restore trovato, 2 non verificabile o uso scorretto.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from typing import Optional

OVERRIDE_PREFIX = "Merge-override:"
OVERRIDE_REASON_PREFIX = "Merge-override-reason:"
# Chiave separata di proposito (ADR-0062 §D6): un Merge-override scritto per
# scusare un merge non deve scusare in silenzio il restore netto di una PR futura.
RESTORE_OVERRIDE_PREFIX = "Restore-override:"
RESTORE_OVERRIDE_REASON_PREFIX = "Restore-override-reason:"
GITLINK_MODE = "160000"


# --- git plumbing --------------------------------------------------------------------


def _git(repo, *args, check=True):
    return subprocess.run(
        ["git", "-C", repo, *args],
        capture_output=True,
        text=True,
        check=check,
    )


def parents(repo, sha):
    out = _git(repo, "log", "-1", "--format=%P", sha).stdout.strip()
    return out.split() if out else []


def subject(repo, sha):
    return _git(repo, "log", "-1", "--format=%s", sha).stdout.strip()


def commit_message(repo, sha):
    return _git(repo, "log", "-1", "--format=%B", sha).stdout


def blob_oid(repo, commit, path):
    """Restituisce l'oid del blob a quel path in quel commit, o None se assente."""
    r = _git(repo, "rev-parse", "--verify", "--quiet", "%s:%s" % (commit, path), check=False)
    if r.returncode != 0:
        return None
    return r.stdout.strip()


def merge_tree(repo, p1, p2):
    """Merge reale a tre vie fra p1 e p2. Ritorna (tree_oid, conflicted_paths, rc).

    tree_oid è None quando git non è riuscito a produrre nessun albero (rc == 2:
    non verificabile, non un fallimento del merge stesso).
    """
    r = _git(
        repo, "merge-tree", "--write-tree", "--name-only", "--messages", p1, p2, check=False
    )
    lines = r.stdout.splitlines()
    if not lines:
        return None, [], r.returncode
    tree = lines[0].strip()
    conflicted = []
    i = 1
    while i < len(lines) and lines[i].strip() != "":
        conflicted.append(lines[i].strip())
        i += 1
    if r.returncode == 2:
        return None, conflicted, r.returncode
    return tree, conflicted, r.returncode


def diff_name_only(repo, tree_a, tree_b):
    out = _git(repo, "diff", "--name-only", tree_a, "%s^{tree}" % tree_b, check=False).stdout
    return [line.strip() for line in out.splitlines() if line.strip()]


def merges_in_range(repo, range_spec):
    """Ritorna (merges, error). error non-None => il range non si risolve (exit 2).

    PG-244: con check=True un range come origin/main..X senza origin/main finiva
    in un traceback, che l'hook leggeva come un fallimento e bloccava il push.
    """
    r = _git(repo, "rev-list", "--merges", range_spec, check=False)
    if r.returncode != 0:
        return [], (r.stderr.strip().splitlines() or ["rc=%d" % r.returncode])[0]
    return [line.strip() for line in r.stdout.splitlines() if line.strip()], None


# --- override trailer ------------------------------------------------------------


def parse_overrides(repo, sha, prefix=OVERRIDE_PREFIX, reason_prefix=OVERRIDE_REASON_PREFIX):
    """Ritorna (paths, reason, error). error non-None => uso scorretto (exit 2).

    I prefissi sono parametri perché lo stesso parser legge due vocabolari:
    Merge-override (default, check_merge) e Restore-override (check_landing).
    """
    msg = commit_message(repo, sha)
    paths = []
    reasons = []
    bare_all = False
    for raw_line in msg.splitlines():
        line = raw_line.strip()
        if line.startswith(prefix):
            value = line[len(prefix):].strip()
            if value == "all":
                bare_all = True
            elif value:
                paths.append(value)
        elif line.startswith(reason_prefix):
            reason = line[len(reason_prefix):].strip()
            if reason:
                reasons.append(reason)
    key = prefix.rstrip(":")
    if bare_all:
        return [], None, "'%s all' è rifiutato — elenca i path uno per uno" % prefix
    if paths and not reasons:
        return [], None, "%s richiede anche %s con un motivo non vuoto" % (
            key, reason_prefix.rstrip(":"))
    return paths, ("; ".join(reasons) if reasons else None), None


# --- avvisi di contesto (una volta sola, non per merge) --------------------------


def config_warnings(repo):
    warnings = []
    r = _git(repo, "config", "--get-regexp", r"^merge\..*\.driver$", check=False)
    if r.returncode == 0 and r.stdout.strip():
        warnings.append(
            "la configurazione git dichiara merge.*.driver personalizzati: "
            "git merge-tree li ignora sempre, quindi il confronto può divergere "
            "da un merge interattivo su quei path"
        )
    for root, dirs, files in os.walk(repo):
        if ".git" in dirs:
            dirs.remove(".git")
        if ".gitattributes" in files:
            path = os.path.join(root, ".gitattributes")
            try:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    content = handle.read()
            except OSError:
                continue
            if "merge=" in content:
                rel = os.path.relpath(path, repo)
                warnings.append(
                    "%s dichiara un attributo merge=, non onorato da git merge-tree" % rel
                )
    return warnings


def installed_hook_warning(installed_path: str, tracked_path: str) -> Optional[str]:
    """Avvisa quando l'hook pre-push installato non è quello del checkout (ADR-0062 §D5).

    L'hook installato è una copia, non un link: una macchina con l'hook di
    ADR-0061 continua a girare la copia vecchia, che non chiama il controllo di
    landing, finché qualcuno non reinstalla. La copia vecchia però chiama ancora
    questo script, quindi è qui che un gate mancante diventa una riga visibile.

    Args:
        installed_path: <git-common-dir>/hooks/pre-push.
        tracked_path: <toplevel>/scripts/git-hooks/pre-push.

    Returns:
        Il messaggio, o None se uno dei due file manca (in CI nessun hook è
        installato) o se sono identici.
    """
    try:
        with open(installed_path, "rb") as handle:
            installed = handle.read()
        with open(tracked_path, "rb") as handle:
            tracked = handle.read()
    except OSError:
        return None
    if installed == tracked:
        return None
    return (
        "l'hook pre-push installato in %s differisce da %s: il controllo di landing "
        "(ADR-0062) potrebbe non girare a ogni push. Reinstalla con "
        "scripts/install-git-hooks.sh --force" % (installed_path, tracked_path)
    )


def _hook_warning_for_cwd(repo: str) -> Optional[str]:
    """Risolve i due path di installed_hook_warning dal repository corrente."""
    common = _git(repo, "rev-parse", "--git-common-dir", check=False)
    top = _git(repo, "rev-parse", "--show-toplevel", check=False)
    if common.returncode != 0 or top.returncode != 0:
        return None
    common_dir = common.stdout.strip()
    if not os.path.isabs(common_dir):
        common_dir = os.path.join(repo, common_dir)
    return installed_hook_warning(
        os.path.join(common_dir, "hooks", "pre-push"),
        os.path.join(top.stdout.strip(), "scripts", "git-hooks", "pre-push"),
    )


# --- il controllo per un singolo merge --------------------------------------------


class MergeReport:
    def __init__(self, sha):
        self.sha = sha
        self.status = None  # ok | failed | skipped | cannot_verify | usage_error
        self.failing = []
        self.overridden = []
        self.novel = []
        self.note = None


def check_merge(repo, sha, verbose):
    report = MergeReport(sha)
    ps = parents(repo, sha)
    if len(ps) != 2:
        report.status = "skipped"
        report.note = "%d genitori, gli octopus merge non sono supportati" % len(ps)
        return report

    p1, p2 = ps
    tree, conflicted, rc = merge_tree(repo, p1, p2)
    if tree is None:
        report.status = "cannot_verify"
        report.note = "git merge-tree non è riuscito a produrre un albero (rc=%d)" % rc
        return report

    conflicted_set = set(conflicted)
    candidates = diff_name_only(repo, tree, sha)

    side_picks = []
    novel = []
    for path in candidates:
        if path in conflicted_set:
            continue
        computed_oid = blob_oid(repo, tree, path)
        committed_oid = blob_oid(repo, sha, path)
        if computed_oid == committed_oid:
            continue  # solo il mode è cambiato, o è già identico
        p1_oid = blob_oid(repo, p1, path)
        p2_oid = blob_oid(repo, p2, path)
        if committed_oid == p1_oid or committed_oid == p2_oid:
            side_picks.append(path)
        else:
            novel.append(path)

    overrides, reason, error = parse_overrides(repo, sha)
    if error:
        report.status = "usage_error"
        report.note = error
        return report

    overridden = [p for p in side_picks if p in overrides]
    failing = [p for p in side_picks if p not in overrides]

    report.novel = novel
    report.overridden = [(p, reason) for p in overridden]
    report.failing = failing
    report.status = "failed" if failing else "ok"
    return report


def print_report(repo, report, verbose):
    short = report.sha[:10]
    if report.status == "skipped":
        print("SALTATO   %s — %s" % (short, report.note))
        return
    if report.status == "cannot_verify":
        print("NON VERIFICABILE %s — %s" % (short, report.note))
        return
    if report.status == "usage_error":
        print("ERRORE    %s — %s" % (short, report.note))
        return
    if verbose or report.status != "ok" or report.novel or report.overridden:
        print("%s %s %s" % (
            "FALLITO  " if report.status == "failed" else "OK       ",
            short,
            subject(repo, report.sha),
        ))
    if report.novel:
        print("  avviso: %d file con contenuto nuovo rispetto a entrambi i genitori "
              "(evil merge legittimo, non bloccante):" % len(report.novel))
        for p in report.novel:
            print("    %s" % p)
    if report.overridden:
        reason = report.overridden[0][1]
        print("  override applicato (%s):" % reason)
        for p, _ in report.overridden:
            print("    %s" % p)
    if report.failing:
        print("  %d file presi in blocco da un genitore senza un conflitto reale "
              "a giustificarlo:" % len(report.failing))
        for p in report.failing:
            print("    %s" % p)
        print("  se è intenzionale, aggiungi al messaggio del merge commit:")
        print("    Merge-override: <path>")
        print("    Merge-override-reason: <motivo>")


# --- il controllo per un landing (ADR-0062) ----------------------------------------


class LandingReport:
    """Esito di un landing: cosa succederebbe se HEAD atterrasse su BASE adesso.

    Attributes:
        base: sha risolto di BASE (o la revisione data, se non risolvibile).
        head: sha risolto di HEAD (o la revisione data, se non risolvibile).
        status: ok | failed | cannot_verify | usage_error (skipped solo in --landings,
            per un commit senza genitori).
        restores: (path, introduced_sha, replaced_sha) dei path non coperti da
            override che tornano a un blob già tenuto da main.
        context_deletions: (path, added_by_sha) dei file cancellati che un restore
            fallito aveva aggiunto; solo contesto, mai un fallimento.
        overridden: (path, reason) dei restore coperti da Restore-override.
        skipped_conflicts: path in conflitto nel merge calcolato, non valutati.
        note: spiegazione per gli stati diversi da ok/failed.
    """

    def __init__(self, base: str, head: str) -> None:
        self.base = base
        self.head = head
        self.status = None
        self.restores = []
        self.context_deletions = []
        self.overridden = []
        self.skipped_conflicts = []
        self.note = None


def _is_zero_oid(oid: str) -> bool:
    return set(oid) == {"0"}


def _raw_entries(out: str):
    """Scompone l'output `--raw -z` di diff-tree o di log.

    Con -z ogni riga raw è `:<modi> <oid> <oid> <stato>` seguita dal path come
    token separato, quindi un path con spazi o caratteri strani non si rompe
    mai. Nel log ogni commit apre con il marcatore `\\x01<sha>` del --format.

    Yields:
        (commit, old_mode, new_mode, old_oid, new_oid, status, path); commit è
        None per diff-tree.
    """
    tokens = out.split("\0")
    commit = None
    i = 0
    while i < len(tokens):
        token = tokens[i].lstrip("\n")
        i += 1
        if token.startswith("\x01"):
            commit = token[1:].strip()
        elif token.startswith(":") and i < len(tokens):
            fields = token[1:].split(" ")
            path = tokens[i]
            i += 1
            if len(fields) < 5:
                continue
            old_mode, new_mode, old_oid, new_oid, status = fields[:5]
            yield commit, old_mode, new_mode, old_oid, new_oid, status[:1], path


def first_parent_record(repo: str, base: str, paths) -> dict:
    """Legge la storia first-parent di BASE e ricorda, per ogni path richiesto,
    ogni blob che ha tenuto (ADR-0062 §D2 passo 4).

    Un solo `git log` senza pathspec, filtrato qui: niente limite di argv e
    niente problemi di quoting dei pathspec. Il log va dal più nuovo al più
    vecchio, quindi il primo commit visto per un oid è il più recente.

    Returns:
        {path: {"introduced": {oid: sha}, "replaced": {oid: sha}, "added_by": sha|None}}
    """
    wanted = set(paths)
    record = {}
    if not wanted:
        return record
    out = _git(
        repo, "log", "--first-parent", "--diff-merges=first-parent", "--root", "--raw",
        "-z", "--no-abbrev", "--no-renames", "--format=%x01%H", base,
    ).stdout
    for commit, old_mode, new_mode, old_oid, new_oid, status, path in _raw_entries(out):
        if path not in wanted:
            continue
        if GITLINK_MODE in (old_mode, new_mode) or old_oid == new_oid:
            continue  # submodulo o solo il mode: nessun blob nuovo tenuto da main
        h = record.setdefault(path, {"introduced": {}, "replaced": {}, "added_by": None})
        if not _is_zero_oid(new_oid):
            h["introduced"].setdefault(new_oid, commit)
        if not _is_zero_oid(old_oid):
            h["replaced"].setdefault(old_oid, commit)
        if status == "A" and h["added_by"] is None:
            h["added_by"] = commit
    return record


def _resolve_commit(repo: str, rev: str):
    r = _git(repo, "rev-parse", "--verify", "--quiet", "%s^{commit}" % rev, check=False)
    return r.stdout.strip() if r.returncode == 0 else None


def check_landing(repo: str, base: str, head: str) -> LandingReport:
    """Se HEAD atterrasse su BASE adesso, qualche path tornerebbe a una versione
    che la storia first-parent di BASE ha già superato? (ADR-0062 §D2)

    Args:
        repo: percorso del repository.
        base: revisione su cui HEAD atterrerebbe (la punta di main).
        head: revisione che atterra (la PR, lo squash, il commit spinto).

    Returns:
        Un LandingReport; lo stato decide l'uscita (0 ok, 1 failed, 2 il resto).
    """
    report = LandingReport(base, head)

    # 1. Risoluzione.
    base_sha = _resolve_commit(repo, base)
    head_sha = _resolve_commit(repo, head)
    if base_sha is None or head_sha is None:
        report.status = "usage_error"
        report.note = "revisione non risolvibile come commit: %s" % (
            base if base_sha is None else head)
        return report
    report.base, report.head = base_sha, head_sha

    # 2. L'albero che atterrerebbe. Il caso lineare (squash, rebase, ogni landing
    # storico in --landings) non ha bisogno di merge-tree: atterra HEAD così com'è.
    anc = _git(repo, "merge-base", "--is-ancestor", base_sha, head_sha, check=False)
    conflicted = []
    if anc.returncode == 0:
        landing_tree = "%s^{tree}" % head_sha
    elif anc.returncode == 1:
        tree, conflicted, rc = merge_tree(repo, base_sha, head_sha)
        if tree is None:
            report.status = "cannot_verify"
            report.note = "git merge-tree non è riuscito a produrre un albero (rc=%d)" % rc
            return report
        landing_tree = tree
    else:
        report.status = "cannot_verify"
        report.note = "git merge-base --is-ancestor non ha risposto (rc=%d)" % anc.returncode
        return report
    conflicted_set = set(conflicted)
    report.skipped_conflicts = list(conflicted)

    # 3. Il diff del landing: candidati (M/A con un blob nuovo) e cancellazioni.
    out = _git(
        repo, "diff-tree", "-r", "-z", "--raw", "--no-renames",
        "%s^{tree}" % base_sha, landing_tree,
    ).stdout
    candidates = []  # (path, new_oid)
    deletions = []
    for _, old_mode, new_mode, old_oid, new_oid, status, path in _raw_entries(out):
        if path in conflicted_set or GITLINK_MODE in (old_mode, new_mode) or old_oid == new_oid:
            continue
        if status in ("M", "A") and not _is_zero_oid(new_oid):
            candidates.append((path, new_oid))
        elif status == "D":
            deletions.append(path)

    # 4-5. Un candidato il cui blob il path ha già tenuto su main è un restore.
    record = first_parent_record(repo, base_sha, [p for p, _ in candidates] + deletions)
    restores = []
    for path, new_oid in candidates:
        h = record.get(path)
        if h is None:
            continue
        if new_oid in h["introduced"] or new_oid in h["replaced"]:
            restores.append((path, h["introduced"].get(new_oid), h["replaced"].get(new_oid)))

    # 7. Override: su qualunque commit del range proprio del landing (§D6).
    overrides = {}
    shas = _git(repo, "rev-list", "%s..%s" % (base_sha, head_sha)).stdout.split()
    for sha in shas:
        paths, reason, error = parse_overrides(
            repo, sha, RESTORE_OVERRIDE_PREFIX, RESTORE_OVERRIDE_REASON_PREFIX)
        if error:
            report.status = "usage_error"
            report.note = "%s: %s" % (sha[:10], error)
            return report
        for p in paths:
            overrides.setdefault(p, reason)

    report.overridden = [(p, overrides[p]) for p, _, _ in restores if p in overrides]
    report.restores = [r for r in restores if r[0] not in overrides]

    # 6. Le cancellazioni sono solo contesto: mostrate quando un restore fallisce,
    # e solo per un file aggiunto dallo stesso commit che quel restore disfa.
    replacing = {x for _, _, x in report.restores}
    report.context_deletions = [
        (p, record[p]["added_by"])
        for p in deletions
        if p in record and record[p]["added_by"] in replacing
    ]

    # 8.
    report.status = "failed" if report.restores else "ok"
    return report


def check_landings(repo: str, range_spec: str) -> list:
    """Valuta ogni commit first-parent L del range come landing di L su L^1
    (ADR-0062 §D4). Rende la misura dell'ADR un comando riproducibile.

    Passa per check_landing e basta: una sola classificazione, nessuna seconda
    implementazione "veloce" della regola che potrebbe divergere.

    Args:
        repo: percorso del repository.
        range_spec: intervallo git, es. <radice>..origin/main.

    Returns:
        Un LandingReport per commit, dal più vecchio; un commit senza genitori
        ha stato "skipped" e una nota, perché non ha una base su cui atterrare.
    """
    out = _git(repo, "rev-list", "--first-parent", "--reverse", range_spec).stdout
    reports = []
    for sha in out.split():
        ps = parents(repo, sha)
        if not ps:
            r = LandingReport(sha, sha)
            r.status = "skipped"
            r.note = "commit senza genitori: nessuna base su cui valutare il landing"
            reports.append(r)
            continue
        reports.append(check_landing(repo, ps[0], sha))
    return reports


def print_landing_report(repo: str, report: LandingReport, verbose: bool) -> None:
    """Stampa un landing: base e head, i restore raggruppati per commit che
    disfano, il contesto, e su fallimento il blocco di trailer da incollare."""
    head = report.head[:10]
    if report.status == "skipped":
        print("SALTATO   %s — %s" % (head, report.note))
        return
    if report.status == "cannot_verify":
        print("NON VERIFICABILE %s su %s — %s" % (head, report.base[:10], report.note))
        return
    if report.status == "usage_error":
        print("ERRORE    %s su %s — %s" % (head, report.base[:10], report.note))
        return
    if not (verbose or report.status != "ok" or report.overridden):
        return
    print("%s landing %s su %s — %s" % (
        "FALLITO  " if report.status == "failed" else "OK       ",
        head,
        report.base[:10],
        subject(repo, report.head),
    ))
    if report.skipped_conflicts:
        print("  %d path in conflitto nel merge calcolato, non valutati" % len(report.skipped_conflicts))
    if report.overridden:
        print("  Restore-override applicato:")
        for p, reason in report.overridden:
            print("    %s (%s)" % (p, reason))
    if not report.restores:
        return
    groups = {}
    for path, introduced, replaced in report.restores:
        groups.setdefault(replaced, []).append((path, introduced))
    print("  %d file tornano a una versione che main aveva già superato:" % len(report.restores))
    for replaced, items in groups.items():
        label = "%s %s" % (replaced[:10], subject(repo, replaced)) if replaced else "?"
        print("  %d path tornano allo stato prima di %s:" % (len(items), label))
        for path, introduced in items:
            print("    %s (versione tenuta da main da %s)" % (
                path, introduced[:10] if introduced else "?"))
    if report.context_deletions:
        print("  contesto: lo stesso landing cancella %d file aggiunti da quei commit:"
              % len(report.context_deletions))
        for path, added_by in report.context_deletions:
            print("    %s (aggiunto da %s)" % (path, added_by[:10]))
    print("  se è intenzionale, aggiungi a un commit della PR:")
    for path, _, _ in report.restores:
        print("    Restore-override: %s" % path)
    print("    Restore-override-reason: <motivo>")


# --- self-test ---------------------------------------------------------------------


def _sh(repo, *args, check=True):
    return subprocess.run(
        ["git", "-C", repo, *args],
        capture_output=True,
        text=True,
        check=check,
        env={
            **os.environ,
            "GIT_AUTHOR_NAME": "Selftest",
            "GIT_AUTHOR_EMAIL": "selftest@example.invalid",
            "GIT_COMMITTER_NAME": "Selftest",
            "GIT_COMMITTER_EMAIL": "selftest@example.invalid",
        },
    )


def _write(repo, relpath, content):
    full = os.path.join(repo, relpath)
    os.makedirs(os.path.dirname(full) or repo, exist_ok=True)
    with open(full, "w", encoding="utf-8") as handle:
        handle.write(content)


def _init_repo(base_dir, name):
    # mkdtemp, non os.path.join: alcuni scenari costruiscono lo stesso repository
    # di base più di una volta (override, "all" rifiutato), e ogni chiamata vuole
    # una directory propria.
    repo = tempfile.mkdtemp(prefix=name + "-", dir=base_dir)
    _sh(repo, "init", "-q", "-b", "main")
    return repo


def _finish_merge(repo):
    """Chiude un `git merge` avviato con check=False: commit se c'era un
    conflitto da risolvere, altrimenti non fa nulla (il merge è già un commit)."""
    if os.path.exists(os.path.join(repo, ".git", "MERGE_HEAD")):
        _sh(repo, "add", "-A")
        _sh(repo, "commit", "-q", "--no-edit")


def _amend_worktree(repo):
    """Applica le modifiche fatte al working tree dopo il merge, sopra al
    commit di merge appena chiuso (vera o falsa 'risoluzione a mano')."""
    _sh(repo, "add", "-A")
    _sh(repo, "commit", "-q", "--amend", "--no-edit")


def _check(report, ok, description):
    report.append(("ok" if ok else "FALLITO") + ": " + description)
    return ok


def _scenario_clean_merge(base_dir, report):
    """Un merge normale, senza sovrapposizioni: nessuna segnalazione."""
    repo = _init_repo(base_dir, "clean")
    _write(repo, "a.txt", "base\n")
    _sh(repo, "add", "a.txt")
    _sh(repo, "commit", "-q", "-m", "base")
    _sh(repo, "checkout", "-q", "-b", "feature")
    _write(repo, "b.txt", "from feature\n")
    _sh(repo, "add", "b.txt")
    _sh(repo, "commit", "-q", "-m", "feature adds b.txt")
    _sh(repo, "checkout", "-q", "main")
    _write(repo, "c.txt", "from main\n")
    _sh(repo, "add", "c.txt")
    _sh(repo, "commit", "-q", "-m", "main adds c.txt")
    _sh(repo, "merge", "-q", "--no-ff", "-m", "merge feature", "feature")
    merge_sha = _sh(repo, "rev-parse", "HEAD").stdout.strip()

    r = check_merge(repo, merge_sha, verbose=False)
    _check(report, r.status == "ok", "merge pulito passa senza segnalazioni")
    _check(report, not r.failing and not r.novel, "merge pulito non produce path sospetti")
    return repo, merge_sha


def _build_wholesale_ours_repo(base_dir):
    """Riproduce la forma dell'incidente: un conflitto reale (shared.txt) più
    un file aggiunto solo da un lato (newfile.txt) scartato in blocco senza
    che git l'avesse mai segnalato come conflitto."""
    repo = _init_repo(base_dir, "wholesale-ours")
    _write(repo, "shared.txt", "base\n")
    _write(repo, "kept.txt", "invariato\n")
    _sh(repo, "add", ".")
    _sh(repo, "commit", "-q", "-m", "base")

    _sh(repo, "checkout", "-q", "-b", "old")
    _write(repo, "shared.txt", "base\nold change\n")
    _write(repo, "oldfile.txt", "aggiunto solo dal branch stantio\n")
    _sh(repo, "add", ".")
    _sh(repo, "commit", "-q", "-m", "old branch's own change")

    _sh(repo, "checkout", "-q", "main")
    _write(repo, "shared.txt", "base\nmain change\n")
    _write(repo, "newfile.txt", "aggiunto da main, come PR #515\n")
    _sh(repo, "add", ".")
    _sh(repo, "commit", "-q", "-m", "main change (PR #515-shaped)")

    _sh(repo, "checkout", "-q", "old")
    _sh(repo, "merge", "-q", "--no-ff", "-m", "chore(tasks): resolve merge conflict in TODO.md sync", "main", check=False)
    _finish_merge(repo)
    # Risoluzione: shared.txt è un conflitto reale, risolto a mano. newfile.txt
    # non aveva alcun conflitto (git l'aveva già unito da solo) ma viene
    # scartato — la stessa firma di 14d8851.
    _write(repo, "shared.txt", "base\nrisolto a mano\n")
    _sh(repo, "rm", "-q", "-f", "newfile.txt", check=False)
    _amend_worktree(repo)
    merge_sha = _sh(repo, "rev-parse", "HEAD").stdout.strip()
    return repo, merge_sha


def _scenario_wholesale_ours(base_dir, report):
    repo, merge_sha = _build_wholesale_ours_repo(base_dir)
    r = check_merge(repo, merge_sha, verbose=False)
    _check(report, r.status == "failed", "il merge 'ours in blocco' viene rifiutato")
    _check(report, r.failing == ["newfile.txt"],
           "solo newfile.txt è segnalato, non il conflitto reale shared.txt (trovato: %r)" % r.failing)
    return repo, merge_sha


def _scenario_override(base_dir, report):
    """Lo stesso merge di sopra, ma con il trailer di override: deve passare."""
    repo, merge_sha = _build_wholesale_ours_repo(base_dir)
    old_message = commit_message(repo, merge_sha)
    new_message = old_message.rstrip("\n") + (
        "\n\nMerge-override: newfile.txt\n"
        "Merge-override-reason: scartato apposta, superato da oldfile.txt\n"
    )
    _sh(repo, "commit", "-q", "--amend", "-m", new_message)
    amended_sha = _sh(repo, "rev-parse", "HEAD").stdout.strip()

    r = check_merge(repo, amended_sha, verbose=False)
    _check(report, r.status == "ok", "il trailer Merge-override fa passare il path elencato")
    _check(report, r.overridden == [("newfile.txt", "scartato apposta, superato da oldfile.txt")],
           "l'override registra il path e il motivo (trovato: %r)" % r.overridden)
    return repo, amended_sha


def _scenario_bare_all_rejected(base_dir, report):
    repo, merge_sha = _build_wholesale_ours_repo(base_dir)
    old_message = commit_message(repo, merge_sha)
    new_message = old_message.rstrip("\n") + "\n\nMerge-override: all\n"
    _sh(repo, "commit", "-q", "--amend", "-m", new_message)
    amended_sha = _sh(repo, "rev-parse", "HEAD").stdout.strip()

    r = check_merge(repo, amended_sha, verbose=False)
    _check(report, r.status == "usage_error", "'Merge-override: all' senza elenco è rifiutato")


def _scenario_novel_content(base_dir, report):
    """Un evil merge legittimo: un file aggiunto solo da un lato viene
    corretto a mano durante la risoluzione. Deve essere solo un avviso."""
    repo = _init_repo(base_dir, "evil-merge")
    _write(repo, "shared.txt", "base\n")
    _sh(repo, "add", ".")
    _sh(repo, "commit", "-q", "-m", "base")

    _sh(repo, "checkout", "-q", "-b", "old")
    _write(repo, "oldfile.txt", "invariato dal branch\n")
    _sh(repo, "add", ".")
    _sh(repo, "commit", "-q", "-m", "old's own file")

    _sh(repo, "checkout", "-q", "main")
    _write(repo, "shared.txt", "base\nmain edit\n")
    _write(repo, "funcs.txt", "versione originale di main, rompe la build\n")
    _sh(repo, "add", ".")
    _sh(repo, "commit", "-q", "-m", "main adds funcs.txt")

    _sh(repo, "checkout", "-q", "old")
    _sh(repo, "merge", "-q", "--no-ff", "-m", "merge main", "main", check=False)
    _finish_merge(repo)
    _write(repo, "funcs.txt", "versione corretta a mano per non rompere la build\n")
    _amend_worktree(repo)
    merge_sha = _sh(repo, "rev-parse", "HEAD").stdout.strip()

    r = check_merge(repo, merge_sha, verbose=False)
    _check(report, r.status == "ok", "un evil merge con contenuto nuovo non viene bloccato")
    _check(report, r.novel == ["funcs.txt"], "il contenuto nuovo è segnalato come avviso (trovato: %r)" % r.novel)


def _scenario_octopus(base_dir, report):
    repo = _init_repo(base_dir, "octopus")
    _write(repo, "a.txt", "base\n")
    _sh(repo, "add", ".")
    _sh(repo, "commit", "-q", "-m", "base")
    _sh(repo, "checkout", "-q", "-b", "b1")
    _write(repo, "b1.txt", "b1\n")
    _sh(repo, "add", ".")
    _sh(repo, "commit", "-q", "-m", "b1")
    _sh(repo, "checkout", "-q", "main")
    _sh(repo, "checkout", "-q", "-b", "b2")
    _write(repo, "b2.txt", "b2\n")
    _sh(repo, "add", ".")
    _sh(repo, "commit", "-q", "-m", "b2")
    _sh(repo, "checkout", "-q", "main")
    _sh(repo, "merge", "-q", "--no-ff", "-m", "octopus", "b1", "b2")
    merge_sha = _sh(repo, "rev-parse", "HEAD").stdout.strip()

    r = check_merge(repo, merge_sha, verbose=False)
    _check(report, r.status == "skipped", "un octopus merge è saltato esplicitamente, non ignorato in silenzio")
    _check(report, r.note is not None and "octopus" in r.note, "il motivo dello skip nomina gli octopus merge")


# --- self-test del controllo di landing (ADR-0062) ----------------------------------


def _commit_all(repo, message):
    _sh(repo, "add", "-A")
    _sh(repo, "commit", "-q", "-m", message)
    return _sh(repo, "rev-parse", "HEAD").stdout.strip()


def _head(repo):
    return _sh(repo, "rev-parse", "HEAD").stdout.strip()


def _amend_message(repo, extra):
    """Aggiunge righe di trailer al messaggio del commit in punta."""
    message = commit_message(repo, "HEAD").rstrip("\n") + "\n\n" + extra
    _sh(repo, "commit", "-q", "--amend", "-m", message)
    return _head(repo)


def _build_stale_modify_repo(base_dir, squash):
    """La forma pericolosa di ADR-0062 Context: un branch stantio unisce main,
    risolve a mano il conflitto reale (shared.txt), ma riprende dal proprio lato
    kept.txt (che main aveva già cambiato, l'analogo di #515) e toglie il file
    che main aveva aggiunto. Con squash=True il branch viene poi schiacciato
    con l'idioma di tutti i giorni, `git reset --soft main && git commit`:
    nessun merge commit resta da ispezionare.

    Ritorna un dict con repo, base, main e head (lo squash o il merge).
    """
    repo = _init_repo(base_dir, "stale-modify-squash" if squash else "stale-modify-merge")
    _write(repo, "shared.txt", "base\n")
    _write(repo, "kept.txt", "versione di base\n")
    base_sha = _commit_all(repo, "base")

    _sh(repo, "checkout", "-q", "-b", "old")
    _write(repo, "shared.txt", "base\nold change\n")
    _write(repo, "oldfile.txt", "aggiunto solo dal branch stantio\n")
    _commit_all(repo, "old branch's own change")

    _sh(repo, "checkout", "-q", "main")
    _write(repo, "shared.txt", "base\nmain change\n")
    _write(repo, "kept.txt", "versione nuova di main, come PR #515\n")
    _write(repo, "added-by-main.txt", "aggiunto da main\n")
    main_sha = _commit_all(repo, "main change (PR #515-shaped)")

    _sh(repo, "checkout", "-q", "old")
    _sh(repo, "merge", "-q", "--no-ff", "-m", "merge main", "main", check=False)
    _finish_merge(repo)
    _write(repo, "shared.txt", "base\nrisolto a mano\n")
    _sh(repo, "checkout", "HEAD^1", "--", "kept.txt")
    _sh(repo, "rm", "-q", "-f", "added-by-main.txt")
    _amend_worktree(repo)
    head = _head(repo)

    if squash:
        _sh(repo, "reset", "-q", "--soft", "main")
        _sh(repo, "commit", "-q", "-m", "feat: squash del branch stantio")
        head = _head(repo)
    return {"repo": repo, "base": base_sha, "main": main_sha, "head": head}


def _restore_paths(r):
    return [p for p, _, _ in r.restores]


def _scenario_landing_squashed_stale_restore(base_dir, report):
    """L1: lo squash stantio viene rifiutato, solo su kept.txt."""
    f = _build_stale_modify_repo(base_dir, squash=True)
    r = check_landing(f["repo"], f["main"], f["head"])
    _check(report, r.status == "failed", "L1: uno squash che riporta kept.txt alla versione stantia è rifiutato")
    _check(report, r.restores == [("kept.txt", f["base"], f["main"])],
           "L1: solo kept.txt è un restore, tenuto da base fino al commit di main (trovato: %r)" % r.restores)
    _check(report, r.context_deletions == [("added-by-main.txt", f["main"])],
           "L1: la cancellazione di added-by-main.txt è solo contesto (trovato: %r)" % r.context_deletions)
    return f


def _scenario_landing_merge_same_result(base_dir, report, squashed):
    """L2: lo stesso branch senza squash dà gli stessi restore, e anche il
    controllo del merge commit scatta."""
    f = _build_stale_modify_repo(base_dir, squash=False)
    r = check_landing(f["repo"], f["main"], f["head"])
    squashed_r = check_landing(squashed["repo"], squashed["main"], squashed["head"])

    def shape(res, fixture):
        names = {fixture["base"]: "base", fixture["main"]: "main"}
        return [(p, names.get(i, i), names.get(x, x)) for p, i, x in res.restores]

    _check(report, r.status == "failed" and shape(r, f) == shape(squashed_r, squashed) and r.restores,
           "L2: con un merge invece dello squash i restore sono identici (trovato: %r)" % shape(r, f))
    m = check_merge(f["repo"], f["head"], verbose=False)
    _check(report, m.status == "failed", "L2: anche check_merge rifiuta quel merge commit")


def _scenario_landing_checkout_old_rev(base_dir, report):
    """L3: `git checkout <old-rev> -- kept.txt` su un branch sopra main."""
    f = _build_stale_modify_repo(base_dir, squash=False)
    repo = f["repo"]
    _sh(repo, "checkout", "-q", "-b", "restore", "main")
    _sh(repo, "checkout", f["base"], "--", "kept.txt")
    head = _commit_all(repo, "fix: riporta kept.txt")
    r = check_landing(repo, f["main"], head)
    _check(report, r.status == "failed" and _restore_paths(r) == ["kept.txt"],
           "L3: un file copiato da una revisione vecchia è rifiutato (trovato: %s %r)" % (r.status, r.restores))


def _scenario_landing_concurrent_edit(base_dir, report):
    """L4: una modifica concorrente legittima produce un blob che main non ha mai avuto."""
    repo = _init_repo(base_dir, "concurrent-edit")
    _write(repo, "multi.txt", "riga 1\nriga 2\nriga 3\nriga 4\nriga 5\n")
    _commit_all(repo, "base")
    _sh(repo, "checkout", "-q", "-b", "feature")
    _write(repo, "multi.txt", "riga 1\nriga 2\nriga 3\nriga 4\nriga 5 del branch\n")
    feature = _commit_all(repo, "feature edits line 5")
    _sh(repo, "checkout", "-q", "main")
    _write(repo, "multi.txt", "riga 1 di main\nriga 2\nriga 3\nriga 4\nriga 5\n")
    main_sha = _commit_all(repo, "main edits line 1")

    r = check_landing(repo, main_sha, feature)
    _check(report, r.status == "ok" and r.restores == [],
           "L4: una modifica concorrente non unita passa (trovato: %s %r)" % (r.status, r.restores))

    _sh(repo, "checkout", "-q", "feature")
    _sh(repo, "merge", "-q", "--no-ff", "-m", "merge main", "main")
    _sh(repo, "reset", "-q", "--soft", "main")
    _sh(repo, "commit", "-q", "-m", "feat: squash")
    r = check_landing(repo, main_sha, _head(repo))
    _check(report, r.status == "ok" and r.restores == [],
           "L4: la stessa modifica schiacciata su main passa (trovato: %s %r)" % (r.status, r.restores))


def _scenario_landing_pure_deletion_residual(base_dir, report):
    """L5: fissa il residuo di ADR-0062 §D8 — uno snapshot stantio che toglie
    solo un file aggiunto da main passa. Se un giorno fallisce, è una scelta."""
    repo, merge_sha = _build_wholesale_ours_repo(base_dir)
    r = check_landing(repo, "main", merge_sha)
    _check(report, r.status == "ok" and r.restores == [],
           "L5: una cancellazione pura non fa fallire il landing (§D8, trovato: %s %r)" % (r.status, r.restores))


def _scenario_landing_override_accepted(base_dir, report):
    """L6: Restore-override sul commit schiacciato, o su un commit vuoto nel range."""
    f = _build_stale_modify_repo(base_dir, squash=True)
    head = _amend_message(
        f["repo"],
        "Restore-override: kept.txt\nRestore-override-reason: ripristino voluto\n",
    )
    r = check_landing(f["repo"], f["main"], head)
    _check(report, r.status == "ok" and r.overridden == [("kept.txt", "ripristino voluto")],
           "L6: Restore-override sul commit schiacciato fa passare kept.txt (trovato: %s %r)"
           % (r.status, r.overridden))

    f = _build_stale_modify_repo(base_dir, squash=True)
    _sh(f["repo"], "commit", "-q", "--allow-empty", "-m",
        "chore: motiva il ripristino\n\nRestore-override: kept.txt\n"
        "Restore-override-reason: ripristino voluto\n")
    r = check_landing(f["repo"], f["main"], _head(f["repo"]))
    _check(report, r.status == "ok" and r.overridden == [("kept.txt", "ripristino voluto")],
           "L6: Restore-override su un commit vuoto nel range vale lo stesso (trovato: %s %r)"
           % (r.status, r.overridden))

    # Uno squash di GitHub con squash_merge_commit_message = COMMIT_MESSAGES concatena i
    # messaggi del branch: il blocco finisce in mezzo, non nell'ultimo paragrafo.
    f = _build_stale_modify_repo(base_dir, squash=True)
    head = _amend_message(
        f["repo"],
        "fix: ripristina kept.txt (#999)\n\n"
        "* fix: ripristina kept.txt\n\n"
        "Restore-override: kept.txt\nRestore-override-reason: ripristino voluto\n\n"
        "* chore: aggiorna TODO.md\n\nNessun trailer qui.\n",
    )
    r = check_landing(f["repo"], f["main"], head)
    _check(report, r.status == "ok" and r.overridden == [("kept.txt", "ripristino voluto")],
           "L6: Restore-override in mezzo a un messaggio di squash GitHub vale lo stesso (trovato: %s %r)"
           % (r.status, r.overridden))


def _scenario_landing_override_rejected(base_dir, report):
    """L7: `Restore-override: all` e i path senza motivo sono errori d'uso."""
    f = _build_stale_modify_repo(base_dir, squash=True)
    head = _amend_message(f["repo"], "Restore-override: all\nRestore-override-reason: tutto\n")
    r = check_landing(f["repo"], f["main"], head)
    _check(report, r.status == "usage_error", "L7: 'Restore-override: all' è rifiutato")

    f = _build_stale_modify_repo(base_dir, squash=True)
    head = _amend_message(f["repo"], "Restore-override: kept.txt\n")
    r = check_landing(f["repo"], f["main"], head)
    _check(report, r.status == "usage_error", "L7: Restore-override senza Restore-override-reason è rifiutato")


def _scenario_landing_keys_are_separate(base_dir, report):
    """L8: un Merge-override non scusa un restore."""
    f = _build_stale_modify_repo(base_dir, squash=True)
    head = _amend_message(f["repo"], "Merge-override: kept.txt\nMerge-override-reason: altro controllo\n")
    r = check_landing(f["repo"], f["main"], head)
    _check(report, r.status == "failed", "L8: Merge-override non vale per il controllo di landing")


def _scenario_landing_fresh_vs_stale_base(base_dir, report):
    """L9: una base stantia attribuisce alla PR il ripristino voluto di main;
    la punta di main no (ADR-0062 §D3)."""
    repo = _init_repo(base_dir, "fresh-base")
    _write(repo, "kept.txt", "v1\n")
    _commit_all(repo, "base")
    _write(repo, "kept.txt", "v2\n")
    v2 = _commit_all(repo, "main: kept.txt v2")
    _sh(repo, "checkout", "-q", "-b", "pr")
    _write(repo, "other.txt", "lavoro della PR\n")
    _commit_all(repo, "pr: other.txt")
    _sh(repo, "checkout", "-q", "main")
    _write(repo, "kept.txt", "v1\n")
    tip = _commit_all(repo, "main: ripristino voluto di kept.txt v1")
    _sh(repo, "checkout", "-q", "pr")
    _sh(repo, "merge", "-q", "--no-ff", "-m", "merge main", "main")
    head = _head(repo)

    r = check_landing(repo, v2, head)
    _check(report, r.status == "failed" and _restore_paths(r) == ["kept.txt"],
           "L9: con la base stantia il ripristino di main è attribuito alla PR (trovato: %s)" % r.status)
    r = check_landing(repo, tip, head)
    _check(report, r.status == "ok", "L9: con la punta di main la PR è pulita (trovato: %s)" % r.status)


def _scenario_landing_conflicted(base_dir, report):
    """L10: HEAD non discende da BASE, un path in conflitto e un restore."""
    repo = _init_repo(base_dir, "conflicted-landing")
    _write(repo, "kept.txt", "v1\n")
    _write(repo, "conflict.txt", "iniziale\n")
    base_sha = _commit_all(repo, "base")
    _write(repo, "kept.txt", "v2\n")
    _commit_all(repo, "main: kept.txt v2")
    _sh(repo, "checkout", "-q", "-b", "branch")
    _sh(repo, "checkout", base_sha, "--", "kept.txt")
    _write(repo, "conflict.txt", "versione del branch\n")
    branch = _commit_all(repo, "branch: riporta kept.txt e cambia conflict.txt")
    _sh(repo, "checkout", "-q", "main")
    _write(repo, "conflict.txt", "versione di main\n")
    tip = _commit_all(repo, "main: cambia conflict.txt")

    r = check_landing(repo, tip, branch)
    _check(report, r.status == "failed" and _restore_paths(r) == ["kept.txt"],
           "L10: il restore è segnalato anche con un conflitto (trovato: %s %r)" % (r.status, r.restores))
    _check(report, r.skipped_conflicts == ["conflict.txt"],
           "L10: il path in conflitto è saltato, non valutato (trovato: %r)" % r.skipped_conflicts)


def _scenario_landing_standalone_deletion(base_dir, report):
    """L11: cancellare un file appena aggiunto da main non è un restore."""
    repo = _init_repo(base_dir, "standalone-deletion")
    _write(repo, "a.txt", "a\n")
    _commit_all(repo, "base")
    _write(repo, "new.txt", "aggiunto da main\n")
    tip = _commit_all(repo, "main adds new.txt")
    _sh(repo, "checkout", "-q", "-b", "cleanup")
    _sh(repo, "rm", "-q", "new.txt")
    head = _commit_all(repo, "refactor: rimuove new.txt")
    r = check_landing(repo, tip, head)
    _check(report, r.status == "ok" and r.restores == [] and r.context_deletions == [],
           "L11: una cancellazione isolata passa senza contesto (trovato: %s %r)" % (r.status, r.context_deletions))


def _scenario_landings_audit(base_dir, report):
    """A1: --landings valuta ogni commit first-parent come landing a sé, e
    attribuisce il restore al solo landing che lo fa."""
    repo = _init_repo(base_dir, "landings-audit")
    _write(repo, "kept.txt", "v1\n")
    root = _commit_all(repo, "root")
    _write(repo, "a.txt", "a\n")
    _commit_all(repo, "landing 1: aggiunge a.txt")
    _write(repo, "kept.txt", "v2\n")
    _commit_all(repo, "landing 2: kept.txt v2")
    _write(repo, "kept.txt", "v1\n")
    third = _commit_all(repo, "landing 3: riporta kept.txt v1")

    reports = check_landings(repo, "%s..main" % root)
    failed = [r for r in reports if r.status == "failed"]
    _check(report, len(reports) == 3, "A1: tre landing esaminati (trovati: %d)" % len(reports))
    _check(report, len(failed) == 1 and failed[0].head == third
           and _restore_paths(failed[0]) == ["kept.txt"],
           "A1: un solo landing fallito, il terzo, su kept.txt (trovati: %r)"
           % [(r.head[:10], r.status) for r in reports])

    reports = check_landings(repo, "main")
    _check(report, len(reports) == 4 and reports[0].status == "skipped" and reports[0].note,
           "A1: il commit radice è saltato con una nota esplicita (trovato: %r)"
           % [(r.head[:10], r.status) for r in reports])


def _scenario_installed_hook_warning(base_dir, report):
    """H1: l'avviso di hook stantio parla solo quando i due file esistono e differiscono."""
    d = tempfile.mkdtemp(prefix="hook-warning-", dir=base_dir)
    tracked = os.path.join(d, "tracked-pre-push")
    installed = os.path.join(d, "installed-pre-push")
    _write(d, "tracked-pre-push", "#!/usr/bin/env bash\necho nuovo\n")
    _write(d, "installed-pre-push", "#!/usr/bin/env bash\necho nuovo\n")
    _check(report, installed_hook_warning(installed, tracked) is None,
           "H1: hook installato identico a quello tracciato, nessun avviso")
    _check(report, installed_hook_warning(os.path.join(d, "assente"), tracked) is None,
           "H1: nessun hook installato, nessun avviso")
    _write(d, "installed-pre-push", "#!/usr/bin/env bash\necho vecchio\n")
    message = installed_hook_warning(installed, tracked)
    _check(report, message is not None and "scripts/install-git-hooks.sh --force" in message,
           "H1: hook installato diverso, l'avviso nomina il comando di reinstallazione (trovato: %r)" % message)


# --- scenari aggiuntivi (tester, non nominati nel piano ma richiesti da ADR §D2) ----


def _scenario_landing_unresolvable_revision(base_dir, report):
    """Una BASE o una HEAD non risolvibile come commit è un usage_error, non un
    crash (ADR-0062 §D2 passo 1: 'la risoluzione fallisce, esce con 2')."""
    f = _build_stale_modify_repo(base_dir, squash=True)
    r = check_landing(f["repo"], "non-esiste-questo-ref", f["head"])
    _check(report, r.status == "usage_error",
           "BASE non risolvibile: usage_error (trovato: %s)" % r.status)
    r = check_landing(f["repo"], f["main"], "non-esiste-questo-ref")
    _check(report, r.status == "usage_error",
           "HEAD non risolvibile: usage_error (trovato: %s)" % r.status)


def _scenario_landing_rename_and_mode_only(base_dir, report):
    """Un rename puro (stesso blob, path nuovo) o un cambio di sola modalità
    (stesso blob, mode diverso) non è mai un restore: diff-tree e
    first_parent_record scartano esplicitamente old_oid == new_oid, la stessa
    riga di codice per entrambe le forme."""
    repo = _init_repo(base_dir, "rename-mode-only")
    _write(repo, "old.txt", "contenuto invariato\n")
    _write(repo, "script.sh", "#!/bin/sh\necho ciao\n")
    base_sha = _commit_all(repo, "base")

    _sh(repo, "checkout", "-q", "-b", "branch")
    _sh(repo, "mv", "old.txt", "new.txt")
    _commit_all(repo, "rinomina old.txt in new.txt")
    os.chmod(os.path.join(repo, "script.sh"), 0o755)
    head = _commit_all(repo, "chmod +x script.sh")

    r = check_landing(repo, base_sha, head)
    _check(report, r.status == "ok" and r.restores == [] and r.context_deletions == [],
           "rename puro + chmod: nessun restore né cancellazione di contesto (trovato: %s %r)"
           % (r.status, r.restores))


def _script_path():
    return os.path.abspath(__file__)


def _run_cli(repo, *args):
    return subprocess.run(
        [sys.executable, _script_path(), *args],
        cwd=repo,
        capture_output=True,
        text=True,
    )


def _scenario_cli_landing_exit_codes(base_dir, report):
    """Il --landing della CLI usa gli stessi codici di ADR-0061: 0 pulito, 1 un
    restore trovato, 2 uso scorretto (revisione non risolvibile). Verificato
    invocando davvero lo script, non solo la funzione Python sotto: qui è
    l'argparse e main() ad essere sotto esame, non check_landing."""
    f = _build_stale_modify_repo(base_dir, squash=True)
    ok_repo = _init_repo(base_dir, "cli-ok")
    _write(ok_repo, "a.txt", "a\n")
    ok_base = _commit_all(ok_repo, "base")
    _write(ok_repo, "b.txt", "b\n")
    ok_head = _commit_all(ok_repo, "aggiunge b.txt")

    r_ok = _run_cli(ok_repo, "--landing", ok_base, ok_head)
    _check(report, r_ok.returncode == 0,
           "CLI --landing pulito: exit 0 (trovato: %d)" % r_ok.returncode)

    r_failed = _run_cli(f["repo"], "--landing", f["main"], f["head"])
    _check(report, r_failed.returncode == 1,
           "CLI --landing con restore: exit 1 (trovato: %d)" % r_failed.returncode)

    r_usage = _run_cli(f["repo"], "--landing", f["main"], "non-esiste-questo-ref")
    _check(report, r_usage.returncode == 2,
           "CLI --landing con revisione non risolvibile: exit 2 (trovato: %d)" % r_usage.returncode)


def _scenario_cli_mode_mutual_exclusion(base_dir, report):
    """--landing e --landings sono mutuamente esclusivi fra loro e con --range,
    --pr-base e --pr-head (ADR-0062 §D4, piano Task 1/2): l'uso combinato esce
    con 2, mai un crash né un'esecuzione silenziosa di un solo modo."""
    repo = _init_repo(base_dir, "cli-mutex")
    _write(repo, "a.txt", "a\n")
    _commit_all(repo, "base")

    r = _run_cli(repo, "--landing", "HEAD", "HEAD", "--range", "HEAD..HEAD")
    _check(report, r.returncode == 2,
           "--landing insieme a --range: exit 2 (trovato: %d)" % r.returncode)

    r = _run_cli(repo, "--landing", "HEAD", "HEAD", "--landings", "HEAD..HEAD")
    _check(report, r.returncode == 2,
           "--landing insieme a --landings: exit 2 (trovato: %d)" % r.returncode)

    r = _run_cli(repo, "--landings", "HEAD..HEAD", "--pr-base", "HEAD", "--pr-head", "HEAD")
    _check(report, r.returncode == 2,
           "--landings insieme a --pr-base/--pr-head: exit 2 (trovato: %d)" % r.returncode)


def _scenario_landing_cannot_verify(base_dir, report):
    """PG-248: HEAD non discende da BASE e git merge-tree non riesce a produrre un
    albero. Provocato togliendo un blob dall'object store del repo usa e getta:
    merge-tree esce con 128 e stdout vuoto, mentre merge-base --is-ancestor, che
    legge solo i commit, risponde ancora."""
    repo = _init_repo(base_dir, "cannot-verify")
    _write(repo, "f.txt", "".join("%d\n" % i for i in range(1, 9)))
    _commit_all(repo, "base")
    _sh(repo, "checkout", "-q", "-b", "branch")
    _write(repo, "f.txt", "".join("%d\n" % i for i in range(1, 8)) + "8 del branch\n")
    head = _commit_all(repo, "branch: cambia l'ultima riga")
    _sh(repo, "checkout", "-q", "main")
    _write(repo, "f.txt", "1 di main\n" + "".join("%d\n" % i for i in range(2, 9)))
    tip = _commit_all(repo, "main: cambia la prima riga")

    blob = _sh(repo, "rev-parse", "%s:f.txt" % head).stdout.strip()
    loose = os.path.join(repo, ".git", "objects", blob[:2], blob[2:])
    if not os.path.isfile(loose):
        # Un gc che ha già impacchettato il blob: la fixture non vale, lo si dice
        # come un controllo fallito invece di far saltare l'intero self-test.
        _check(report, False, "PG-248: blob %s non più loose, fixture non costruibile" % blob[:10])
        return
    os.chmod(loose, 0o644)
    os.remove(loose)

    r = check_landing(repo, tip, head)
    _check(report, r.status == "cannot_verify" and "merge-tree" in (r.note or ""),
           "PG-248: merge-tree senza albero dà cannot_verify (trovato: %s %r)" % (r.status, r.note))
    cli = _run_cli(repo, "--landing", tip, head)
    _check(report, cli.returncode == 2 and "Traceback" not in cli.stderr,
           "PG-248: CLI --landing non verificabile esce con 2 (trovato: %d)" % cli.returncode)


def _scenario_cli_range_unresolvable(base_dir, report):
    """PG-244: un --range la cui base non esiste (origin/main in un repo senza
    remote) esce con 2 e un messaggio, mai con un traceback."""
    repo = _init_repo(base_dir, "range-unresolvable")
    _write(repo, "a.txt", "a\n")
    _commit_all(repo, "base")
    r = _run_cli(repo, "--range", "origin/main..HEAD")
    _check(report, r.returncode == 2 and "Traceback" not in r.stderr
           and "range non risolvibile" in r.stderr,
           "PG-244: --range con base assente esce con 2 senza traceback (trovato: %d %r)"
           % (r.returncode, r.stderr[-200:]))


def self_test():
    report = []
    tmp = tempfile.mkdtemp(prefix="pergamenum-merge-integrity-selftest-")
    try:
        _scenario_clean_merge(tmp, report)
        _scenario_wholesale_ours(tmp, report)
        _scenario_override(tmp, report)
        _scenario_bare_all_rejected(tmp, report)
        _scenario_novel_content(tmp, report)
        _scenario_octopus(tmp, report)
        squashed = _scenario_landing_squashed_stale_restore(tmp, report)
        _scenario_landing_merge_same_result(tmp, report, squashed)
        _scenario_landing_checkout_old_rev(tmp, report)
        _scenario_landing_concurrent_edit(tmp, report)
        _scenario_landing_pure_deletion_residual(tmp, report)
        _scenario_landing_override_accepted(tmp, report)
        _scenario_landing_override_rejected(tmp, report)
        _scenario_landing_keys_are_separate(tmp, report)
        _scenario_landing_fresh_vs_stale_base(tmp, report)
        _scenario_landing_conflicted(tmp, report)
        _scenario_landing_standalone_deletion(tmp, report)
        _scenario_landings_audit(tmp, report)
        _scenario_installed_hook_warning(tmp, report)
        _scenario_landing_unresolvable_revision(tmp, report)
        _scenario_landing_rename_and_mode_only(tmp, report)
        _scenario_cli_landing_exit_codes(tmp, report)
        _scenario_cli_mode_mutual_exclusion(tmp, report)
        _scenario_landing_cannot_verify(tmp, report)
        _scenario_cli_range_unresolvable(tmp, report)
    finally:
        # Guardia: non cancellare mai nulla fuori dalla nostra directory temporanea.
        if tmp.startswith(tempfile.gettempdir()) and os.path.basename(tmp).startswith(
            "pergamenum-merge-integrity-selftest-"
        ):
            shutil.rmtree(tmp, ignore_errors=True)

    failed = [line for line in report if line.startswith("FALLITO")]
    print("check-merge-integrity.py --self-test: %d controlli" % len(report))
    print("\n".join(report))
    return 1 if failed else 0


# --- CLI -----------------------------------------------------------------------------


def build_parser():
    parser = argparse.ArgumentParser(
        description="Trova un merge che ha scartato in silenzio il contenuto di un genitore "
        "(ADR-0061), o un landing che riporta un path a una versione che main aveva già "
        "superato (ADR-0062)."
    )
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--range", help="intervallo git, es. origin/main..HEAD (default)")
    modes.add_argument(
        "--landing",
        nargs=2,
        metavar=("BASE", "HEAD"),
        help="valuta HEAD come se atterrasse su BASE adesso (ADR-0062)",
    )
    modes.add_argument(
        "--landings",
        metavar="RANGE",
        help="audit: ogni commit first-parent L del range come landing di L su L^1 (ADR-0062)",
    )
    parser.add_argument("--pr-base", help="sha di base della PR")
    parser.add_argument("--pr-head", help="sha di head della PR")
    parser.add_argument("--verbose", action="store_true", help="stampa anche i merge puliti")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="esegue le asserzioni interne, in repository usa e getta, e non tocca questo repository",
    )
    return parser


def _landing_exit_code(reports) -> int:
    """Stessi codici di ADR-0061: 2 prima di 1 per un errore d'uso, 1 prima di 2
    per un non verificabile (un fallimento reale non si nasconde dietro un 2)."""
    statuses = [r.status for r in reports]
    if "usage_error" in statuses:
        return 2
    if "failed" in statuses:
        return 1
    if "cannot_verify" in statuses:
        return 2
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if "--self-test" in argv:
        if len(argv) != 1:
            print("--self-test non si combina con altri argomenti", file=sys.stderr)
            return 2
        return self_test()

    parser = build_parser()
    args = parser.parse_args(argv)
    if (args.landing or args.landings) and (args.pr_base or args.pr_head):
        parser.error("--landing/--landings non si combinano con --pr-base/--pr-head")

    repo = os.getcwd()
    for warning in config_warnings(repo):
        print("AVVISO CONFIGURAZIONE: %s" % warning)
    # In ogni modo, --range compreso: l'hook di ADR-0061 ancora installato
    # chiama solo --range, ed è proprio quello il caso da far vedere.
    hook_warning = _hook_warning_for_cwd(repo)
    if hook_warning:
        print("AVVISO HOOK: %s" % hook_warning)

    if args.landing:
        report = check_landing(repo, args.landing[0], args.landing[1])
        # Sempre stampato, anche pulito: chi legge il log di un push o di un job
        # deve vedere contro quale base il landing è stato confrontato.
        print_landing_report(repo, report, verbose=True)
        return _landing_exit_code([report])

    if args.landings:
        reports = check_landings(repo, args.landings)
        for r in reports:
            print_landing_report(repo, r, args.verbose)
        print(
            "check-merge-integrity.py: %d landing esaminati, %d falliti, %d non verificabili, "
            "%d saltati (senza genitori)" % (
                len(reports),
                sum(1 for r in reports if r.status == "failed"),
                sum(1 for r in reports if r.status == "cannot_verify"),
                sum(1 for r in reports if r.status == "skipped"),
            )
        )
        return _landing_exit_code(reports)

    if args.pr_base and args.pr_head:
        range_spec = "%s..%s" % (args.pr_base, args.pr_head)
    elif args.range:
        range_spec = args.range
    else:
        range_spec = "origin/main..HEAD"

    merges, error = merges_in_range(repo, range_spec)
    if error:
        print("check-merge-integrity.py: range non risolvibile: %s (%s)" % (range_spec, error),
              file=sys.stderr)
        return 2
    if not merges:
        print("check-merge-integrity.py: nessun merge commit in %s" % range_spec)
        return 0

    reports = [check_merge(repo, sha, args.verbose) for sha in merges]
    for r in reports:
        print_report(repo, r, args.verbose)

    failed = sum(1 for r in reports if r.status == "failed")
    skipped = sum(1 for r in reports if r.status == "skipped")
    cannot_verify = sum(1 for r in reports if r.status == "cannot_verify")
    usage_errors = sum(1 for r in reports if r.status == "usage_error")

    print(
        "check-merge-integrity.py: %d merge esaminati, %d falliti, %d saltati (octopus), "
        "%d non verificabili" % (len(merges), failed, skipped, cannot_verify)
    )

    if usage_errors:
        return 2
    if failed:
        return 1
    if cannot_verify:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
