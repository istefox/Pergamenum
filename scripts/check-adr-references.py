#!/usr/bin/env python3
"""Check the three rules of the ADR directory README on the working tree.

The rules live in `docs/adr/README.md` and this command reads them from there,
nowhere else. PG-273, the follow-up of chain 14 (issue #581): chain 14 checked
the rules by hand, once, and a mechanical rule nobody runs decays.

- Rule 1, one number per file: two files under `docs/adr/` sharing a number are
  a finding. Against a base ref, a number the branch introduced since its
  merge-base with the base, held on the base by another file name, is a finding
  too. A slug rename of a number present at the merge-base, and a `git mv` to a
  number the base does not hold, are not.
- Rule 2, a status line: every ADR states its status in its head, as a
  `- Status:` bullet (bold or not) or as a `## Status` section that is the first
  second-level heading, and the status word is one of `accepted`, `proposed`,
  `superseded`, `deprecated`, `rejected`. An ADR the base holds that still reads
  `proposed` is a finding. A commit hash inside the status statement that is
  not a commit on the base's first-parent line is a warning, never a finding.
- Rule 3, a citation says where the ADR lives: in every scanned file, the first
  citation of a number `docs/adr/` does not hold must share its sentence with a
  qualifying phrase from the README's «External ADR series» table. Later
  citations of the same number in the file are not checked.

The scanned set is every tracked `.swift`, `.md`, `.yml`, `.yaml`, `.py` and
`.sh` file except the root `TODO.md` and `SPEC.md`, read from the working tree.

Usage:
    scripts/check-adr-references.py [--base REF] [--verbose]
    scripts/check-adr-references.py --self-test

With no `--base`, the base is `origin/main` when it resolves (run `git fetch
origin` first). A base that does not resolve, or shares no history with HEAD,
prints a notice and skips the base checks; the in-tree checks still decide.

Exit: 0 clean, 1 a finding, 2 a check that could not run (bad usage, not a git
repository, the registry table missing or unreadable, a file that cannot be
read). 2 outranks 1; rules 1 and 2 still print before it. Warnings and notices
never change the exit code.

The check is advisory: `.github/workflows/adr-references.yml` runs it on every
pull request and push to `main`, never as a required check, and it is not in
the pre-push hook, because it reads prose and a comment citation should not
stop a push.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Dict, List, Optional, Tuple

ADR_DIR = "docs/adr"
README = "docs/adr/README.md"
REGISTRY_HEADING = "## External ADR series"
PHRASE_COLUMN = "Qualifying phrase"
SCANNED_SUFFIXES = (".swift", ".md", ".yml", ".yaml", ".py", ".sh")
EXCLUDED_ROOT_FILES = ("TODO.md", "SPEC.md")
STATUS_WORDS = ("accepted", "proposed", "superseded", "deprecated", "rejected")
DEFAULT_BASE = "origin/main"

PROG = "check-adr-references.py"


ADR_NAME = re.compile(r"^(\d{4})-.+\.md$")
STATUS_BULLET = re.compile(r"^- (\*\*)?Status(\*\*)?:(\*\*)?", re.IGNORECASE)
# 7 to 40 hex characters bounded by non-alphanumerics; a digit is required below,
# so an ordinary word made of a-f letters is never read as a hash.
HEX_WORD = re.compile(r"(?<![0-9A-Za-z])[0-9a-fA-F]{7,40}(?![0-9A-Za-z])")
# `ADR-` plus exactly four digits, not glued to a preceding letter or digit, and
# case-sensitive: a lower-case file name is not a citation.
CITATION = re.compile(r"(?<![A-Za-z0-9])ADR-(\d{4})(?!\d)")
COMMENT_MARKERS = {
    ".swift": ("///", "//"),
    ".py": ("#",),
    ".sh": ("#",),
    ".yml": ("#",),
    ".yaml": ("#",),
}
MARKDOWN_HEADING = re.compile(r"^#{1,6} ")
BLOCK_STARTER = re.compile(r"^(?:[-*+] |\d+[.)] |\||```|~~~)")
SENTENCE_END = re.compile(r"[.!?][)\]»\"'*_`]*(?=\s)")
SENTENCE_OPENERS = "([\"*_`"


class UsageError(Exception):
    """A check that cannot run: reported on stderr, exit 2, never a traceback."""


class Finding:
    def __init__(self, rule: int, path: str, line: int, message: str) -> None:
        self.rule = rule
        self.path = path
        self.line = line
        self.message = message

    def __str__(self) -> str:
        return "%s:%d: rule %d: %s" % (self.path, self.line, self.rule, self.message)


class Warning_:
    def __init__(self, path: str, line: int, message: str) -> None:
        self.path = path
        self.line = line
        self.message = message

    def __str__(self) -> str:
        return "%s:%d: warning (rule 2): %s" % (self.path, self.line, self.message)


class Base:
    def __init__(self, ref: str, sha: str, merge_base: str) -> None:
        self.ref = ref
        self.sha = sha
        self.merge_base = merge_base


# --- git -----------------------------------------------------------------------------


def _git(repo: str, *args: str, stdin: Optional[str] = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            ["git", "-C", repo, *args],
            capture_output=True,
            text=True,
            input=stdin,
        )
    except OSError as error:
        raise UsageError("cannot run git: %s" % error)


def repository_root(cwd: str) -> str:
    done = _git(cwd, "rev-parse", "--show-toplevel")
    root = done.stdout.strip()
    if done.returncode != 0 or not root:
        raise UsageError("%s is not inside a git repository" % cwd)
    return root


def resolve_base(root: str, ref: str, notices: List[str]) -> Optional[Base]:
    """The base and its merge-base with HEAD, or None with one notice naming the
    ref and the reason: every base check is then skipped (R-02)."""
    skipped = "base checks skipped (rule 1 against the base, proposed on the base, status hashes)"
    done = _git(root, "rev-parse", "--verify", "--quiet", ref + "^{commit}")
    if done.returncode != 0:
        notices.append("base %s does not resolve to a commit; %s" % (ref, skipped))
        return None
    sha = done.stdout.strip()
    done = _git(root, "merge-base", "HEAD", sha)
    if done.returncode != 0:
        notices.append("base %s has no merge-base with HEAD; %s" % (ref, skipped))
        return None
    return Base(ref, sha, done.stdout.strip())


def numbered(names: List[str]) -> Dict[str, List[str]]:
    """ADR file names grouped by number, each group in sorted order."""
    held = {}  # type: Dict[str, List[str]]
    for name in sorted(names):
        match = ADR_NAME.match(name)
        if match:
            held.setdefault(match.group(1), []).append(name)
    return held


def working_tree_names(root: str) -> List[str]:
    directory = os.path.join(root, ADR_DIR)
    if not os.path.isdir(directory):
        return []
    return [n for n in os.listdir(directory) if os.path.isfile(os.path.join(directory, n))]


def commit_names(root: str, commit: str) -> List[str]:
    done = _git(root, "ls-tree", "--name-only", commit, ADR_DIR + "/")
    if done.returncode != 0:
        return []
    return [os.path.basename(p) for p in done.stdout.splitlines()]


def adr_path(name: str) -> str:
    return "%s/%s" % (ADR_DIR, name)


def read_text(root: str, relpath: str, errors: List[str]) -> Optional[str]:
    try:
        with open(os.path.join(root, relpath), encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError as error:
        errors.append("cannot read %s: %s" % (relpath, error.strerror or error))
        return None


# --- rule 1 --------------------------------------------------------------------------


def rule_one(
    held: Dict[str, List[str]],
    base: Optional[Base],
    base_held: Dict[str, List[str]],
    merge_base_held: Dict[str, List[str]],
) -> Tuple[List[Finding], set]:
    """Duplicates in the tree, then numbers the branch introduced that the base
    holds under another name. Returns the findings and the numbers reported
    against the base, which rule 2's «proposed on the base» leaves alone."""
    found = []  # type: List[Finding]
    against_base = set()
    for number, names in sorted(held.items()):
        if len(names) > 1:
            found.append(Finding(1, adr_path(names[0]), 1, "number %s is also held by %s" % (
                number, ", ".join(adr_path(n) for n in names[1:]))))
    if base is None:
        return found, against_base
    for number, names in sorted(held.items()):
        if number in merge_base_held or number not in base_held:
            continue  # a slug rename, or a number still free on the base
        for name in names:
            others = [n for n in base_held[number] if n != name]
            if others:
                found.append(Finding(1, adr_path(name), 1, "number %s is held on %s by %s; "
                                     "take the next free number" % (
                                         number, base.ref, ", ".join(adr_path(n) for n in others))))
                against_base.add(number)
    return found, against_base


