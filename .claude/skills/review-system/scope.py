#!/usr/bin/env python3
"""Resolve a /review-system system into what to read, cheaply, and file
what reviews found.

  scope.py <system>        docs, files (lines, churn, fix commits) ranked by
                           risk, changes since the last review, issues.md
                           entries touching the files
  scope.py --list          every system: mode, files, lines, last reviewed
  scope.py --orphans       code files no system covers, and files in several
  scope.py --apply <dir>…  record reviews: each dir's report.md Blockers,
                           Major, Cleanups and Outside the system entries
                           appended to issues.md and
                           linked under the roadmap's "Found by the audits:",
                           its review.md copied to .claude/reviews/; lists
                           entries naming a symbol another names, then runs
                           check_docs

<system> is a name from systems.md, or feature:<name>, doc:<path>, files:<glob>.
A folder (`dir/`) in a doc's Files header or in Extra means the files directly
in it; a glob in a doc header is reported, not expanded.
"""
import glob
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(ROOT, "docs", "dev")
ISSUES = os.path.join(DOCS, "issues.md")
REVIEWS = os.path.join(ROOT, ".claude", "reviews")
CODE = ("*.qml", "*.go", "*.py", "*.sh", "*.lua")
RECORDED = ("Blockers", "Major", "Cleanups", "Outside the system")
LINKS = "Found by the audits:\n"


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout


def systems():
    out, cur = {}, None
    for line in open(os.path.join(HERE, "systems.md")):
        if line.startswith("## "):
            cur = out[line[3:].strip()] = {"mode": "files", "docs": [], "extra": []}
        elif cur is not None:
            for key in ("Docs", "Extra", "Mode", "Scope"):
                if line.startswith(key + ":"):
                    val = line[len(key) + 1:].strip()
                    if key in ("Docs", "Extra"):
                        cur[key.lower()] += val.split()
                    else:
                        cur[key.lower()] = val
    return out


def expand(pattern, base=ROOT):
    if pattern.endswith("/"):
        pattern += "*"
    hits = sorted(glob.glob(os.path.join(base, pattern)))
    return [os.path.relpath(h, base) for h in hits if os.path.isfile(h)]


def doc_files(doc):
    """Files a doc's header lists; globs are reported, not expanded."""
    files, broad = [], []
    for line in open(os.path.join(DOCS, doc)):
        if line.startswith("> **Files:**"):
            for p in re.findall(r"`([^`]+)`", line):
                if "*" in p:
                    broad.append(p)
                else:
                    files += expand(p)
            break
    return files, broad


def resolve(name):
    table = systems()
    if name.startswith("feature:"):
        spec = {"mode": "files", "docs": ["features/%s.md" % name[8:]], "extra": []}
    elif name.startswith("doc:"):
        spec = {"mode": "files", "docs": [os.path.relpath(os.path.join(ROOT, name[4:]), DOCS)], "extra": []}
    elif name.startswith("files:"):
        spec = {"mode": "files", "docs": [], "extra": [name[6:]]}
    elif name in table:
        spec = table[name]
    else:
        return None
    docs = [d for pat in spec["docs"] for d in expand(pat, DOCS)]
    files, broad = [], []
    for d in docs:
        f, b = doc_files(d)
        files += f
        broad += b
    for pat in spec["extra"]:
        files += expand(pat)
    seen = set()
    files = [f for f in files if not (f in seen or seen.add(f))]
    return {**spec, "docs": docs, "files": files, "broad": sorted(set(broad))}


def lines(path):
    try:
        return sum(1 for _ in open(os.path.join(ROOT, path), errors="replace"))
    except OSError:
        return 0


def counts(log):
    c = {}
    for f in log.split("\n"):
        if f.strip():
            c[f.strip()] = c.get(f.strip(), 0) + 1
    return c


def review_path(name):
    return os.path.join(REVIEWS, name.replace(":", "_").replace("/", "_") + ".md")


def last_review(name):
    path = review_path(name)
    if not os.path.isfile(path):
        return None
    m = re.search(r"^reviewed:\s*(\w+)", open(path).read(), re.M)
    return m.group(1) if m else None


def show(name):
    s = resolve(name)
    if s is None:
        print("unknown system %r; scope.py --list shows them" % name)
        return 2
    churn = counts(git("log", "--since=6.months", "--format=", "--name-only"))
    fixes = counts(git("log", "--since=6.months", "-i", "--grep=fix", "--format=", "--name-only"))
    others = owners(systems()) if not name.startswith(("feature:", "doc:", "files:")) else {}
    code = [f for f in s["files"] if not is_side(f)]
    rows = [(f, lines(f), churn.get(f, 0), fixes.get(f, 0)) for f in code]
    rows.sort(key=lambda r: r[1] * (1 + r[2]) * (1 + 2 * r[3]), reverse=True)
    print("# %s  (mode: %s)" % (name, s["mode"]))
    print("docs: " + " ".join("docs/dev/" + d for d in s["docs"]))
    if s["broad"]:
        print("globs in doc headers (not expanded): " + " ".join(s["broad"]))
    print("\ncode by risk (lines, commits 6mo, fix commits 6mo; also in = another system's file, a seam here):")
    for f, n, c, x in rows:
        also = [o for o in others.get(f, []) if o != name]
        print("  %5d %3d %3d  %s%s" % (n, c, x, f, ("  [also in: %s]" % ", ".join(also)) if also else ""))
    print("total: %d files, %d lines" % (len(rows), sum(r[1] for r in rows)))
    side = [f for f in s["files"] if is_side(f)]
    if side:
        print("tests and data (grep for what you need, never read whole):")
        for f in side:
            print("  %5d  %s" % (lines(f), f))
    sha = last_review(name)
    print("\nlast review: " + (("%s (%s)" % (sha, os.path.relpath(review_path(name), ROOT))) if sha else "none"))
    if sha:
        changed = set(git("diff", "--name-only", sha).split()) & set(s["files"])
        print("changed since: " + (" ".join(sorted(changed)) if changed else "nothing"))
    issues = open(ISSUES).read().split("\n### ")[1:]
    hit = [e.split("\n")[0] for e in issues if any(f in e for f in s["files"])]
    print("\nissues.md entries touching these files:" + ("".join("\n  - " + h for h in hit) if hit else " none"))
    return 0


