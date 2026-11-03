#!/usr/bin/env python3
"""Flag hand-written docs that may have drifted from the code they describe.

A doc in docs/dev/ lists its files in its `> **Files:**` header. When those
files have changed in many commits since the doc itself last changed, the
doc probably describes an older version of them: reread it against the code
(and touch it, even only to confirm it, to reset the count).

  scripts/check_doc_drift.py                  docs at or past the threshold
  scripts/check_doc_drift.py --min N          threshold (default 5 commits)
  scripts/check_doc_drift.py --all            every doc, with its count
  scripts/check_doc_drift.py --changed F...   docs whose files include any
                                              of F but which aren't among F
                                              themselves (verify.sh: what you
                                              changed is described there)
  --markdown (with any of the above)          Markdown tables instead, for
                                              CI's job summary; docs link to
                                              the commit when GITHUB_* is set

Warnings only: always exits 0. check_docs.py checks that cited paths exist;
this checks that the doc was read since they last changed. Commits are
counted with --no-merges; a directory in Files counts commits under it.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs/dev"
GENERATED = ("docs/dev/generated/", "docs/dev/config/")
FILES_LINE = re.compile(r"^> \*\*Files:\*\*(.*)$", re.M)
CITED = re.compile(r"`([\w./-]+)`")


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def docs():
    """{doc path: [the files and dirs its Files header lists]}"""
    out = {}
    for path in sorted(DOCS.rglob("*.md")):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(GENERATED):
            continue
        match = FILES_LINE.search(path.read_text())
        if not match:
            continue
        cited = [c.rstrip("/") for c in CITED.findall(match.group(1))]
        cited = [c for c in cited if (ROOT / c).exists()]
        if cited:
            out[rel] = cited
    return out


def drift(doc, files):
    """(commits touching `files` since `doc` last changed, the newest one's subject)"""
    since = git("log", "-1", "--format=%H", "--", doc)
    span = f"{since}..HEAD" if since else "HEAD"
    commits = git("rev-list", "--no-merges", span, "--", *files).split()
    subject = git("log", "-1", "--format=%s", commits[0]) if commits else ""
    return len(commits), subject


def link(doc):
    """doc as a Markdown link to it at this commit, on CI; else as code"""
    server, repo, sha = (os.environ.get(k) for k in ("GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_SHA"))
    return f"[`{doc}`]({server}/{repo}/blob/{sha}/{doc})" if server and repo and sha else f"`{doc}`"


def cell(text):
    return text.replace("|", "\\|")


def covers(cited, path):
    return any(path == c or path.startswith(c + "/") for c in cited)


def main(argv):
    minimum, show_all, changed, markdown = 5, False, None, False
    args = iter(argv)
    for arg in args:
        if arg == "--min":
            minimum = int(next(args))
        elif arg == "--all":
            show_all = True
        elif arg == "--markdown":
            markdown = True
        elif arg == "--changed":
            changed = list(args)
        else:
            print(__doc__.strip(), file=sys.stderr)
            return 2
    table = docs()

    if changed is not None:
        hits = {}
        for doc, cited in table.items():
            if doc in changed:
                continue
            touched = [f for f in changed if covers(cited, f)]
            if touched:
                hits[doc] = touched
        if markdown:
            print("### Docs describing what this changes\n")
            if not hits:
                print("No doc lists the changed files.\n")
                return 0
            print("Not changed here: reread them if behaviour changed.\n")
            print("| Doc | Changed files it lists | Commits behind |\n|---|---|--:|")
            for doc, touched in sorted(hits.items()):
                count, _ = drift(doc, table[doc])
                print(f"| {link(doc)} | {', '.join(f'`{t}`' for t in touched)} | {count} |")
            print()
            return 0
        if not hits:
            print("no doc lists the changed files")
            return 0
        print("docs describing what changed (update them if behaviour changed):")
        for doc, touched in sorted(hits.items()):
            count, _ = drift(doc, table[doc])
            behind = f"; {count} commits behind its files" if count >= minimum else ""
            print(f"  {doc}  ({', '.join(touched)}{behind})")
        return 0

    rows = sorted(((*drift(doc, cited), doc) for doc, cited in table.items()), reverse=True)
    shown = [r for r in rows if show_all or r[0] >= minimum]
    if markdown:
        print("### Doc drift\n")
        if not shown:
            print(f"No doc's files changed in {minimum}+ commits since the doc did.\n")
            return 0
        print(f"Docs whose files changed in {minimum}+ commits since the doc did: reread one against the code, "
              "then fix or touch it to reset its count. Warnings only.\n")
        print("| Commits | Doc | Latest |\n|--:|---|---|")
        for count, subject, doc in shown:
            print(f"| {count} | {link(doc)} | {cell(subject)} |")
        print()
        return 0
    if not shown:
        print(f"doc drift ok (no doc's files changed in {minimum}+ commits since it did)")
        return 0
    if not show_all:
        print(f"docs whose files changed in {minimum}+ commits since the doc did (reread against the code):")
    for count, subject, doc in shown:
        print(f"  {count:3}  {doc}" + (f"  (latest: {subject})" if subject else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
