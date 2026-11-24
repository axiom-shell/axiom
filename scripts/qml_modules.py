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
  scripts/qml_modules.py --layout OUT  the pure tree plus the layout harness's
                                     pieces (reusable/, the readers Style
                                     needs, the LAYOUT_SERVICES files) over the
                                     stubs in tests-layout/stubs

As a library it also holds the checks' shared baseline compare: `baseline_diff`
for counted baselines, `ratchet` for symbol baselines that only shrink.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# The shell's QML: `qs.` module names are relative to it
QML_ROOT = ROOT / "qml"
QML_DIRS = ["components", "shell", "services", "config"]

# The colour calls a bar widget may not make (check_structure T2): the shell's colour functions and raw colours
WIDGET_COLOR_CALLS = re.compile(
    r"\bTheme\.|resolveColor|Qt\.(?:rgba|hsla|hsva|alpha|lighter|darker|tint|color)\s*\(|\bBarWidgetStyle\.|"
    r"\bBarsConfig\.\w*Colors?\(|\bBarColors\.(?:widgetColors|pulseLadder|resolve)\s*\(|[\"']#[0-9a-fA-F]{3,8}[\"']|"
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



def baseline_diff(found, known):
    """Compare two {file: {key: count}} maps: (new, gone), lists of (file, key, n),
    `new` where found exceeds known by n (file, then key order), `gone` where known
    exceeds found by n (known's own order)."""
    new, gone = [], []
    for name, counts in sorted(found.items()):
        for key, n in sorted(counts.items()):
            have = known.get(name, {}).get(key, 0)
            if n > have:
                new.append((name, key, n - have))
    for name, counts in known.items():
        for key, n in counts.items():
            left = found.get(name, {}).get(key, 0)
            if n > left:
                gone.append((name, key, n - left))
    return new, gone


def numbered(symbols):
    """Number the repeats of a symbol: the k-th (k >= 2) gets `#k`."""
    seen, out = {}, []
    for symbol in symbols:
        seen[symbol] = seen.get(symbol, 0) + 1
        out.append(symbol if seen[symbol] == 1 else f"{symbol}#{seen[symbol]}")
    return out


def file_at(base, path, root=ROOT):
    """`path`'s text at git ref `base` (`git show <base>:<path>` run in `root`), None when
    the path is absent at a readable base; ValueError when the base can't be read."""
    if not base:
        raise ValueError(f"{path}: can't read the base {base}: no base given")
    ref = subprocess.run(["git", "rev-parse", "--verify", f"{base}^{{commit}}"],
                         cwd=root, capture_output=True, text=True)
    if ref.returncode:
        raise ValueError(f"{path}: can't read the base {base}: {ref.stderr.strip()}")
    shown = subprocess.run(["git", "show", f"{base}:{path}"], cwd=root, capture_output=True, text=True)
    return shown.stdout if shown.returncode == 0 else None


def default_base(root=ROOT):
    """The ref a check reads its baseline's base from: HEAD^1 in GitHub Actions (the merge
    commit's first parent), else the merge-base with origin/main; `origin/main` when that
    fails, so `file_at` reports it."""
    if os.environ.get("GITHUB_ACTIONS"):
        return "HEAD^1"
    done = subprocess.run(["git", "merge-base", "origin/main", "HEAD"], cwd=root, capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 and done.stdout.strip() else "origin/main"


def _baseline(text):
    """A {file: {rule: [symbol]}} baseline's text parsed, or None when it has another shape."""
    try:
        data = json.loads(text)
    except ValueError:
        return None
    ok = isinstance(data, dict) and all(
        isinstance(rules, dict) and all(isinstance(syms, list) and all(isinstance(s, str) for s in syms)
                                        for syms in rules.values())
        for rules in data.values())
    return data if ok else None


def _baseline_entries(baseline):
    return {(f, r, s) for f, rules in baseline.items() for r, syms in rules.items() for s in syms}


def ratchet(found, path, base, new_rules, root=ROOT):
    """Hold found {file: {rule: [symbol]}} to the baseline at `path` (repo-relative) in `root`:
    error lines for a hit not in the baseline, a baselined one that's gone, and an entry added
    since `base` whose rule and file aren't in `new_rules`. The base is read on every call."""
    try:
        at_base = file_at(base, path, root)
    except ValueError as e:
        return [str(e)]
    file = Path(root) / path
    known = _baseline(file.read_text()) if file.exists() else {}
    if known is None:
        return [f"{path}: not a {{file: {{rule: [symbol]}}}} baseline"]
    before = _baseline_entries(_baseline(at_base) or {}) if at_base is not None else set()
    hits, listed = _baseline_entries(found), _baseline_entries(known)
    errors = []
    for f, r, s in sorted(hits - listed):
        errors.append(f"{f}: {r} {s}: not in the baseline (fix it, or add an exception with its reason to {Path(path).name.replace('-baseline', '-exceptions')})")
    for f, r, s in sorted(listed - hits):
        errors.append(f"{f}: {r} {s}: fixed, still baselined (delete the entry)")
    for f, r, s in sorted((listed & hits) - before):
        if r not in new_rules and f not in new_rules:
            errors.append(f"{f}: {r} {s}: added to the baseline since {base} (a baseline only shrinks)")
    return errors


def add_to_baseline(found, path, new_rules, root=ROOT):
    """Write the baseline at `path`: its entries still found, plus found ones whose rule or file
    is in `new_rules`. Returns the entry count."""
    file = Path(root) / path
    old = (_baseline(file.read_text()) if file.exists() else None) or {}
    keep = _baseline_entries(old)
    out = {}
    for f, r, s in sorted(_baseline_entries(found)):
        if (f, r, s) in keep or r in new_rules or f in new_rules:
            out.setdefault(f, {}).setdefault(r, []).append(s)
    file.write_text(json.dumps(out, indent=2) + "\n")
    return sum(len(syms) for rules in out.values() for syms in rules.values())


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


# The layout harness (tests-layout/): the pure files and the pieces that import
# only the Quickshell modules its stubs supply
LAYOUT_STUBS = ROOT / "tests-layout" / "stubs"
LAYOUT_CONFIG = {"Appearance", "Widget", "Theme", "Style", "StyleInk", "StyleTextRole", "BarStyle", "PopoutsConfig"}
STUBBED_IMPORTS = {"Quickshell", "Quickshell.Widgets"}
# Service files a layout test loads, whose imports the stubs supply
LAYOUT_SERVICES = {"services/core/EngineTrace.qml"}


def layout(path):
    """What the layout harness loads: the components (pure, or importing only the Quickshell modules its stubs
    supply), the config readers the pieces read and the service files a test needs (LAYOUT_SERVICES). The other
    services and readers stay out: a module's singletons are all compiled on import, so one that needs a missing
    service would fail the import."""
    rel = path.relative_to(QML_ROOT).as_posix()
    if rel.startswith("config/"):
        return path.stem in LAYOUT_CONFIG
    if rel in LAYOUT_SERVICES:
        return True
    if not rel.startswith("components/"):
        return False
    return all(i in STUBBED_IMPORTS for i in re.findall(r"^import (Quickshell\S*)", path.read_text(), re.M))


# Files other than QML a layout piece loads by URL, relative to qml/: the composite's compiled shader
LAYOUT_ASSETS = ["components/hosts/popout/shaders/chrome-composite.frag.qsb"]


def add_assets(out):
    """Copy the layout pieces' non-QML files (LAYOUT_ASSETS) into the tree."""
    for rel in LAYOUT_ASSETS:
        target = Path(out) / "qs" / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(QML_ROOT / rel, target)


def add_stubs(out, stubs):
    """Copy the stub files into the tree (replacing a file of the same name) and list them in their qmldir."""
    for f in sorted(Path(stubs).rglob("*.qml")):
        rel_dir = f.parent.relative_to(stubs)
        target = Path(out) / rel_dir
        target.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, target / f.name)
        qmldir = target / "qmldir"
        lines = qmldir.read_text().splitlines() if qmldir.exists() else ["module " + ".".join(rel_dir.parts)]
        lines = [ln for ln in lines if f.name not in ln.split()]
        kind = "singleton " if SINGLETON.search(f.read_text()) else ""
        lines.append(f"{kind}{f.stem} 1.0 {f.name}")
        qmldir.write_text("\n".join(lines) + "\n")


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
    only = pure if args[:1] == ["--pure"] else layout if args[:1] == ["--layout"] else None
    args = args[1:] if only else args
    if len(args) != 1:
        sys.exit(__doc__.strip())
    build_tree(args[0], only)
    if only is layout:
        add_stubs(args[0], LAYOUT_STUBS)
        add_assets(args[0])


if __name__ == "__main__":
    main()