# --- rule 2 --------------------------------------------------------------------------


def status_statement(lines: List[str]) -> Optional[List[Tuple[int, str]]]:
    """The status statement as (line number, text) pairs, or None.

    The head is every line before the first `## ` heading that is not
    `## Status`. A status bullet in the head, plus its continuation lines
    indented by two or more spaces, wins; otherwise a `## Status` section that
    is the first `## ` heading gives its first paragraph."""
    first = next((i for i, line in enumerate(lines) if line.startswith("## ")), None)
    status_section = first is not None and lines[first].strip().lower() == "## status"
    if first is None:
        head_end = len(lines)
    elif status_section:
        head_end = next(
            (i for i in range(first + 1, len(lines)) if lines[i].startswith("## ")), len(lines)
        )
    else:
        head_end = first
    for index in range(head_end):
        if STATUS_BULLET.match(lines[index]):
            statement = [(index + 1, lines[index])]
            following = index + 1
            while following < len(lines) and lines[following].startswith("  ") \
                    and lines[following].strip():
                statement.append((following + 1, lines[following]))
                following += 1
            return statement
    if status_section:
        index = first + 1
        while index < head_end and not lines[index].strip():
            index += 1
        statement = []
        while index < head_end and lines[index].strip() and not lines[index].startswith("#"):
            statement.append((index + 1, lines[index]))
            index += 1
        return statement or None
    return None


def status_word(statement: List[Tuple[int, str]]) -> str:
    text = " ".join(line for _, line in statement)
    marker = STATUS_BULLET.match(text)
    if marker:
        text = text[marker.end():]
    text = re.sub(r"[*_`]", "", text)
    match = re.search(r"[A-Za-z]+", text)
    return match.group(0).lower() if match else ""


def commits_of(root: str, words: List[str]) -> Dict[str, Optional[str]]:
    """Each hex word mapped to the commit it names, or None. One process."""
    unique = sorted(set(words))
    if not unique:
        return {}
    done = _git(root, "cat-file", "--batch-check",
                stdin="".join(word + "^{commit}\n" for word in unique))
    answers = done.stdout.splitlines() if done.returncode == 0 else []
    resolved = {}  # type: Dict[str, Optional[str]]
    for index, word in enumerate(unique):
        fields = answers[index].split() if index < len(answers) else []
        resolved[word] = fields[0] if len(fields) == 3 and fields[1] == "commit" else None
    return resolved


