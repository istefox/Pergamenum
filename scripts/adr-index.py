#!/usr/bin/env python3
"""Print or check CLAUDE.md's `## ADR index` against the ADR files' own headings.

PG-397: PR #930 built the index with a throwaway shell loop over the headings of
`docs/adr/0*.md`, and nothing kept it in step afterwards, so a new ADR left it
one line short. This command is that loop, kept in the repository.

Every `docs/adr/NNNN-<slug>.md` gives one line, `- ADR-NNNN — <title>`, in file
name order. The title is the file's first line, a heading in either of the two
shapes the directory uses: `# ADR-NNNN: <title>` or `# ADR-NNNN — <title>`. A
first line in neither shape, or naming a number other than the file's own, is a
file the index cannot be built from.

- With no option, the index lines are printed, ready to replace the bullets
  under CLAUDE.md's `## ADR index`.
- With `--check`, the bullets under that heading (up to the next `#` or `##`
  heading) are compared with the lines the files give: a line no file gives is
  stale, a line no bullet holds is missing, and the same lines in another order
  are out of order.

Usage:
    scripts/adr-index.py [--check]
    scripts/adr-index.py --self-test

Exit: 0 printed, or in step; 1 out of step (`--check` only); 2 an index that
could not be built or read (bad usage, not a git repository, no ADR directory, a
heading in neither shape, no `## ADR index` section).
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from typing import Dict, List, Optional, Tuple

ADR_DIR = "docs/adr"
INSTRUCTIONS = "CLAUDE.md"
INDEX_HEADING = "## ADR index"

PROG = "adr-index.py"

ADR_NAME = re.compile(r"^(\d{4})-.+\.md$")
# The two heading shapes in use: a colon (most ADRs) or a spaced em dash (ADR-0023, 0024, 0026).
ADR_HEADING = re.compile(r"^# ADR-(\d{4})(?:: | — )(.+)$")
# The section ends at the next top- or second-level heading, so a bullet of a later section is
# never read as an index line.
SECTION_END = re.compile(r"^##? ")


class UsageError(Exception):
    """An index that cannot be built or read: reported on stderr, exit 2, never a traceback."""


def repository_root(cwd: str) -> str:
    """The top of the git working tree holding `cwd`.

    Args:
        cwd: the directory the command was started in.

    Returns:
        The absolute path of the working tree's top level.

    Raises:
        UsageError: git cannot run, or `cwd` is not inside a git repository.
    """
    try:
        done = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise UsageError("cannot run git: %s" % error)
    root = done.stdout.strip()
    if done.returncode != 0 or not root:
        raise UsageError("%s is not inside a git repository" % cwd)
    return root


def read_lines(root: str, relpath: str) -> List[str]:
    """The lines of a working-tree file, without their line endings.

    Raises:
        UsageError: the file is missing or cannot be decoded as UTF-8.
    """
    try:
        with open(os.path.join(root, relpath), encoding="utf-8") as handle:
            return handle.read().splitlines()
    except (OSError, UnicodeDecodeError) as error:
        raise UsageError("cannot read %s: %s" % (relpath, error))


def index_lines(root: str) -> List[str]:
    """One `- ADR-NNNN — <title>` line per ADR file, in file name order.

    Args:
        root: the repository's top level.

    Returns:
        The index lines the ADR files give.

    Raises:
        UsageError: no ADR directory, no ADR file, or a file whose first line is
            not a heading of either shape for its own number.
    """
    directory = os.path.join(root, ADR_DIR)
    try:
        names = sorted(name for name in os.listdir(directory) if ADR_NAME.match(name))
    except OSError as error:
        raise UsageError("cannot list %s: %s" % (ADR_DIR, error))
    if not names:
        raise UsageError("%s holds no NNNN-<slug>.md file" % ADR_DIR)
    lines = []  # type: List[str]
    for name in names:
        relpath = "%s/%s" % (ADR_DIR, name)
        number = name[:4]  # ADR_NAME matched: four digits, then the slug
        content = read_lines(root, relpath)
        first = content[0] if content else ""
        heading = ADR_HEADING.match(first)
        if heading is None:
            raise UsageError("%s:1: the first line is not `# ADR-NNNN: <title>` or "
                             "`# ADR-NNNN — <title>`" % relpath)
        if heading.group(1) != number:
            # The index line is built from the heading, so a heading that names another number
            # would put the wrong ADR in the index without anything saying so.
            raise UsageError("%s:1: the heading names ADR-%s, the file name %s"
                             % (relpath, heading.group(1), number))
        lines.append("- ADR-%s — %s" % (number, heading.group(2).rstrip()))
    return lines


def indexed_lines(root: str) -> Tuple[int, List[Tuple[int, str]]]:
    """The bullets under CLAUDE.md's `## ADR index`, with their 1-based line numbers.

    Every bullet of the section counts, not only those starting `- ADR-`: a bullet
    written in another shape is a line no file gives, reported as stale.

    Returns:
        The heading's 1-based line number, and the section's bullets.

    Raises:
        UsageError: CLAUDE.md cannot be read or holds no `## ADR index` heading.
    """
    content = read_lines(root, INSTRUCTIONS)
    try:
        start = content.index(INDEX_HEADING)
    except ValueError:
        raise UsageError("%s has no `%s` section" % (INSTRUCTIONS, INDEX_HEADING))
    bullets = []  # type: List[Tuple[int, str]]
    for offset, line in enumerate(content[start + 1:], start=start + 2):
        if SECTION_END.match(line):
            break
        if line.startswith("- "):
            bullets.append((offset, line.rstrip()))
    return start + 1, bullets


def compare(expected: List[str], heading: int, actual: List[Tuple[int, str]]) -> List[str]:
    """The differences between the lines the files give and the bullets CLAUDE.md holds.

    Counted as multisets, so a bullet written twice is reported once as stale.

    Args:
        expected: the lines `index_lines` builds.
        heading: the 1-based line number of the `## ADR index` heading.
        actual: the bullets `indexed_lines` reads, with their line numbers.

    Returns:
        One message per difference, `CLAUDE.md:<line>: <what>`; empty when in step.
    """
    held = [line for _, line in actual]
    missing = Counter(expected) - Counter(held)
    unclaimed = Counter(expected)
    found = []  # type: List[str]
    for number, line in actual:
        # The first bullet of a line claims it, so a duplicate is reported where it was added.
        if unclaimed[line] > 0:
            unclaimed[line] -= 1
            continue
        found.append("%s:%d: stale, no ADR file gives this line: %s"
                     % (INSTRUCTIONS, number, line))
    # A missing line has no line number of its own; it is reported at the section's last
    # bullet, or at the heading's next line when the section holds none.
    anchor = actual[-1][0] if actual else heading + 1
    for line in expected:
        if missing[line] > 0:
            missing[line] -= 1
            found.append("%s:%d: missing: %s" % (INSTRUCTIONS, anchor, line))
    if not found and held != expected:
        for (number, line), wanted in zip(actual, expected):
            if line != wanted:
                found.append("%s:%d: out of order, expected here: %s"
                             % (INSTRUCTIONS, number, wanted))
                break
    return found


def run(cwd: str, check: bool) -> int:
    root = repository_root(cwd)
    expected = index_lines(root)
    if not check:
        print("\n".join(expected))
        return 0
    heading, bullets = indexed_lines(root)
    found = compare(expected, heading, bullets)
    for line in found:
        print(line)
    print("%s: %d ADR files, %d differences" % (PROG, len(expected), len(found)))
    return 1 if found else 0


# --- self-test ---------------------------------------------------------------------

SELFTEST_PREFIX = "pergamenum-adr-index-selftest-"
SCRIPT = os.path.abspath(__file__)


def _hermetic_env(ceiling: str) -> Dict[str, str]:
    """Every GIT_* variable removed (GIT_DIR would point a `git -C <tmp>` call at the
    real repository), no global or system configuration, and a ceiling so a plain
    directory under the lab is not read as part of a repository above it."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(
        {
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CEILING_DIRECTORIES": ceiling,
        }
    )
    return env


