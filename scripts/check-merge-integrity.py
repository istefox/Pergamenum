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

Uso:
    scripts/check-merge-integrity.py [--range A..B] [--verbose]
    scripts/check-merge-integrity.py --pr-base <sha> --pr-head <sha>
    scripts/check-merge-integrity.py --self-test

Uscita: 0 pulito, 1 side-pick trovato, 2 non verificabile o uso scorretto.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

OVERRIDE_PREFIX = "Merge-override:"
OVERRIDE_REASON_PREFIX = "Merge-override-reason:"


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
    r = _git(repo, "rev-list", "--merges", range_spec)
    return [line.strip() for line in r.stdout.splitlines() if line.strip()]


# --- override trailer ------------------------------------------------------------


def parse_overrides(repo, sha):
    """Ritorna (paths, reason, error). error non-None => uso scorretto (exit 2)."""
    msg = commit_message(repo, sha)
    paths = []
    reasons = []
    bare_all = False
    for raw_line in msg.splitlines():
        line = raw_line.strip()
        if line.startswith(OVERRIDE_PREFIX):
            value = line[len(OVERRIDE_PREFIX):].strip()
            if value == "all":
                bare_all = True
            elif value:
                paths.append(value)
        elif line.startswith(OVERRIDE_REASON_PREFIX):
            reason = line[len(OVERRIDE_REASON_PREFIX):].strip()
            if reason:
                reasons.append(reason)
    if bare_all:
        return [], None, "'Merge-override: all' è rifiutato — elenca i path uno per uno"
    if paths and not reasons:
        return [], None, "Merge-override richiede anche Merge-override-reason con un motivo non vuoto"
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
        description="Trova un merge che ha scartato in silenzio il contenuto di un genitore."
    )
    parser.add_argument("--range", help="intervallo git, es. origin/main..HEAD (default)")
    parser.add_argument("--pr-base", help="sha di base della PR")
    parser.add_argument("--pr-head", help="sha di head della PR")
    parser.add_argument("--verbose", action="store_true", help="stampa anche i merge puliti")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="esegue le asserzioni interne, in repository usa e getta, e non tocca questo repository",
    )
    return parser


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if "--self-test" in argv:
        if len(argv) != 1:
            print("--self-test non si combina con altri argomenti", file=sys.stderr)
            return 2
        return self_test()

    args = build_parser().parse_args(argv)
    if args.pr_base and args.pr_head:
        range_spec = "%s..%s" % (args.pr_base, args.pr_head)
    elif args.range:
        range_spec = args.range
    else:
        range_spec = "origin/main..HEAD"

    repo = os.getcwd()
    for warning in config_warnings(repo):
        print("AVVISO CONFIGURAZIONE: %s" % warning)

    merges = merges_in_range(repo, range_spec)
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