def rule_two(
    root: str,
    held: Dict[str, List[str]],
    base: Optional[Base],
    base_held: Dict[str, List[str]],
    against_base: set,
    errors: List[str],
) -> Tuple[List[Finding], List[Warning_]]:
    found = []  # type: List[Finding]
    hex_sites = []  # type: List[Tuple[str, int, str]]
    for number, names in sorted(held.items()):
        for name in names:
            path = adr_path(name)
            text = read_text(root, path, errors)
            if text is None:
                continue
            statement = status_statement(text.splitlines())
            if statement is None:
                found.append(Finding(2, path, 1, "no status line in the head: a `- Status:` "
                                     "bullet, or `## Status` as the first second-level section"))
                continue
            line = statement[0][0]
            word = status_word(statement)
            if word not in STATUS_WORDS:
                found.append(Finding(2, path, line, "status word %r is not one of %s" % (
                    word, ", ".join(STATUS_WORDS))))
            elif word == "proposed" and base is not None and number in base_held \
                    and number not in against_base:
                found.append(Finding(2, path, line, "reads proposed, but %s already holds %s: "
                                     "flip it to accepted with its landing evidence" % (
                                         base.ref, number)))
            for line_number, text_line in statement:
                for match in HEX_WORD.finditer(text_line):
                    if any(c.isdigit() for c in match.group(0)):
                        hex_sites.append((path, line_number, match.group(0)))
    warnings = []  # type: List[Warning_]
    if base is None or not hex_sites:
        return found, warnings
    resolved = commits_of(root, [word for _, _, word in hex_sites])
    listed = _git(root, "rev-list", "--first-parent", base.sha)
    first_parent = set(listed.stdout.split()) if listed.returncode == 0 else set()
    for path, line_number, word in hex_sites:
        full = resolved.get(word)
        if full is None:
            warnings.append(Warning_(path, line_number, "`%s` is not a commit" % word))
        elif full not in first_parent:
            warnings.append(Warning_(path, line_number, "`%s` is not on the first-parent line "
                                     "of %s" % (word, base.ref)))
    return found, warnings


# --- rule 3 --------------------------------------------------------------------------


def _cells(row: str) -> List[str]:
    return [cell.strip() for cell in row.strip().strip("|").split("|")]


def read_registry(root: str) -> List[str]:
    """The qualifying phrases of the README's «External ADR series» table (R-08).
    Raises UsageError when the table is missing or unreadable."""
    path = os.path.join(root, README)
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except FileNotFoundError:
        raise UsageError("%s is missing, so rule 3 has no qualifying phrases" % README)
    except OSError as error:
        raise UsageError("cannot read %s: %s" % (README, error.strerror or error))
    start = next((i for i, line in enumerate(lines) if line.rstrip() == REGISTRY_HEADING), None)
    if start is None:
        raise UsageError("%s has no %r heading" % (README, REGISTRY_HEADING))
    table = []  # type: List[str]
    for line in lines[start + 1:]:
        if MARKDOWN_HEADING.match(line):
            break
        if line.lstrip().startswith("|"):
            table.append(line)
        elif table:
            break
    if not table:
        raise UsageError("%s has no table under %r" % (README, REGISTRY_HEADING))
    header = [cell.lower() for cell in _cells(table[0])]
    if PHRASE_COLUMN.lower() not in header:
        raise UsageError("the %r table in %s has no %r column" % (
            REGISTRY_HEADING, README, PHRASE_COLUMN))
    column = header.index(PHRASE_COLUMN.lower())
    rows = table[1:]
    if rows and set(rows[0].replace(" ", "")) <= set("|-:"):
        rows = rows[1:]
    if not rows:
        raise UsageError("the %r table in %s has no data row" % (REGISTRY_HEADING, README))
    phrases = []
    for row in rows:
        cells = _cells(row)
        phrase = cells[column].strip("`").strip() if column < len(cells) else ""
        if not phrase:
            raise UsageError("the %r table in %s has an empty %r cell" % (
                REGISTRY_HEADING, README, PHRASE_COLUMN))
        phrases.append(phrase)
    return phrases


def scanned_files(root: str) -> List[str]:
    """Tracked files with a scanned suffix, minus the root TODO.md and SPEC.md,
    present in the working tree as regular files (a symlink is skipped)."""
    done = _git(root, "ls-files", "-z")
    if done.returncode != 0:
        raise UsageError("git ls-files failed: %s" % done.stderr.strip())
    paths = []
    for path in done.stdout.split("\0"):
        if not path or not path.endswith(SCANNED_SUFFIXES) or path in EXCLUDED_ROOT_FILES:
            continue
        full = os.path.join(root, path)
        if os.path.islink(full) or not os.path.isfile(full):
            continue
        paths.append(path)
    return paths


def blocks(text: str, suffix: str) -> List[List[Tuple[int, str]]]:
    """Lines grouped into blocks: a blank line, a change between comment and
    plain text, or a line starting a markdown block begins a new one."""
    markers = COMMENT_MARKERS.get(suffix, ())
    result = []  # type: List[List[Tuple[int, str]]]
    current = []  # type: List[Tuple[int, str]]
    kind = None  # type: Optional[str]
    for number, raw in enumerate(text.splitlines(), start=1):
        body = raw.strip()
        line_kind = "plain"
        for marker in markers:
            if body.startswith(marker):
                line_kind = "comment"
                body = body[len(marker):].strip()
                break
        if not body:
            if current:
                result.append(current)
            current, kind = [], None
            continue
        starts = (
            line_kind != kind
            or (suffix == ".md" and MARKDOWN_HEADING.match(body) is not None)
            or BLOCK_STARTER.match(body) is not None
        )
        if starts and current:
            result.append(current)
            current = []
        current.append((number, body))
        kind = line_kind
    if current:
        result.append(current)
    return result


def sentence_bounds(joined: str) -> List[Tuple[int, int]]:
    """Split after `.`, `!` or `?` (plus closing punctuation) when whitespace and
    then an upper-case letter or `«` follow, optionally after an opener."""
    bounds = []
    begin = 0
    for match in SENTENCE_END.finditer(joined):
        cursor = match.end()
        while cursor < len(joined) and joined[cursor].isspace():
            cursor += 1
        while cursor < len(joined) and joined[cursor] in SENTENCE_OPENERS:
            cursor += 1
        if cursor < len(joined) and (joined[cursor] == "«" or joined[cursor].isupper()):
            bounds.append((begin, match.end()))
            begin = match.end()
    bounds.append((begin, len(joined)))
    return bounds


