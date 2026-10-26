#!/usr/bin/env python3
"""Check that the hand-written docs still match the code.

Docs drift silently; this catches the drift a reader would trip on:
- every relative markdown link points at a file that exists
- every backticked repo path (`services/core/FooManager.qml`, `docs/dev/…`)
  exists, resolved from the repo root, from components/, or from the doc's
  own directory (paths with <placeholders> or globs are skipped)
- every backticked `Singleton.member` names a member that file declares
  (Singleton = a file in services/*/, config/ or components/methods/)
- no backticked name is one a rename retired (RETIRED: add the old name
  when renaming a singleton, so docs still citing it fail; an old name that
  is also a schema definition fails only with a member that isn't a setting)
- every shared piece (a file in components/reusable, forms or content/parts)
  is named in the shared-ui-pieces index or the docs it defers to, so the
  index agents check before building stays whole
- every recipe in docs/recipes has a skill in .claude/skills of its name,
  and each such skill only points at its recipe (a rule restated in a skill
  drifts from the recipe, which is the one copy)
- every `x-*` annotation the config schema uses is named in
  docs/dev/core/schema-annotations.md, so that list stays complete
- every link to an issues.md entry names one that's there; an entry the
  cleanup roadmap (docs/dev/roadmap.md) doesn't link is a warning

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
from qml_modules import ROOT

GENERATED = ("docs/dev/config/", "docs/dev/generated/")
PATH_ROOTS = ("components/", "services/", "config/", "scripts/", "shell/", "tests/", "docs/",
              "examples/", "backend/", ".github/", ".claude/", "shell.qml", "greeter.qml", "install.sh")
# Names a rename retired: a doc still citing one is stale (old -> new)
RETIRED = {"IconConfig": "IconsConfig", "PopoutConfig": "PopoutsConfig", "Bar": "BarsConfig"}
# Backticked text that looks like a member access but isn't one of ours
NOT_MEMBERS = {"Quickshell", "Qt", "Math", "JSON", "Object", "Array", "String", "Date", "Number",
               "console", "Hyprland", "Text", "Item", "Layout", "Keys", "Image"}


def docs():
    files = [p for p in (ROOT / "docs").rglob("*.md") if not str(p.relative_to(ROOT)).startswith(GENERATED)]
    files += [p for p in ROOT.rglob("AGENTS.md") if ".git" not in p.parts]
    files += [ROOT / "README.md", ROOT / "CONTRIBUTING.md"]
    files += list((ROOT / ".claude/skills").rglob("*.md"))
    return sorted(p for p in files if p.exists())


def singletons():
    """{name: set of root member names} for every singleton file."""
    table = {}
    for folder in ("services/*", "config", "components/methods"):
        for path in ROOT.glob(f"{folder}/*.qml"):
            _, members = parse_qml(path)
            text = path.read_text()
            names = {m["name"] for m in members}
            # Members declared deeper (an IpcHandler's functions, inline
            # objects' ids) still count as the file's
            names |= set(re.findall(r"\b(?:function|property\s+\S+|signal)\s+(\w+)", text))
            names |= set(re.findall(r"\bid:\s*(\w+)", text))
            table[path.stem] = names
    return table


def config_names():
    """`Section.key` and `Definition.key` spellings of config paths (a doc
    naming `Appearance.surface` or `Bar.background` means the setting)."""
    schema = json.loads((ROOT / "config/json/config.schema.json").read_text())
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


ISSUE_FIELDS = ["Where", "What", "Size", "Found"]
SIZES = {"trivial", "small", "needs a plan"}


def check_issues():
    """docs/dev/issues.md: every entry under "## Open" is a ### heading with
    the four fields, in order, a known size and a dated Found."""
    path = ROOT / "docs/dev/issues.md"
    if not path.exists():
        return [f"{path.relative_to(ROOT)}: missing"]
    text = path.read_text()
    errors = []
    body = text.split("\n## Open", 1)[-1] if "\n## Open" in text else ""
    for entry in re.split(r"(?m)^### ", body)[1:]:
        title = entry.splitlines()[0]
        fields = re.findall(r"(?m)^- \*\*(\w+):\*\* (.+)$", entry)
        names = [name for name, _ in fields]
        if names != ISSUE_FIELDS:
            errors.append(f"docs/dev/issues.md: '{title}': fields {names}, expected {ISSUE_FIELDS}")
            continue
        values = dict(fields)
        if values["Size"].strip() not in SIZES:
            errors.append(f"docs/dev/issues.md: '{title}': Size must be one of {sorted(SIZES)}")
        if not re.match(r"\d{4}-\d{2}-\d{2}, while ", values["Found"]):
            errors.append(f"docs/dev/issues.md: '{title}': Found must be 'YYYY-MM-DD, while <task>'")
    return errors


ISSUES = "docs/dev/issues.md"
ROADMAP = "docs/dev/roadmap.md"


def heading_slug(title):
    """GitHub's anchor for a heading: lowercase, punctuation dropped, spaces
    to hyphens."""
    return re.sub(r"[^\w\- ]", "", title.strip().lower()).replace(" ", "-")


def check_issue_links(paths):
    """Every link to an issues.md entry (`issues.md#<anchor>`) names an
    entry that's there, so fixing one (and removing it) can't leave a dead
    link in the cleanup roadmap. Returns (errors, warnings): an entry the
    roadmap doesn't link is only a warning."""
    issues = ROOT / ISSUES
    anchors = {heading_slug(line[4:]) for line in issues.read_text().splitlines() if line.startswith("### ")}
    errors, linked = [], set()
    for doc in paths:
        text = strip_fences(doc.read_text())
        for n, line in enumerate(text.splitlines(), 1):
            for target, anchor in re.findall(r"\]\(([^)\s#]*)#([^)\s]+)\)", line):
                if (doc.parent / (target or doc.name)).resolve() != issues.resolve():
                    continue
                if anchor not in anchors:
                    errors.append(f"{doc.relative_to(ROOT)}:{n}: link to a missing issues.md entry #{anchor}")
                elif doc.relative_to(ROOT).as_posix() == ROADMAP:
                    linked.add(anchor)
    body = issues.read_text().split("\n## Open", 1)[-1]
    warnings = [f"{ISSUES}: '{line[4:]}' isn't linked from {ROADMAP} (add it to the phase that fixes it)"
                for line in body.splitlines() if line.startswith("### ") and heading_slug(line[4:]) not in linked]
    return errors, warnings