class _Lab:
    """One self-test run: a temporary base directory and the hermetic env."""

    def __init__(self, base_dir: str) -> None:
        self.base_dir = base_dir
        self.env = _hermetic_env(base_dir)
        self.report = []  # type: List[str]

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

    def repo(self, name: str) -> str:
        repo = self.directory(name)
        done = subprocess.run(["git", "-C", repo, "init", "-q"], capture_output=True,
                              text=True, env=self.env)
        if done.returncode != 0:
            raise RuntimeError("git init failed: %s" % done.stderr.strip())
        return repo

    def check(self, rid: str, kind: str, ok: bool, description: str) -> None:
        self.report.append("%s: %s %s: %s" % ("ok" if ok else "FAILED", rid, kind, description))


def write(repo: str, relpath: str, content: str) -> None:
    full = os.path.join(repo, relpath)
    os.makedirs(os.path.dirname(full) or repo, exist_ok=True)
    with open(full, "w", encoding="utf-8") as handle:
        handle.write(content)


def adr(repo: str, number: int, slug: str, heading: str) -> None:
    write(repo, "%s/%04d-%s.md" % (ADR_DIR, number, slug), "%s\n\n- Status: accepted\n" % heading)


def instructions(repo: str, bullets: List[str], after: str = "") -> None:
    write(repo, INSTRUCTIONS, "# CLAUDE.md\n\n## Stack\n\n- Swift 6\n\n%s\n\nEvery ADR.\n\n%s\n%s"
          % (INDEX_HEADING, "".join(b + "\n" for b in bullets), after))


