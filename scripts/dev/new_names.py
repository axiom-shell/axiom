#!/usr/bin/env python3
"""List every name a branch adds, so a review can check names, duplicates
and clashes without reading the diff.

The change set is `git diff <merge-base of REF and HEAD>` (committed and
uncommitted) plus untracked files (every line added). From the added lines
only it lists what they define:

  QML     function, property, signal, id, and a component per new .qml file
  Go      func (functions and methods), type
  Python  def, class        shell  NAME() { / function NAME
  .js under tests/  function, var (a file's top-level names only)
  schema  mapping keys under qml/config/schema/ (JSON-schema and x-* keywords
          are skipped), and every schema.yaml
  strings the first string literal of an I18n.tr( call in QML

`(moved)` marks a name that was also on a removed line of the same file (an
edit or rename). `also defined:` lists up to 5 other places in the tracked
tree where the same name is defined the same way; for a string, the I18n.tr
calls with the same text ignoring case, spacing, digits and placeholders.
A name, or `Stem.name`, that is a key of scripts/names.json > retired prints `is retired: use <new>`
(`retired` in --json: the new name, else null). Generated files are skipped. It informs, it never gates: exit 0.

  scripts/dev/new_names.py [--base REF] [--files PATH ...] [--json]
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import manifests  # noqa: E402

SKIP = ("docs/dev/generated/", "docs/dev/config/", "qml/config/i18n/",
        "qml/config/json/config.schema.json", "qml/config/themes/template/")
# JSON-schema and annotation keywords: the keys of a schema that name no setting
KEYWORDS = {"type", "default", "description", "title", "minimum", "maximum", "enum", "items",
            "properties", "required", "additionalProperties", "$ref", "$schema", "$id", "$defs",
            "definitions", "allOf", "anyOf", "oneOf", "not", "if", "then", "else", "const",
            "format", "pattern", "minLength", "maxLength", "minItems", "maxItems", "examples",
            "value", "label", "name", "key", "icon", "id"}
MAX_ALSO = 5

PATTERNS = {
    "qml": [
        ("function", re.compile(r"^\s*(?:async\s+)?function\s+(\w+)\s*\(")),
        ("property", re.compile(r"^\s*(?:(?:readonly|required|default)\s+)*property\s+[\w.<>]+\s+(\w+)")),
        ("signal", re.compile(r"^\s*signal\s+(\w+)")),
        ("id", re.compile(r"^\s*(?:\w[\w.]*\s*\{\s*)?id\s*:\s*(\w+)")),
    ],
    "go": [
        ("func", re.compile(r"^func\s+(?:\([^)]*\)\s*)?(\w+)\s*[\[(]")),
        ("type", re.compile(r"^type\s+(\w+)")),
    ],
    "py": [
        ("def", re.compile(r"^\s*(?:async\s+)?def\s+(\w+)\s*\(")),
        ("class", re.compile(r"^\s*class\s+(\w+)")),
    ],
    "sh": [
        ("function", re.compile(r"^\s*(?:function\s+)?(\w[\w-]*)\s*\(\)\s*\{")),
        ("function", re.compile(r"^\s*function\s+(\w[\w-]*)")),
    ],
    "js": [
        ("function", re.compile(r"^function\s+(\w+)\s*\(")),
        ("var", re.compile(r"^var\s+(\w+)\b")),
    ],
    "schema": [
        ("key", re.compile(r"^\s*(?:-\s+)?([A-Za-z_$][\w$.-]*)\s*:")),
    ],
}
STRING = re.compile(r"""I18n\.tr\(\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')""")


def git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True).stdout


def lang_of(path):
    if path.startswith("qml/config/schema/") and path.endswith((".yaml", ".yml")) \
            or path.endswith("/schema.yaml"):
        return "schema"
    if path.startswith("tests/") and path.endswith(".js"):
        return "js"
    return {".qml": "qml", ".go": "go", ".py": "py", ".sh": "sh"}.get(Path(path).suffix)


def norm(text):
    """A string's comparison form: no placeholders or digits, one space, lower case."""
    text = re.sub(r"\{\w*\}|\d+", "", text)
    return re.sub(r"\s+", " ", text).strip().lower()


def extract(lang, line):
    """The (kind, name) pairs a source line defines."""
    found = []
    for kind, rx in PATTERNS.get(lang, []):
        m = rx.match(line)
        if not m:
            continue
        name = m.group(1)
        if lang == "schema" and (name in KEYWORDS or name.startswith("x-")):
            continue
        found.append((kind, name))
        break
    if lang == "qml":
        for m in STRING.finditer(line):
            found.append(("string", m.group(1)[1:-1]))
            break
    return found