def _fold(text: str) -> str:
    return " ".join(text.split()).casefold()


def rule_three(path: str, text: str, held: Dict[str, List[str]], phrases: List[str]) -> List[Finding]:
    found = []  # type: List[Finding]
    folded_phrases = [_fold(p) for p in phrases]
    seen = set()
    suffix = os.path.splitext(path)[1]
    for block in blocks(text, suffix):
        starts = []
        offset = 0
        for _, body in block:
            starts.append(offset)
            offset += len(body) + 1
        joined = " ".join(body for _, body in block)
        bounds = None  # computed only when a block holds a citation to check
        for match in CITATION.finditer(joined):
            number = match.group(1)
            if number in seen:
                continue  # only the first citation of a number in a file is checked
            seen.add(number)
            if number in held:
                continue
            if bounds is None:
                bounds = sentence_bounds(joined)
            begin, end = next((b, e) for b, e in bounds if b <= match.start() < e)
            sentence = _fold(joined[begin:end])
            if any(phrase in sentence for phrase in folded_phrases):
                continue
            row = max(i for i, start in enumerate(starts) if start <= match.start())
            found.append(Finding(3, path, block[row][0], "first citation of %s in this file: "
                                 "%s holds no %s, and the sentence names no origin from the %r "
                                 "table in %s" % (match.group(0), ADR_DIR, number,
                                                  REGISTRY_HEADING, README)))
    return found


# --- the check -----------------------------------------------------------------------


def run(repo: str, base: Optional[str], verbose: bool) -> int:
    root = repository_root(repo)
    notices = []  # type: List[str]
    errors = []  # type: List[str]
    ref = base or DEFAULT_BASE
    resolved = resolve_base(root, ref, notices)

    held = numbered(working_tree_names(root))
    base_held = {}  # type: Dict[str, List[str]]
    merge_base_held = {}  # type: Dict[str, List[str]]
    if resolved is not None:
        base_held = numbered(commit_names(root, resolved.sha))
        merge_base_held = numbered(commit_names(root, resolved.merge_base))

    found_one, against_base = rule_one(held, resolved, base_held, merge_base_held)
    found_two, warnings = rule_two(root, held, resolved, base_held, against_base, errors)

    phrases = None  # type: Optional[List[str]]
    try:
        phrases = read_registry(root)
    except UsageError as error:
        errors.append(str(error) + "; rule 3 not run")
    paths = scanned_files(root)
    found_three = []  # type: List[Finding]
    if phrases is not None:
        for path in paths:
            text = read_text(root, path, errors)
            if text is not None:
                found_three.extend(rule_three(path, text, held, phrases))

    for notice in notices:
        print("notice: %s" % notice)
    if verbose:
        if resolved is not None:
            print("base: %s -> %s" % (resolved.ref, resolved.sha))
            print("merge-base: %s" % resolved.merge_base)
        print("scanned: %d files" % len(paths))
        if phrases is not None:
            print("phrases: %s" % ", ".join('"%s"' % p for p in phrases))
    for finding in found_one + found_two + found_three:
        print(finding)
    for warning in warnings:
        print(warning)
    sys.stdout.flush()
    for error in errors:
        print("%s: error: %s" % (PROG, error), file=sys.stderr)
    print("%s: rule 1: %d, rule 2: %d, rule 3: %d findings; %d warnings" % (
        PROG, len(found_one), len(found_two), len(found_three), len(warnings)))
    if errors:
        return 2
    if found_one or found_two or found_three:
        return 1
    return 0


# --- self-test ---------------------------------------------------------------------

SELFTEST_PREFIX = "pergamenum-adr-references-selftest-"
SCRIPT = os.path.abspath(__file__)


def cite(number: int) -> str:
    """A citation built at runtime, so this file holds no literal one (R-07)."""
    return "ADR-%04d" % number