COLON = "- ADR-0001 — First decision"
DASH = "- ADR-0002 — Second decision"
THIRD = "- ADR-0003 — Third decision"


def _two_shapes(lab: _Lab, name: str) -> str:
    """Two ADRs, one per heading shape, with a README the file filter must skip."""
    repo = lab.repo(name)
    adr(repo, 1, "first", "# ADR-0001: First decision")
    adr(repo, 2, "second", "# ADR-0002 — Second decision")
    write(repo, "%s/README.md" % ADR_DIR, "# Architecture Decision Records\n")
    return repo


def _no_traceback(err: str) -> bool:
    return "Traceback" not in err


# S-01: print and check in step


def _scenario_s01(lab: _Lab) -> None:
    repo = _two_shapes(lab, "s01")
    instructions(repo, [COLON, DASH])
    code, out, _ = lab.cli(repo)
    lab.check("S-01", "pass", code == 0 and out.splitlines() == [COLON, DASH],
              "both heading shapes print as `- ADR-NNNN — title`, README skipped")
    code, out, _ = lab.cli(repo, "--check")
    lab.check("S-01", "pass", code == 0 and "0 differences" in out, "an index in step: exit 0")
    sub = os.path.join(repo, ADR_DIR)
    code, out, _ = lab.cli(sub, "--check")
    lab.check("S-01", "pass", code == 0, "run from a subdirectory: the repository root is used")


# S-02: a new ADR without its line


def _scenario_s02(lab: _Lab) -> None:
    repo = _two_shapes(lab, "s02")
    adr(repo, 3, "third", "# ADR-0003: Third decision")
    instructions(repo, [COLON, DASH])
    code, out, _ = lab.cli(repo, "--check")
    missing = [line for line in out.splitlines() if ": missing: " in line]
    lab.check("S-02", "fail",
              code == 1 and missing == ["%s:12: missing: %s" % (INSTRUCTIONS, THIRD)],
              "a new ADR the index lacks: exit 1, one missing line at the last bullet")
    instructions(repo, [])
    code, out, _ = lab.cli(repo, "--check")
    missing = [line for line in out.splitlines() if ": missing: " in line]
    lab.check("S-02", "fail",
              code == 1 and missing == ["%s:8: missing: %s" % (INSTRUCTIONS, line)
                                        for line in (COLON, DASH, THIRD)],
              "a section with no bullets: every line missing, at the heading's next line")


# S-03: a retitled ADR, a removed ADR, a duplicated bullet


def _scenario_s03(lab: _Lab) -> None:
    repo = _two_shapes(lab, "s03")
    instructions(repo, ["- ADR-0001 — Old title", DASH, DASH, THIRD])
    code, out, _ = lab.cli(repo, "--check")
    stale = [line for line in out.splitlines() if ": stale, " in line]
    missing = [line for line in out.splitlines() if ": missing: " in line]
    at = ["%s:%d: " % (INSTRUCTIONS, number) for number in (11, 13, 14)]
    lab.check("S-03", "fail", code == 1 and len(stale) == 3
              and all(line.startswith(prefix) for line, prefix in zip(stale, at))
              and missing == ["%s:14: missing: %s" % (INSTRUCTIONS, COLON)],
              "an old title, the second copy of a line and a removed ADR are stale, "
              "the new title missing")


# S-04: the same lines in another order