# Folders of shared pieces -> the docs that must name each of their files
PIECE_INDEX = {
    "components/reusable": ["docs/dev/core/shared-ui-pieces.md"],
    "components/forms": ["docs/dev/core/shared-ui-pieces.md"],
    "components/content/parts": ["docs/dev/core/shared-ui-pieces.md", "docs/dev/overlay/content-roots.md",
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


# A recipe skill's body: this many lines at most, naming its recipe
SKILL_LINES = 2


def check_skills():
    errors = []
    recipes = {p.stem for p in (ROOT / "docs/recipes").glob("*.md")}
    skills = {p.parent.name: p for p in (ROOT / ".claude/skills").glob("*/SKILL.md")}
    for name in sorted(recipes - skills.keys()):
        errors.append(f"docs/recipes/{name}.md: no skill .claude/skills/{name}/SKILL.md")
    for name in sorted(recipes & skills.keys()):
        rel = skills[name].relative_to(ROOT)
        body = [line for line in skills[name].read_text().split("---", 2)[-1].splitlines() if line.strip()]
        if not any(f"docs/recipes/{name}.md" in line for line in body):
            errors.append(f"{rel}: doesn't point at docs/recipes/{name}.md")
        elif len(body) > SKILL_LINES:
            errors.append(f"{rel}: {len(body)} lines; a recipe skill only points at its recipe "
                          f"(move rules into docs/recipes/{name}.md)")
    return errors


SCHEMA = "config/json/config.schema.json"
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
                    candidates = [ROOT / path, ROOT / "components" / path, doc.parent / path]
                    if not any(c.exists() or c.with_suffix(".qml").exists() for c in candidates) and not ignored(path):
                        errors.append(f"{where}: `{span}` doesn't exist")
                    continue
                m = re.fullmatch(r"([A-Z]\w*)\.(_?[a-z]\w*)(?:\(.*\))?", span)
                if m and m.group(1) in members and m.group(1) not in NOT_MEMBERS \
                        and m.group(2) not in ("qml", "json", "md", "sh", "py") and span.split("(")[0] not in configs:
                    if m.group(2) not in members[m.group(1)]:
                        errors.append(f"{where}: `{span}`: {m.group(1)} has no member {m.group(2)}")
    errors += check_issues()
    link_errors, warnings = check_issue_links(docs())
    errors += link_errors
    errors += check_skills()
    errors += check_piece_index()
    errors += check_annotations()
    for w in warnings:
        print(f"warning  {w}")
    for e in errors:
        print(f"error    {e}")
    print("docs ok" if not errors else f"{len(errors)} doc errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
