#!/usr/bin/env python3
"""Mark log lines (stdin) that an open docs/dev/issues.md entry already covers.

A line is known when it contains a backticked quote from the entry's **What**
(at least 12 characters: quote the warning's message there) and either names a
QML file (`@path/File.qml[line:col]`, or a `console.warn` tagged `[File]`) that
the entry's **Where** cites, or, for a warning from Qt or Quickshell itself that
names no file, comes from a logging category the **What** quotes too
(`WARN quickshell.I3.ipc: …`). Such a line gets
`  (known: issues.md › <title>)` appended; everything else passes through as is.

  scripts/log.sh | scripts/dev/known_issues.py
"""
import os
import re
import sys
from pathlib import Path

# AXIOM_ISSUES: another issues file (the tests')
ISSUES = Path(os.environ.get("AXIOM_ISSUES") or Path(__file__).resolve().parent.parent.parent / "docs/dev/issues.md")
LOG_FILE = re.compile(r"@([\w./-]+\.qml)\[")
# A console.warn naming its file by tag: "  WARN qml: [MediaManager] …"
TAGGED = re.compile(r"^\s*\w+ qml: \[(\w+)\] ")
# A line's logging category: "  WARN quickshell.I3.ipc: …"
CATEGORY = re.compile(r"^\s*\w+ ([a-z][\w]*(?:\.[\w]+)+): ")
TICKED = re.compile(r"`([^`]+)`")


def entries():
    """[(title, cited paths, quotes)] for each open entry"""
    text = ISSUES.read_text() if ISSUES.exists() else ""
    # The format's example at the top is no entry
    text = re.sub(r"^```.*?^```", "", text, flags=re.S | re.M)
    out = []
    for block in re.split(r"^### ", text, flags=re.M)[1:]:
        title = block.splitlines()[0].strip().replace("`", "")
        where = re.search(r"^- \*\*Where:\*\* (.*)$", block, re.M)
        what = re.search(r"^- \*\*What:\*\* (.*)$", block, re.M)
        if not where or not what:
            continue
        paths = {p for p in TICKED.findall(where.group(1)) if p.endswith(".qml")}
        ticked = TICKED.findall(what.group(1))
        categories = {q for q in ticked if CATEGORY.match(f"  WARN {q}: ")}
        # A category is no quote: it would match every line from it
        quotes = [q for q in ticked if len(q) >= 12 and q not in categories]
        if (paths or categories) and quotes:
            out.append((title, paths, categories, quotes))
    return out


def main():
    known = entries()
    for line in sys.stdin:
        line = line.rstrip("\n")
        match = LOG_FILE.search(line)
        tag = TAGGED.match(line) if not match else None
        category = CATEGORY.match(line) if not match and not tag else None
        for title, paths, categories, quotes in known:
            if match:
                source = match.group(1) in paths
            elif tag:
                source = any(Path(p).stem == tag.group(1) for p in paths)
            else:
                source = category is not None and category.group(1) in categories
            if source and any(q in line for q in quotes):
                line += f"  (known: issues.md › {title})"
                break
        print(line)


if __name__ == "__main__":
    main()