def _scenario_s04(lab: _Lab) -> None:
    repo = _two_shapes(lab, "s04")
    instructions(repo, [DASH, COLON])
    code, out, _ = lab.cli(repo, "--check")
    lab.check("S-04", "fail", code == 1 and "%s:11: out of order, expected here: %s"
              % (INSTRUCTIONS, COLON) in out, "swapped lines: exit 1, out of order")


# S-05: the section ends at the next heading


def _scenario_s05(lab: _Lab) -> None:
    repo = _two_shapes(lab, "s05")
    instructions(repo, [COLON, DASH], after="\n## Later\n\n- a bullet of another section\n")
    code, _, _ = lab.cli(repo, "--check")
    lab.check("S-05", "pass", code == 0, "a bullet under the next `##` heading is not read")
    instructions(repo, [COLON])
    code, out, _ = lab.cli(repo, "--check")
    lab.check("S-05", "fail", code == 1 and "missing: %s" % DASH in out,
              "an index section at the end of the file is read to the end")


# S-06: files the index cannot be built from


def _scenario_s06(lab: _Lab) -> None:
    repo = _two_shapes(lab, "s06")
    adr(repo, 3, "third", "# Third decision")
    instructions(repo, [COLON, DASH])
    for args in ((), ("--check",)):
        code, out, err = lab.cli(repo, *args)
        lab.check("S-06", "fail", code == 2 and "0003-third.md:1: " in err and out == ""
                  and _no_traceback(err), "a heading in neither shape %s: exit 2, nothing printed"
                  % (" ".join(args) or "(print)"))
    repo = _two_shapes(lab, "s06-number")
    adr(repo, 3, "third", "# ADR-0004: Third decision")
    code, _, err = lab.cli(repo)
    lab.check("S-06", "fail", code == 2 and "names ADR-0004" in err and _no_traceback(err),
              "a heading naming another number: exit 2")
    repo = lab.repo("s06-empty")
    code, _, err = lab.cli(repo)
    lab.check("S-06", "fail", code == 2 and _no_traceback(err), "no ADR directory: exit 2")


# S-07: no index section


def _scenario_s07(lab: _Lab) -> None:
    repo = _two_shapes(lab, "s07")
    write(repo, INSTRUCTIONS, "# CLAUDE.md\n\n## Stack\n\n- Swift 6\n")
    code, _, err = lab.cli(repo, "--check")
    lab.check("S-07", "fail", code == 2 and "no `%s` section" % INDEX_HEADING in err
              and _no_traceback(err), "CLAUDE.md without the section: --check exits 2")
    code, _, _ = lab.cli(repo)
    lab.check("S-07", "pass", code == 0, "printing does not read CLAUDE.md")


# CLI


def _scenario_cli(lab: _Lab) -> None:
    repo = _two_shapes(lab, "cli")
    instructions(repo, [COLON, DASH])
    code, _, err = lab.cli(repo, "--self-test", "--check")
    lab.check("CLI", "fail", code == 2 and _no_traceback(err), "--self-test --check: exit 2")
    code, _, err = lab.cli(repo, "--no-such-option")
    lab.check("CLI", "fail", code == 2 and _no_traceback(err), "an unknown option: exit 2")
    code, out, err = lab.cli(repo, "--chec")
    lab.check("CLI", "fail", code == 2 and out == "" and _no_traceback(err),
              "--chec, an abbreviation of --check: exit 2, nothing printed")
    plain = lab.directory("not-a-repository")
    code, _, err = lab.cli(plain)
    lab.check("CLI", "fail", code == 2 and "%s: error: " % PROG in err and _no_traceback(err),
              "a directory that is not a git repository: exit 2")


SCENARIOS = (
    _scenario_s01,
    _scenario_s02,
    _scenario_s03,
    _scenario_s04,
    _scenario_s05,
    _scenario_s06,
    _scenario_s07,
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
        description="Print CLAUDE.md's ADR index from the headings of docs/adr/, or check it.",
        # A prefix such as `--chec` must not print the index and exit 0 as if a check
        # passed (the PG-291 lesson of check-adr-references.py): long options match exactly.
        allow_abbrev=False,
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare the bullets under CLAUDE.md's `%s` with the files; exit 1 when out of step"
        % INDEX_HEADING,
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run the scenarios in throwaway directories; touches no repository",
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
        return run(os.getcwd(), args.check)
    except UsageError as error:
        print("%s: error: %s" % (PROG, error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
