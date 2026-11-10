#!/usr/bin/env python3
"""Check that the hand-written docs still match the code.

Docs drift silently; this catches the drift a reader would trip on:
- every relative markdown link points at a file that exists
- every backticked repo path (`qml/services/core/FooManager.qml`, `docs/dev/…`)
  exists, resolved from the repo root or from the doc's own directory
  (paths with <placeholders> or globs are skipped)
- every backticked `Singleton.member` names a member that file declares
  (Singleton = a file in qml/services/*/, qml/config/ or
  qml/components/methods/)
- no backticked name is one a rename retired (RETIRED: add the old name
  when renaming a singleton, so docs still citing it fail; an old name that
  is also a schema definition fails only with a member that isn't a setting)
- every shared piece (a file in qml/components/reusable, forms or content/parts)
  is named in the shared-ui-pieces index or the docs it defers to, so the
  index agents check before building stays whole
- every `x-*` annotation the config schema uses is named in
  docs/dev/core/schema-annotations.md, so that list stays complete

Covers docs/**/*.md (not the generated docs/dev/config and docs/dev/generated),
every AGENTS.md, README.md and CONTRIBUTING.md, and .claude/skills. Fenced
code blocks are skipped.

  scripts/check_docs.py
"""
import json
import re
import subprocess
import sys
from pathlib import Path

from gen_docs import parse_qml
from qml_modules import QML_ROOT, ROOT

GENERATED = ("docs/dev/config/", "docs/dev/generated/")
SCHEMA = "qml/config/json/config.schema.json"
# The old top-level QML folders stay roots, so a path cited at its place
# before the qml/ layout fails instead of passing unchecked
PATH_ROOTS = ("qml/", "data/", "components/", "services/", "config/", "scripts/", "shell/", "tests/", "docs/",
              "examples/", "assets/", "backend/", "packaging/", ".github/", ".claude/", "shell.qml", "greeter.qml",
              "install.sh")
# Names a rename retired: a doc still citing one is stale (old -> new)
RETIRED = {"IconConfig": "IconsConfig", "PopoutConfig": "PopoutsConfig", "Bar": "BarsConfig",
           "EdgeMenusConfig": "MenusConfig", "EdgeMenuManager": "MenuManager", "EdgeMenuEditor": "MenuEditor",
           "EdgeMenuBody": "MenuBody", "EdgeMenuSync": "MenuSync"}
# Backticked text that looks like a member access but isn't one of ours
NOT_MEMBERS = {"Quickshell", "Qt", "Math", "JSON", "Object", "Array", "String", "Date", "Number",
               "console", "Hyprland", "Text", "Item", "Layout", "Keys", "Image"}


def docs():
    files = [p for p in (ROOT / "docs").rglob("*.md") if not str(p.relative_to(ROOT)).startswith(GENERATED)]
    # Not agents' worktrees: other branches' checkouts, absent in CI
    worktrees = ROOT / ".claude" / "worktrees"
    files += [p for p in ROOT.rglob("AGENTS.md") if ".git" not in p.parts and not p.is_relative_to(worktrees)]
    files += [ROOT / "README.md", ROOT / "CONTRIBUTING.md"]
    files += list((ROOT / ".claude/skills").rglob("*.md"))
    return sorted(p for p in files if p.exists())


def singletons():
    """{name: set of root member names} for every singleton file."""
    table = {}
    for folder in ("services/*", "config", "components/methods"):
        for path in QML_ROOT.glob(f"{folder}/*.qml"):
            _, members = parse_qml(path)
            text = path.read_text()
            names = {m["name"] for m in members}
            # Members declared deeper (an IpcTarget's functions, inline
            # objects' ids) still count as the file's
            names |= set(re.findall(r"\b(?:function|property\s+\S+|signal)\s+(\w+)", text))
            names |= set(re.findall(r"\bid:\s*(\w+)", text))
            table[path.stem] = names
    return table


def config_names():
    """`Section.key` and `Definition.key` spellings of config paths (a doc
    naming `Appearance.surface` or `Bar.background` means the setting)."""
    schema = json.loads((ROOT / SCHEMA).read_text())
    names = set()

    def walk(prefix, node, depth=0):
        if depth > 6 or not isinstance(node, dict):
            return
        node = schema["definitions"].get(node.get("$ref", "").split("/")[-1], node)
        for key, child in node.get("properties", {}).items():
            names.add(f"{prefix}.{key}")
            walk(f"{prefix}.{key}", child, depth + 1)
        if isinstance(node.get("items"), dict):
            walk(prefix, node["items"], depth + 1)
    for section, node in schema["properties"].items():
        walk(section, node)
    for name, node in schema["definitions"].items():
        walk(name, node)
    return names