def is_side(path):
    return path.startswith("tests/") or path.endswith((".json", "_test.go")) or "/testdata/" in path


def owners(names):
    out = {}
    for name in names:
        for f in resolve(name)["files"]:
            out.setdefault(f, []).append(name)
    return out


def all_code():
    out = []
    for top in ("components", "services", "config", "shell", "scripts", "backend"):
        for pat in CODE:
            out += expand(os.path.join(top, "**", pat))
    return sorted(set(out + expand("shell.qml") + expand("install.sh")))


def symbols(entry):
    """(path, symbol) pairs an entry's Where names: `path` (`a`, `b`)."""
    where = re.search(r"(?m)^- \*\*Where:\*\* (.*)$", entry)
    pairs = set()
    for path, syms in re.findall(r"`([^`]+?)(?::[\d-]+)?`\s*\(([^)]*)\)", where.group(1) if where else ""):
        pairs |= {(path, s) for s in re.findall(r"`([^`]+)`", syms)}
    return pairs


def apply(dirs):
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    import check_docs
    issues = open(ISSUES).read()
    titles = {line[4:] for line in issues.splitlines() if line.startswith("### ")}
    new = []
    for d in dirs:
        report = open(os.path.join(d, "report.md")).read()
        for section in re.split(r"(?m)^## ", report)[1:]:
            if section.startswith(RECORDED):
                for entry in re.split(r"(?m)^### ", section)[1:]:
                    entry = "### " + entry.strip()
                    if entry.splitlines()[0][4:] in titles:
                        print("already in issues.md, skipped: " + entry.splitlines()[0][4:])
                    else:
                        new.append(entry)
        record = os.path.join(d, "review.md")
        if os.path.isfile(record):
            shutil.copy(record, review_path(open(record).readline()[2:].strip()))
    old = re.split(r"(?m)^(?=### )", issues.split("\n## Open", 1)[1])[1:]
    for i, entry in enumerate(new):
        for other in old + new[:i]:
            shared = symbols(entry) & symbols(other)
            if shared:
                print("same symbol, one cause or one fix? %s / %s: %s" % (
                    entry.splitlines()[0][4:], other.splitlines()[0][4:], ", ".join("%s (%s)" % p for p in sorted(shared))))
    if new:
        with open(ISSUES, "w") as f:
            f.write(issues.rstrip("\n") + "\n\n" + "\n\n".join(new) + "\n")
        roadmap = os.path.join(DOCS, "roadmap.md")
        text = open(roadmap).read()
        end = text.index(LINKS) + len(LINKS)
        while text.startswith("- [", end):
            end = text.index("\n", end) + 1
        links = "".join("- [%s](issues.md#%s)\n" % (t, check_docs.heading_slug(t))
                        for t in (e.splitlines()[0][4:] for e in new))
        with open(roadmap, "w") as f:
            f.write(text[:end] + links + text[end:])
    print("%d entries filed" % len(new))
    return check_docs.main()


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "--list"
    table = systems()
    if arg == "--list":
        print("%-20s %-10s %5s %7s  %s" % ("system", "mode", "files", "lines", "last review"))
        print("(code only: tests and .json data left out)")
        for name in table:
            s = resolve(name)
            code = [f for f in s["files"] if not is_side(f)]
            print("%-20s %-10s %5d %7d  %s" % (name, s["mode"], len(code), sum(map(lines, code)), last_review(name) or "-"))
        print("\nalso: feature:<name> (%s), doc:<path>, files:<glob>"
              % " ".join(os.path.basename(f)[:-3] for f in sorted(glob.glob(os.path.join(DOCS, "features", "*.md")))))
        return 0
    if arg == "--orphans":
        features = ["feature:" + os.path.basename(f)[:-3] for f in glob.glob(os.path.join(DOCS, "features", "*.md"))]
        found = owners(list(table) + features)
        orphans = [f for f in all_code() if f not in found and not is_side(f)]
        print("no system (%d):" % len(orphans))
        for f in orphans:
            print("  %5d  %s" % (lines(f), f))
        multi = {f: o for f, o in found.items() if len([n for n in o if not n.startswith("feature:")]) > 1}
        print("\nin several systems (%d):" % len(multi))
        for f, o in sorted(multi.items()):
            print("  %s: %s" % (f, ", ".join(o)))
        return 0
    if arg == "--apply":
        return apply(sys.argv[2:])
    return show(arg)


if __name__ == "__main__":
    sys.exit(main())
