#!/usr/bin/env python3
"""Lay the shell out as a QML module tree that plain Qt tools can import.

qs resolves `import qs.…` itself, from the shell's directories, so qmllint
and qmltestrunner can't see those modules on their own. This builds what qs
builds in its runtime VFS: `<out>/qs/<dir>/` per directory, each .qml file
copied in (qmllint follows symlinks back to the repo and then sees two
types per file), and a `qmldir` listing the directory's types (singletons
declared as such, which qs's own VFS leaves out). Point a tool at it with
`-I <out>`.

  scripts/qml_modules.py OUT         build the tree in OUT (emptied first)
  scripts/qml_modules.py --pure OUT  only files that don't import Quickshell
"""
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# The shell's QML: `qs.` module names are relative to it
QML_ROOT = ROOT / "qml"
QML_DIRS = ["components", "shell", "services", "config"]

# The colour calls a bar widget may not make (check_structure T2): the shell's colour functions and raw colours
WIDGET_COLOR_CALLS = re.compile(
    r"\bTheme\.|resolveColor|Qt\.(?:rgba|hsla|hsva|alpha|lighter|darker|tint|color)\s*\(|\bBarWidgetStyle\.|"
    r"\bBarsConfig\.\w*Colors?\(|[\"']#[0-9a-fA-F]{3,8}[\"']|"
    r"[\"'](?:white|black|red|green|blue|yellow|orange|purple|gray|grey|cyan|magenta)[\"']")


def load_exceptions(path, rules, section=None):
    """Read an exceptions file ({ "<key>": { "rules": [...], "reason": "..." } }, under `section` if given) into
    (entries, errors): every entry needs a reason and only known rules."""
    path = Path(path)
    if not path.exists():
        return {}, []
    try:
        data = json.loads(path.read_text())
    except ValueError as e:
        return {}, [f"{path.name}: not JSON: {e}"]
    if section:
        data = data.get(section, {})
    entries, errors = {}, []
    for key, entry in data.items():
        if key.startswith("_"):
            continue
        if not isinstance(entry, dict):
            errors.append(f"{path.name}: {key} is not an object")
            continue
        if not str(entry.get("reason", "")).strip():
            errors.append(f"{path.name}: {key} has no reason")
        listed = entry.get("rules", [])
        for rule in listed:
            if rule not in rules:
                errors.append(f"{path.name}: {key} names {rule}, not a rule")
        entries[key] = dict(entry, rules=listed, reason=entry.get("reason", ""))
    return entries, errors


SINGLETON = re.compile(r"^\s*pragma\s+Singleton\b", re.M)


def qml_files():
    """Every QML file the shell loads: the entrypoints (shell.qml, greeter.qml)
    and the module directories."""
    files = [QML_ROOT / "shell.qml", QML_ROOT / "greeter.qml"]
    for d in QML_DIRS:
        files.extend(sorted((QML_ROOT / d).rglob("*.qml")))
    return files


QUICKSHELL_IMPORT = re.compile(r"^import Quickshell\b", re.M)


def pure(path):
    """Imports nothing from Quickshell, whose modules only exist inside qs."""
    return not QUICKSHELL_IMPORT.search(path.read_text())


def build_tree(out, only=None):
    """Build the module tree in `out` (emptied first); returns `out`.

    `only` (a path predicate) keeps just the files it accepts, e.g. `pure`
    for qmltestrunner, which can't load Quickshell's modules."""
    out = Path(out)
    if out.exists():
        shutil.rmtree(out)
    by_dir = {}
    for f in qml_files():
        if only and not only(f):
            continue
        by_dir.setdefault(f.parent.relative_to(QML_ROOT), []).append(f)
    for rel_dir, files in sorted(by_dir.items()):
        target = out / "qs" / rel_dir
        target.mkdir(parents=True, exist_ok=True)
        module = ".".join(("qs",) + rel_dir.parts)
        lines = [f"module {module}"]
        for f in sorted(files):
            shutil.copy2(f, target / f.name)
            kind = "singleton " if SINGLETON.search(f.read_text()) else ""
            lines.append(f"{kind}{f.stem} 1.0 {f.name}")
        (target / "qmldir").write_text("\n".join(lines) + "\n")
    return out


def main():
    args = sys.argv[1:]
    only = pure if args[:1] == ["--pure"] else None
    args = args[1:] if only else args
    if len(args) != 1:
        sys.exit(__doc__.strip())
    build_tree(args[0], only)


if __name__ == "__main__":
    main()