def parse_diff(text):
    """{path: ([(line, text)] added, [text] removed, is_new_file)} from `git diff -U0`."""
    files, old, cur, n = {}, None, None, 0
    for raw in text.split("\n"):
        if raw.startswith("--- "):
            old = raw[4:]
        elif raw.startswith("+++ "):
            path = raw[4:]
            if path == "/dev/null":
                cur = None
                continue
            path = path[2:] if path.startswith("b/") else path
            cur = files.setdefault(path, ([], [], old == "/dev/null"))
        elif raw.startswith("@@") and cur is not None:
            m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)", raw)
            n = int(m.group(1))
        elif cur is not None and raw.startswith("+"):
            cur[0].append((n, raw[1:]))
            n += 1
        elif cur is not None and raw.startswith("-"):
            cur[1].append(raw[1:])
    return files


def change_set(root, base, only):
    mb = git(root, "merge-base", base, "HEAD").strip() or "HEAD"
    files = parse_diff(git(root, "diff", "-U0", "--no-color", mb))
    for path in git(root, "ls-files", "-o", "--exclude-standard").split("\n"):
        f = root / path
        if path and f.is_file():
            try:
                lines = f.read_text().split("\n")
            except (UnicodeDecodeError, OSError):
                continue
            files[path] = ([(i + 1, t) for i, t in enumerate(lines)], [], True)
    return {p: v for p, v in files.items()
            if not p.startswith(SKIP) and (not only or p in only)}


def build_index(root):
    """Every definition and I18n string in the tracked tree:
    ({(lang, kind, name): [path:line]}, {norm: [path:line]})."""
    defs, strings = {}, {}
    for path in git(root, "ls-files").split("\n"):
        lang = lang_of(path)
        if not lang or path.startswith(SKIP):
            continue
        try:
            lines = (root / path).read_text().split("\n")
        except (UnicodeDecodeError, OSError):
            continue
        if lang == "qml":
            defs.setdefault((lang, "component", Path(path).stem), []).append(f"{path}:1")
        for i, text in enumerate(lines, 1):
            for kind, name in extract(lang, text):
                if kind == "string":
                    strings.setdefault(norm(name), []).append(f"{path}:{i}")
                else:
                    defs.setdefault((lang, kind, name), []).append(f"{path}:{i}")
    return defs, strings


def retired_names(root):
    """The scratch tree's `scripts/names.json` retired keys ({old: {new, why}}), none when it has no list."""
    try:
        text = (root / "scripts" / "names.json").read_text()
    except OSError:
        return {}
    return manifests.retired(text)[0]


def collect(root, base, only):
    retired = retired_names(root)
    changes = change_set(root, base, only)
    defs, strings = build_index(root)
    out = []
    for path in sorted(changes):
        lang = lang_of(path)
        if not lang:
            continue
        added, removed, is_new = changes[path]
        gone = {pair for text in removed for pair in extract(lang, text)}
        items = [(1, "component", Path(path).stem)] if lang == "qml" and is_new else []
        for n, text in added:
            items += [(n, kind, name) for kind, name in extract(lang, text)]
        for n, kind, name in items:
            here = f"{path}:{n}"
            if kind == "string":
                key = norm(name)
                also = [p for p in strings.get(key, []) if p != here] if key else []
            elif kind == "id":
                also = []
            else:
                also = [p for p in defs.get((lang, kind, name), [])
                        if p != here and not (kind == "component" and p.startswith(path + ":"))]
            entry = None if kind == "string" else retired.get(name) or retired.get(f"{Path(path).stem}.{name}")
            out.append({"file": path, "kind": kind, "name": name, "line": n,
                        "moved": (kind, name) in gone and kind != "component",
                        "also": also[:MAX_ALSO],
                        "retired": entry["new"] if entry else None})
    return out


def main():
    ap = argparse.ArgumentParser(description="List the names a branch adds.")
    ap.add_argument("--base", default="main", help="the ref to diff from (merge-base with HEAD)")
    ap.add_argument("--files", nargs="+", default=[], metavar="PATH", help="only these paths")
    ap.add_argument("--json", action="store_true", help="print a list of objects")
    args = ap.parse_args()
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if top.returncode:
        print("new_names: not inside a git repository", file=sys.stderr)
        return 0
    rows = collect(Path(top.stdout.strip()), args.base, set(args.files))
    if args.json:
        print(json.dumps(rows, indent=2))
        return 0
    last = None
    for r in rows:
        if r["file"] != last:
            last = r["file"]
            print(last)
        tail = f"  also defined: {', '.join(r['also'])}" if r["also"] else ""
        moved = " (moved)" if r["moved"] else ""
        old = f"  {r['name']} is retired: use {r['retired']}" if r["retired"] is not None else ""
        print(f"  {r['kind']} {r['name']}{moved}  {r['file']}:{r['line']}{old}{tail}")
    print(f"{len(rows)} names, {sum(1 for r in rows if r['also'])} also defined elsewhere")
    return 0


if __name__ == "__main__":
    sys.exit(main())