def retired_name(span, configs):
    """The retired name a span starts with, or None. One that is also a
    schema definition is stale only with a member that isn't a config path:
    `Bar` and `Bar.background` are the setting, `Bar.lookOf` the old reader."""
    old = re.match(r"(\w+)(?:\.(\w+))?", span)
    if not old or old.group(1) not in RETIRED:
        return None
    name, member = old.groups()
    if any(c.startswith(name + ".") for c in configs) and (not member or f"{name}.{member}" in configs):
        return None
    return name


def ignored(path):
    """A gitignored path (runtime state, build output) is named in docs but
    never in a checkout, so it may not exist."""
    # Also as a directory: a `dir/` rule can't match a path that isn't there
    return any(subprocess.run(["git", "-C", str(ROOT), "check-ignore", "-q", "--no-index", p]).returncode == 0
               for p in (path, path.rstrip("/") + "/"))


def strip_fences(text):
    return re.sub(r"(?ms)^```.*?^```", "", text)


# Folders of shared pieces -> the docs that must name each of their files
PIECE_INDEX = {
    "qml/components/reusable": ["docs/dev/core/shared-ui-pieces.md"],
    "qml/components/forms": ["docs/dev/core/shared-ui-pieces.md"],
    "qml/components/content/parts": ["docs/dev/core/shared-ui-pieces.md", "docs/dev/overlay/content-roots.md",
                                 "docs/dev/overlay/writing-modules.md"],
}


def check_piece_index():
    errors = []
    for folder, index in PIECE_INDEX.items():
        text = "\n".join((ROOT / doc).read_text() for doc in index)
        for path in sorted((ROOT / folder).glob("*.qml")):
            if not re.search(rf"\b{re.escape(path.stem)}\b", text):
                errors.append(f"{folder}/{path.name}: not in {index[0]} (add a line for it)")
    return errors


ANNOTATIONS_DOC = "docs/dev/core/schema-annotations.md"


def schema_annotations(node, found):
    if isinstance(node, dict):
        for key, value in node.items():
            if key.startswith("x-"):
                found.add(key)
            schema_annotations(value, found)
    elif isinstance(node, list):
        for value in node:
            schema_annotations(value, found)
    return found


def check_annotations():
    text = (ROOT / ANNOTATIONS_DOC).read_text()
    used = schema_annotations(json.loads((ROOT / SCHEMA).read_text()), set())
    return [f"{SCHEMA}: `{name}` isn't in {ANNOTATIONS_DOC} (add a line for it)"
            for name in sorted(used) if not re.search(rf"`{re.escape(name)}(?![\w-])", text)]


def main():
    errors = []
    members = singletons()
    configs = config_names()
    for doc in docs():
        rel = doc.relative_to(ROOT)
        text = strip_fences(doc.read_text())
        for n, line in enumerate(text.splitlines(), 1):
            where = f"{rel}:{n}"
            for target in re.findall(r"\]\(([^)\s#]+)(?:#[^)]*)?\)", line):
                if re.match(r"[a-z]+:", target):
                    continue
                if not (doc.parent / target).exists():
                    errors.append(f"{where}: link to missing {target}")
            for span in re.findall(r"`([^`\n]+)`", line):
                span = span.strip()
                old = retired_name(span, configs)
                if old:
                    errors.append(f"{where}: `{span}`: {old} was renamed to {RETIRED[old]}")
                    continue
                if span.startswith(PATH_ROOTS) and not re.search(r"[<>*{}|$ ]|\.\.\.|…", span):
                    path = span.split(":")[0].rstrip("/").rstrip(".,")
                    candidates = [ROOT / path, doc.parent / path]
                    if not any(c.exists() or c.with_suffix(".qml").exists() for c in candidates) and not ignored(path):
                        errors.append(f"{where}: `{span}` doesn't exist")
                    continue
                m = re.fullmatch(r"([A-Z]\w*)\.(_?[a-z]\w*)(?:\(.*\))?", span)
                if m and m.group(1) in members and m.group(1) not in NOT_MEMBERS \
                        and m.group(2) not in ("qml", "json", "md", "sh", "py") and span.split("(")[0] not in configs:
                    if m.group(2) not in members[m.group(1)]:
                        errors.append(f"{where}: `{span}`: {m.group(1)} has no member {m.group(2)}")
    errors += check_piece_index()
    errors += check_annotations()
    for e in errors:
        print(f"error    {e}")
    print("docs ok" if not errors else f"{len(errors)} doc errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