def _hermetic_env(ceiling: str) -> Dict[str, str]:
    """Every GIT_* variable removed (the harness injects core.hooksPath through
    GIT_CONFIG_COUNT, and GIT_DIR would point a `git -C <tmp>` call at the real
    repository), no global or system configuration, a fixed identity."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(
        {
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CEILING_DIRECTORIES": ceiling,
            "GIT_AUTHOR_NAME": "Selftest",
            "GIT_AUTHOR_EMAIL": "selftest@example.invalid",
            "GIT_COMMITTER_NAME": "Selftest",
            "GIT_COMMITTER_EMAIL": "selftest@example.invalid",
        }
    )
    return env


class _Lab:
    """One self-test run: a temporary base directory and the hermetic env."""

    def __init__(self, base_dir: str) -> None:
        self.base_dir = base_dir
        self.env = _hermetic_env(base_dir)
        self.report = []  # type: List[str]

    def sh(self, repo: str, *args: str) -> str:
        done = subprocess.run(
            ["git", "-C", repo, *args],
            capture_output=True,
            text=True,
            env=self.env,
        )
        if done.returncode != 0:
            raise RuntimeError("git %s failed: %s" % (" ".join(args), done.stderr.strip()))
        return done.stdout.strip()

    def cli(self, cwd: str, *args: str) -> Tuple[int, str, str]:
        done = subprocess.run(
            [sys.executable, SCRIPT, *args],
            cwd=cwd,
            capture_output=True,
            text=True,
            env=self.env,
        )
        return done.returncode, done.stdout, done.stderr

    def directory(self, name: str) -> str:
        return tempfile.mkdtemp(prefix=name + "-", dir=self.base_dir)

    def repo(self, name: str, registry: Optional[str] = "concept-to-code workflow") -> str:
        repo = self.directory(name)
        self.sh(repo, "init", "-q", "-b", "main")
        if registry is not None:
            write(repo, README, registry_readme(registry))
        return repo

    def check(self, rid: str, kind: str, ok: bool, description: str) -> None:
        self.report.append("%s: %s %s: %s" % ("ok" if ok else "FAILED", rid, kind, description))


def write(repo: str, relpath: str, content: str) -> None:
    full = os.path.join(repo, relpath)
    os.makedirs(os.path.dirname(full) or repo, exist_ok=True)
    with open(full, "w", encoding="utf-8") as handle:
        handle.write(content)


def registry_readme(phrase: str) -> str:
    return (
        "# Architecture Decision Records\n\n"
        "## 3. A citation says where the ADR lives\n\n"
        "Qualify it.\n\n"
        "%s\n\n"
        "The origins a citation may name.\n\n"
        "| Origin | %s |\n"
        "|---|---|\n"
        "| A retired series | %s |\n\n"
        "## Renumbering register\n" % (REGISTRY_HEADING, PHRASE_COLUMN, phrase)
    )


def adr(repo: str, number: int, slug: str, status: str = "- Status: accepted") -> str:
    relpath = "%s/%04d-%s.md" % (ADR_DIR, number, slug)
    write(repo, relpath, "# %s\n\n%s\n\n## Context\n\nText.\n" % (slug, status))
    return relpath


def commit(lab: _Lab, repo: str, message: str = "change") -> str:
    lab.sh(repo, "add", "-A")
    lab.sh(repo, "commit", "-q", "-m", message)
    return lab.sh(repo, "rev-parse", "HEAD")


def summary_line(out: str) -> str:
    lines = out.strip().splitlines()
    return lines[-1] if lines else ""


def lines_with(out: str, marker: str) -> List[str]:
    return [line for line in out.splitlines() if marker in line]


def findings(out: str, rule: int) -> List[str]:
    """Finding lines of one rule, anchored on `<path>:<line>: `: the summary line
    (`check-adr-references.py: rule 1: 0, …`) also holds `: rule 1: `."""
    pattern = re.compile(r"^\S+:\d+: rule %d: " % rule)
    return [line for line in out.splitlines() if pattern.match(line)]


def _no_traceback(err: str) -> bool:
    return "Traceback" not in err


# R-01


def _scenario_r01(lab: _Lab) -> None:
    repo = lab.repo("r01-pass")
    for number, slug in ((1, "a"), (2, "b"), (3, "c")):
        adr(repo, number, slug)
    commit(lab, repo)
    code, out, _ = lab.cli(repo)
    lab.check("R-01", "pass", code == 0 and "rule 1: 0," in summary_line(out),
              "three ADRs with distinct numbers: exit 0, rule 1: 0")

    repo = lab.repo("r01-fail")
    adr(repo, 2, "a")
    adr(repo, 2, "b")
    commit(lab, repo)
    code, out, _ = lab.cli(repo)
    found = findings(out, 1)
    lab.check("R-01", "fail", code == 1 and len(found) == 1
              and "0002-a.md" in found[0] and "0002-b.md" in found[0],
              "0002-a.md and 0002-b.md: exit 1, one rule 1 line naming both")


# R-02


def _collision_repo(lab: _Lab) -> str:
    """A branch adds 0003-bar.md; main then adds 0003-foo.md."""
    repo = lab.repo("r02-collision")
    adr(repo, 1, "x")
    commit(lab, repo, "base")
    lab.sh(repo, "checkout", "-q", "-b", "feature")
    adr(repo, 3, "bar")
    commit(lab, repo, "branch takes 0003")
    lab.sh(repo, "checkout", "-q", "main")
    adr(repo, 3, "foo")
    commit(lab, repo, "main takes 0003")
    lab.sh(repo, "checkout", "-q", "feature")
    return repo


def _scenario_r02(lab: _Lab) -> None:
    repo = _collision_repo(lab)
    code, out, _ = lab.cli(repo, "--base", "main")
    found = findings(out, 1)
    lab.check("R-02", "fail", code == 1 and len(found) == 1
              and "0003-bar.md" in found[0] and "0003-foo.md" in found[0],
              "branch 0003-bar.md against main's 0003-foo.md, --base main: exit 1 naming both")

    lab.sh(repo, "update-ref", "refs/remotes/origin/main", "main")
    code, out, _ = lab.cli(repo)
    found = findings(out, 1)
    lab.check("R-02", "fail", code == 1 and len(found) == 1 and "0003-foo.md" in found[0],
              "same collision, no --base, refs/remotes/origin/main set: exit 1 (default base)")

    repo = lab.repo("r02-slug-rename")
    adr(repo, 1, "foo")
    commit(lab, repo, "base")
    lab.sh(repo, "checkout", "-q", "-b", "feature")
    lab.sh(repo, "mv", "docs/adr/0001-foo.md", "docs/adr/0001-bar.md")
    commit(lab, repo, "rename the slug")
    code, out, _ = lab.cli(repo, "--base", "main")
    lab.check("R-02", "pass", code == 0 and not findings(out, 1),
              "slug rename 0001-foo.md -> 0001-bar.md of a merge-base number: exit 0")

    repo = lab.repo("r02-renumber")
    adr(repo, 2, "a")
    adr(repo, 2, "b")
    commit(lab, repo, "base holds a duplicate")
    lab.sh(repo, "checkout", "-q", "-b", "feature")
    lab.sh(repo, "mv", "docs/adr/0002-b.md", "docs/adr/0004-b.md")
    commit(lab, repo, "renumber")
    code, out, _ = lab.cli(repo, "--base", "main")
    lab.check("R-02", "pass", code == 0 and not findings(out, 1),
              "git mv 0002-b.md -> 0004-b.md, a number free on the base: exit 0")

    repo = lab.repo("r02-unresolvable")
    adr(repo, 1, "x")
    commit(lab, repo)
    code, out, _ = lab.cli(repo, "--base", "no-such-ref")
    notices = [line for line in out.splitlines() if line.startswith("notice: ")]
    lab.check("R-02", "notice", code == 0 and len(notices) == 1
              and "no-such-ref" in notices[0] and "skipped" in notices[0],
              "clean tree, --base no-such-ref: exit 0, one notice naming the ref, base checks skipped")
    code, out, _ = lab.cli(repo)
    notices = [line for line in out.splitlines() if line.startswith("notice: ")]
    lab.check("R-02", "notice", code == 0 and len(notices) == 1 and "skipped" in notices[0],
              "no remote and no --base: exit 0, one notice, base checks skipped")

    repo = lab.repo("r02-orphan")
    adr(repo, 1, "x")
    commit(lab, repo)
    lab.sh(repo, "checkout", "-q", "--orphan", "other")
    commit(lab, repo, "unrelated history")
    lab.sh(repo, "checkout", "-q", "main")
    code, out, _ = lab.cli(repo, "--base", "other")
    notices = [line for line in out.splitlines() if line.startswith("notice: ")]
    lab.check("R-02", "notice", code == 0 and len(notices) == 1 and "skipped" in notices[0],
              "base on an orphan branch, no merge-base: exit 0, notice")

    repo = lab.repo("r02-unresolvable-duplicate")
    adr(repo, 2, "a")
    adr(repo, 2, "b")
    commit(lab, repo)
    code, out, _ = lab.cli(repo, "--base", "no-such-ref")
    lab.check("R-02", "fail", code == 1 and len(findings(out, 1)) == 1
              and any(line.startswith("notice: ") for line in out.splitlines()),
              "unresolvable base plus an in-tree duplicate: exit 1, the in-tree check decides")


# R-03


def _scenario_r03(lab: _Lab) -> None:
    repo = lab.repo("r03-forms")
    forms = [
        "- Status: accepted",
        "- **Status**: Accepted",
        "- **Status:** Accepted (2026-09-01)",
        "- Status: **accepted**, 2026-09-01",
        "- Status: superseded by the next one",
        "- Status: deprecated",
        "- Status: rejected",
    ]
    for index, form in enumerate(forms, start=1):
        adr(repo, index, "bullet-%d" % index, form)
    write(repo, "docs/adr/0008-section.md",
          "# Section\n\nPreamble.\n\n## Status\n\nAccepted — landed in PR #1.\n\n## Context\n\nText.\n")
    write(repo, "docs/adr/0009-section-branch.md",
          "# Section\n\n## Status\n\naccepted, proposed for the `x` branch\n\n## Context\n\nText.\n")
    commit(lab, repo)
    code, out, _ = lab.cli(repo)
    lab.check("R-03", "pass", code == 0 and "rule 2: 0," in summary_line(out),
              "every bullet form, bold or not, and a first ## Status section: exit 0")

    cases = [
        ("no status line", "# No status\n\n## Context\n\nText.\n"),
        ("- Status: draft", "# Draft\n\n- Status: draft\n\n## Context\n\nText.\n"),
        ("## Context before ## Status",
         "# Late\n\n## Context\n\nText.\n\n## Status\n\nAccepted.\n"),
        ("## Context before a - Status: bullet",
         "# Late bullet\n\n## Context\n\n- Status: accepted\n"),
    ]
    for description, text in cases:
        repo = lab.repo("r03-fail")
        write(repo, "docs/adr/0001-case.md", text)
        commit(lab, repo)
        code, out, _ = lab.cli(repo)
        found = findings(out, 2)
        lab.check("R-03", "fail", code == 1 and len(found) == 1
                  and found[0].startswith("docs/adr/0001-case.md:"),
                  "%s: exit 1, one rule 2 line" % description)


# R-04


def _scenario_r04(lab: _Lab) -> None:
    repo = lab.repo("r04-on-base")
    adr(repo, 1, "x", "- Status: proposed")
    commit(lab, repo, "base")
    lab.sh(repo, "checkout", "-q", "-b", "feature")
    write(repo, "notes.md", "Unrelated.\n")
    commit(lab, repo, "branch")
    code, out, _ = lab.cli(repo, "--base", "main")
    found = findings(out, 2)
    lab.check("R-04", "fail", code == 1 and len(found) == 1 and "proposed" in found[0],
              "an ADR reading proposed on the base, unchanged on the branch: exit 1")

    repo = lab.repo("r04-branch-only")
    adr(repo, 1, "x")
    commit(lab, repo, "base")
    lab.sh(repo, "checkout", "-q", "-b", "feature")
    adr(repo, 2, "y", "- Status: proposed")
    commit(lab, repo, "branch proposes")
    code, out, _ = lab.cli(repo, "--base", "main")
    lab.check("R-04", "pass", code == 0,
              "an ADR reading proposed only on the branch: exit 0")

    repo = lab.repo("r04-flipped")
    adr(repo, 1, "x", "- Status: proposed")
    commit(lab, repo, "base")
    lab.sh(repo, "checkout", "-q", "-b", "feature")
    adr(repo, 1, "x", "- Status: accepted")
    code, out, _ = lab.cli(repo, "--base", "main")
    lab.check("R-04", "pass", code == 0,
              "proposed on the base, accepted in the working tree: exit 0")


# R-05


def _warning_repo(lab: _Lab) -> str:
    repo = lab.repo("r05-warn")
    adr(repo, 1, "x")
    commit(lab, repo, "base")
    lab.sh(repo, "checkout", "-q", "-b", "feature")
    write(repo, "notes.md", "Branch work.\n")
    branch_commit = commit(lab, repo, "branch only")
    adr(repo, 2, "y",
        "- Status: accepted. Landed via PR #3 (merge `%s`, 2026-09-01),\n"
        "  and not `fedcba9876543210fedcba9876543210fedcba98`." % branch_commit[:12])
    return repo


def _scenario_r05(lab: _Lab) -> None:
    repo = _warning_repo(lab)
    code, out, _ = lab.cli(repo, "--base", "main")
    warnings = lines_with(out, ": warning (rule 2): ")
    lab.check("R-05", "warn", code == 0 and len(warnings) == 2
              and not findings(out, 2)
              and warnings[1].startswith("docs/adr/0002-y.md:4:"),
              "a branch-only commit and a hash that is no commit in a status line: "
              "two warnings, exit 0")

    repo = lab.repo("r05-pass")
    adr(repo, 1, "x")
    base_commit = commit(lab, repo, "base")
    lab.sh(repo, "checkout", "-q", "-b", "feature")
    write(repo, "notes.md", "Branch work.\n")
    branch_commit = commit(lab, repo, "branch only")
    adr(repo, 2, "y",
        "- Status: accepted. Landed via PR #1 (merge `%s`, 2026-09-01).\n"
        "- Date: 2026-09-01, written against `%s`." % (base_commit[:12], branch_commit[:12]))
    code, out, _ = lab.cli(repo, "--base", "main")
    lab.check("R-05", "pass", code == 0 and not lines_with(out, ": warning (rule 2): "),
              "a first-parent commit of the base in the status line, a branch commit in "
              "- Date:: no warning, exit 0")

    repo = _warning_repo(lab)
    adr(repo, 3, "dup")
    adr(repo, 3, "dup-again")
    code, out, _ = lab.cli(repo, "--base", "main")
    lab.check("R-05", "fail", code == 1 and len(lines_with(out, ": warning (rule 2): ")) == 2,
              "warnings plus an R-01 duplicate: exit 1, the warnings still printed")


# R-06


def _rule3_repo(lab: _Lab, name: str, files: Dict[str, str]) -> Tuple[int, str]:
    repo = lab.repo(name)
    adr(repo, 1, "held")
    for relpath, text in files.items():
        write(repo, relpath, text)
    commit(lab, repo)
    code, out, _ = lab.cli(repo)
    return code, out


def _scenario_r06(lab: _Lab) -> None:
    code, out = _rule3_repo(lab, "r06-bare", {
        "notes.md": "# Notes\n\nA paragraph that follows\n%s for its rule.\n" % cite(155),
    })
    found = findings(out, 3)
    lab.check("R-06", "fail", code == 1 and len(found) == 1 and found[0].startswith("notes.md:4:"),
              "an unqualified first citation of an unheld number: exit 1, at its line")

    code, out = _rule3_repo(lab, "r06-wrap", {
        "notes.md": "We follow %s of the retired\nConcept-To-Code\nWorkflow here.\n" % cite(155),
    })
    lab.check("R-06", "pass", code == 0,
              "the qualifier in the same sentence across line wraps, another case: exit 0")

    code, out = _rule3_repo(lab, "r06-comments", {
        "a.swift": "struct A {\n    /// See %s of the retired concept-to-code\n"
                   "    /// workflow for the rule.\n    let a = 1\n}\n" % cite(155),
        "b.swift": "// Per %s of the concept-to-code\n//   workflow, nothing else.\n" % cite(156),
        "c.py": "x = 1\n# Per %s of the concept-to-code\n# workflow.\n" % cite(157),
        "d.sh": "#!/usr/bin/env bash\n# Per %s of the\n#   concept-to-code workflow.\n" % cite(158),
        "e.yml": "name: x\n# Per %s, of the concept-to-code\n# workflow.\non: push\n" % cite(159),
    })
    lab.check("R-06", "pass", code == 0,
              "the qualifier across a wrap of ///, // (.swift) and # (.py, .sh, .yml): exit 0")

    code, out = _rule3_repo(lab, "r06-next-sentence", {
        "notes.md": "We follow %s here. It comes from the concept-to-code workflow.\n" % cite(155),
    })
    lab.check("R-06", "fail", code == 1 and len(findings(out, 3)) == 1,
              "the qualifier only in the next sentence: exit 1")

    code, out = _rule3_repo(lab, "r06-next-item", {
        "notes.md": "- %s is the rule\n- the concept-to-code workflow wrote it\n" % cite(155),
    })
    lab.check("R-06", "fail", code == 1 and len(findings(out, 3)) == 1,
              "the qualifier only in the next list item: exit 1")

    code, out = _rule3_repo(lab, "r06-first-qualified", {
        "notes.md": "First %s of the concept-to-code workflow.\n\nThen %s again.\n"
                    % (cite(155), cite(155)),
    })
    lab.check("R-06", "pass", code == 0, "first citation qualified, the second bare: exit 0")

    code, out = _rule3_repo(lab, "r06-first-bare", {
        "notes.md": "First %s bare.\n\nThen %s of the concept-to-code workflow.\n"
                    % (cite(155), cite(155)),
    })
    found = findings(out, 3)
    lab.check("R-06", "fail", code == 1 and len(found) == 1 and found[0].startswith("notes.md:1:"),
              "first citation bare, the second qualified: exit 1, at the first's line")

    code, out = _rule3_repo(lab, "r06-held", {
        "notes.md": "The rule is %s, bare.\n" % cite(1),
        "other.md": "The rule is %s of the concept-to-code workflow.\n" % cite(1),
    })
    lab.check("R-06", "pass", code == 0,
              "a held number cited bare, and qualified in another file: exit 0")


# R-07


def _scenario_r07(lab: _Lab) -> None:
    repo = lab.repo("r07-scanned-set")
    bare = "See %s for the rule.\n" % cite(155)
    comment = {"swift": "// ", "py": "# ", "sh": "# ", "yml": "# ", "yaml": "# ", "md": ""}
    for suffix, marker in comment.items():
        write(repo, "src/file.%s" % suffix, marker + bare)
    write(repo, "docs/TODO.md", bare)
    write(repo, "notes.txt", bare)
    write(repo, "TODO.md", bare)
    write(repo, "SPEC.md", bare)
    commit(lab, repo)
    write(repo, "extra.md", bare)
    code, out, _ = lab.cli(repo)
    found = findings(out, 3)
    skipped = ("notes.txt:", "TODO.md:", "SPEC.md:", "extra.md:")
    lab.check("R-07", "fail", code == 1 and len(found) == 7
              and not [line for line in found if line.startswith(skipped)],
              "one bare citation per scanned suffix and in docs/TODO.md: exactly 7 rule 3 "
              "lines, none for notes.txt, root TODO.md, root SPEC.md or untracked extra.md")

    repo = lab.repo("r07-own-file")
    adr(repo, 1, "x")
    os.makedirs(os.path.join(repo, "scripts"))
    shutil.copy2(SCRIPT, os.path.join(repo, "scripts", PROG))
    commit(lab, repo)
    code, out, _ = lab.cli(repo)
    lab.check("R-07", "pass", code == 0
              and not [line for line in out.splitlines() if line.startswith("scripts/" + PROG)],
              "this script, copied and committed: exit 0, no line names it")


# R-08


def _scenario_r08(lab: _Lab) -> None:
    broken = [
        ("no docs/adr/README.md", None),
        ("a README without the heading", "# Architecture Decision Records\n\nNothing here.\n"),
        ("the heading with no data row",
         "%s\n\n| Origin | %s |\n|---|---|\n\n## Next\n" % (REGISTRY_HEADING, PHRASE_COLUMN)),
        ("an empty phrase cell",
         "%s\n\n| Origin | %s |\n|---|---|\n| A series |  |\n" % (REGISTRY_HEADING, PHRASE_COLUMN)),
        ("no %s column" % PHRASE_COLUMN,
         "%s\n\n| Origin | Phrase |\n|---|---|\n| A series | a phrase |\n" % REGISTRY_HEADING),
    ]
    for description, readme in broken:
        repo = lab.repo("r08-broken", registry=None)
        adr(repo, 1, "x")
        if readme is not None:
            write(repo, README, readme)
        commit(lab, repo)
        code, out, err = lab.cli(repo)
        lab.check("R-08", "fail", code == 2 and "%s: error: " % PROG in err and _no_traceback(err),
                  "%s: exit 2, an error on stderr, no traceback" % description)

    repo = lab.repo("r08-other-series", registry="`other series`")
    adr(repo, 1, "x")
    write(repo, "notes.md", "We follow %s of the Other\nSeries here.\n" % cite(155))
    commit(lab, repo)
    code, out, _ = lab.cli(repo)
    lab.check("R-08", "pass", code == 0,
              "registry phrase `other series`, a citation qualified with Other/Series: exit 0")

    write(repo, "notes.md", "We follow %s of the concept-to-code workflow here.\n" % cite(155))
    code, out, _ = lab.cli(repo)
    lab.check("R-08", "fail", code == 1 and len(findings(out, 3)) == 1,
              "same registry, a citation qualified only with a phrase it does not list: exit 1")

    repo = lab.repo("r08-broken-duplicate", registry=None)
    write(repo, README, "# Architecture Decision Records\n")
    adr(repo, 2, "a")
    adr(repo, 2, "b")
    commit(lab, repo)
    code, out, err = lab.cli(repo)
    lab.check("R-08", "fail", code == 2 and len(findings(out, 1)) == 1
              and _no_traceback(err),
              "a broken registry plus an in-tree duplicate: exit 2, the rule 1 line still printed")


# CLI


def _scenario_cli(lab: _Lab) -> None:
    repo = lab.repo("cli")
    adr(repo, 1, "x")
    commit(lab, repo)
    code, _, err = lab.cli(repo, "--self-test", "--verbose")
    lab.check("CLI", "fail", code == 2 and _no_traceback(err), "--self-test --verbose: exit 2")
    code, _, err = lab.cli(repo, "--no-such-option")
    lab.check("CLI", "fail", code == 2 and _no_traceback(err), "an unknown option: exit 2")
    plain = lab.directory("not-a-repository")
    code, _, err = lab.cli(plain)
    lab.check("CLI", "fail", code == 2 and "%s: error: " % PROG in err and _no_traceback(err),
              "a directory that is not a git repository: exit 2")


SCENARIOS = (
    _scenario_r01,
    _scenario_r02,
    _scenario_r03,
    _scenario_r04,
    _scenario_r05,
    _scenario_r06,
    _scenario_r07,
    _scenario_r08,
    _scenario_cli,
)


def self_test() -> int:
    tmp = tempfile.mkdtemp(prefix=SELFTEST_PREFIX)
    lab = _Lab(tmp)
    try:
        for scenario in SCENARIOS:
            try:
                scenario(lab)
            except Exception as error:  # a broken fixture is a red scenario, not a traceback
                lab.report.append("FAILED: %s: fixture error: %s" % (scenario.__name__, error))
    finally:
        # Guard: never remove anything outside our own temporary directory.
        if tmp.startswith(tempfile.gettempdir()) and os.path.basename(tmp).startswith(
            SELFTEST_PREFIX
        ):
            shutil.rmtree(tmp, ignore_errors=True)

    failed = [line for line in lab.report if line.startswith("FAILED")]
    print("%s --self-test: %d checks, %d failed" % (PROG, len(lab.report), len(failed)))
    print("\n".join(lab.report))
    return 1 if failed else 0


# --- CLI -----------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=PROG,
        description="Check the three rules of docs/adr/README.md on the working tree.",
    )
    parser.add_argument(
        "--base",
        help="the ref the branch will land on (default: %s, when it resolves)" % DEFAULT_BASE,
    )
    parser.add_argument("--verbose", action="store_true", help="print the base, merge-base, "
                        "scanned file count and qualifying phrases")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run the scenarios in throwaway repositories; touches no repository",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if "--self-test" in argv:
        if len(argv) != 1:
            print("%s: error: --self-test does not combine with other arguments" % PROG,
                  file=sys.stderr)
            return 2
        return self_test()
    args = build_parser().parse_args(argv)
    try:
        return run(os.getcwd(), args.base, args.verbose)
    except UsageError as error:
        print("%s: error: %s" % (PROG, error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
