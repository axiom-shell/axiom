#!/usr/bin/env python3
"""The checks job's summary: one Markdown page of what each check found.

Runs the quick checks again (each takes under a second; the job's own steps
still fail on them) and prints, as Markdown:
  - an overview table: each check, passed / failed / warnings, and counts
  - each finding as a row (where, linked to the file at this commit, and
    what), errors shown, warnings folded
  - the docs describing what this change touches (with --changed-from) and
    the doc drift table (check_doc_drift.py --markdown)

  scripts/ci_summary.py [--changed-from REF] >> "$GITHUB_STEP_SUMMARY"

--changed-from REF lists the files changed between REF and HEAD (a pull
request's merge commit: HEAD^1). Links need GITHUB_SERVER_URL,
GITHUB_REPOSITORY and GITHUB_SHA (set on CI); without them, paths are code.
Always exits 0: it reports, the steps fail.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PASS, FAIL, WARN = "✅", "❌", "⚠️"
# "path:line: message" or "path: message", as check_structure and check_docs print
LOCATED = re.compile(r"^((?:[\w.-]+/)*[\w.-]+\.\w+)(?::(\d+))?:\s+(.*)$")


def run(*command):
    done = subprocess.run([sys.executable, *command], cwd=ROOT, capture_output=True, text=True)
    return done.returncode, (done.stdout + done.stderr).splitlines()


def link(path, line=None):
    server, repo, sha = (os.environ.get(k) for k in ("GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_SHA"))
    label = f"`{path}:{line}`" if line else f"`{path}`"
    if not (server and repo and sha) or not (ROOT / path).exists():
        return label
    return f"[{label}]({server}/{repo}/blob/{sha}/{path}" + (f"#L{line}" if line else "") + ")"


def cell(text):
    return text.replace("|", "\\|").replace("\n", " ")


def finding(level, text):
    """(level, where, what) from one reported line"""
    m = LOCATED.match(text.strip())
    if m:
        return level, link(m.group(1), m.group(2)), m.group(3)
    return level, "", text.strip()


# Each check: its name, then (status, summary text, findings)

def leveled(script):
    """check_structure / check_docs: `error    …` and `warning  …` lines"""
    code, lines = run(script)
    found = [finding(m.group(1), m.group(2)) for m in (re.match(r"^(error|warning)\s+(.*)$", line) for line in lines) if m]
    errors = sum(1 for f in found if f[0] == "error")
    warnings = len(found) - errors
    if code != 0:
        return FAIL, counted(errors, warnings) or "failed", found or [("error", "", line) for line in lines[-5:]]
    return (WARN if warnings else PASS), counted(errors, warnings) or "ok", found


def contract():
    """gen_docs.py: the shell's daemon calls and listeners the daemon doesn't
    define, one indented line each (the docs themselves are built, not checked)"""
    code, lines = run("scripts/gen_docs.py")
    found = [("error", link("docs/dev/generated/rpc.md"), line.strip()) for line in lines if line.startswith("  ")]
    if code != 0:
        return FAIL, f"{len(found)} disagreements" if found else "failed", found or [("error", "", line) for line in lines[-5:]]
    return PASS, "ok", []


def translations():
    code, lines = run("scripts/check_i18n.py")
    found, parts, language = [], [], ""
    for line in lines:
        header = re.match(r"^(\S+\.json): (\d+)/(\d+) translated, (\d+) missing, (\d+) unused", line)
        if header:
            language = header.group(1)
            missing, unused = int(header.group(4)), int(header.group(5))
            if missing or unused:
                parts.append(f"{language}: {missing} missing, {unused} unused")
            continue
        entry = re.match(r"^\s+(missing|unused|format)\s+(.*)$", line)
        if entry:
            found.append(("warning", link(f"config/i18n/{language}"), f"{entry.group(1)}: {entry.group(2)}"))
            if entry.group(1) == "format":
                parts.append(f"{language}: not in the canonical format")
    # Missing entries fall back to English: the step only warns
    return (WARN if code != 0 or found else PASS), "; ".join(parts) or "complete", found


def counted(errors, warnings):
    return ", ".join(f"{n} {word}{'s' if n != 1 else ''}" for n, word in ((errors, "error"), (warnings, "warning")) if n)


CHECKS = [
    ("Structure (`check_structure.py`)", lambda: leveled("scripts/check_structure.py")),
    ("Shell and daemon agree (`gen_docs.py`)", contract),
    ("Docs match the code (`check_docs.py`)", lambda: leveled("scripts/check_docs.py")),
    ("Package lists agree (`check_packages.py`)", lambda: leveled("scripts/check_packages.py")),
    ("Translations (`check_i18n.py`)", translations),
]


def findings_table(rows):
    out = ["| | Where | What |", "|---|---|---|"]
    for level, where, what in rows:
        out.append(f"| {FAIL if level == 'error' else WARN} | {where} | {cell(what)} |")
    return out


def changed_files(ref):
    done = subprocess.run(["git", "diff", "--name-only", ref, "HEAD"], cwd=ROOT, capture_output=True, text=True)
    return done.stdout.splitlines() if done.returncode == 0 else None


def main(argv):
    ref = None
    if argv[:1] == ["--changed-from"] and len(argv) == 2:
        ref = argv[1]
    elif argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    results = [(name, *check()) for name, check in CHECKS]
    out = ["## Checks", "", "| Check | Result | |", "|---|:-:|---|"]
    out += [f"| {name} | {status} | {cell(summary)} |" for name, status, summary, _ in results]
    out.append("")
    for name, status, _, found in results:
        if not found:
            continue
        errors = [f for f in found if f[0] == "error"]
        warnings = [f for f in found if f[0] != "error"]
        out.append(f"### {status} {name}")
        out.append("")
        if errors:
            out += findings_table(errors) + [""]
        if warnings:
            out += [f"<details><summary>{len(warnings)} warning{'s' if len(warnings) != 1 else ''}</summary>", ""]
            out += findings_table(warnings) + ["", "</details>", ""]

    if ref:
        files = changed_files(ref)
        if files:
            out.append(subprocess.run([sys.executable, "scripts/check_doc_drift.py", "--markdown", "--changed", *files],
                                      cwd=ROOT, capture_output=True, text=True).stdout)
    out.append(subprocess.run([sys.executable, "scripts/check_doc_drift.py", "--markdown"],
                              cwd=ROOT, capture_output=True, text=True).stdout)
    print("\n".join(out).rstrip() + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
