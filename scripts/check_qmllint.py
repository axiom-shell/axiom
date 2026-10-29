#!/usr/bin/env python3
"""Run qmllint over the shell, failing only on warnings not in the baseline.

qmllint can't resolve `import qs.…` by itself, so this lints a copy of the
shell laid out as QML modules (scripts/qml_modules.py). Many of its warnings
are gaps in Quickshell's type info rather than bugs, so the known ones are
kept in scripts/qmllint-baseline.json, per file, as "category: message"
with a count (no line numbers, so unrelated edits don't churn it). A new
warning, or one more of a known kind in the same file, fails the check; so
does a baselined one that's gone, since the baseline only shrinks.

  scripts/check_qmllint.py                    lint (exit 1 on new or gone warnings)
  scripts/check_qmllint.py --update-baseline  accept the current warnings
"""
import collections
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from qml_modules import ROOT, build_tree



def qt_path(env, query, fallback):
    """$env, else what qmake6 says for `query` (Fedora's Qt is in
    /usr/lib64/qt6), else Arch's `fallback` (scripts/lib/qt_paths.sh)."""
    if os.environ.get(env):
        return os.environ[env]
    try:
        out = subprocess.run(["qmake6", "-query", query], capture_output=True, text=True, check=True).stdout.strip()
        if out:
            return out
    except (OSError, subprocess.CalledProcessError):
        pass
    return fallback


QMLLINT = qt_path("QT_BIN", "QT_INSTALL_BINS", "/usr/lib/qt6/bin") + "/qmllint"
# Quickshell's QML modules are installed beside Qt's
QT_QML = qt_path("QT_QML", "QT_INSTALL_QML", "/usr/lib/qt6/qml")
BASELINE = ROOT / "scripts" / "qmllint-baseline.json"
# Quickshell's type info can't express these, so every file would hit them:
# PanelWindow reads as uncreatable, and Process.exited's QProcess enum is
# not exported
DISABLED = ["uncreatable-type", "signal-handler-parameters"]


def qt_imports(out):
    """QT_QML with Quickshell's type info minus its opaque stubs; returns `out`.

    Since 0.3.2, a Quickshell module's qmltypes declares a member-less
    `isTypeOpaque` stub for each type it uses from another module
    (QuickshellScreenInfo, PopupAnchor, Margins, UntypedObjectModel, …), and
    qmllint resolves the stub instead of the real type. Every other module is
    linked in as is."""
    out.mkdir()
    for entry in Path(QT_QML).iterdir():
        if entry.name != "Quickshell":
            os.symlink(entry, out / entry.name)
    shutil.copytree(Path(QT_QML) / "Quickshell", out / "Quickshell")
    for types in (out / "Quickshell").rglob("*.qmltypes"):
        kept, block = [], None
        for line in types.read_text().splitlines(keepends=True):
            if block is None and line.startswith("    Component {"):
                block, depth = [], 0
            if block is None:
                kept.append(line)
                continue
            block.append(line)
            depth += line.count("{") - line.count("}")
            if depth == 0:
                if not any("isTypeOpaque: true" in b for b in block):
                    kept.extend(block)
                block = None
        types.write_text("".join(kept))
    return out


def lint():
    """{repo-relative file: Counter("category: message")}, and the raw lines."""
    with tempfile.TemporaryDirectory() as tmp:
        tree = build_tree(Path(tmp) / "tree")
        files = sorted(str(p) for p in (tree / "qs").rglob("*.qml"))
        imports = qt_imports(Path(tmp) / "qml")
        # --bare: no default import path, which would find the stubbed Quickshell
        args = [QMLLINT, "--bare", "-I", str(tree), "-I", str(imports)]
        for category in DISABLED:
            args += [f"--{category}", "disable"]
        # One qmllint per CPU, each on a share of the files with its own report
        count = os.cpu_count() or 1
        shards = [s for s in (files[i::count] for i in range(count)) if s]
        reports = [Path(tmp) / f"report{i}.json" for i in range(len(shards))]
        procs = [subprocess.Popen(args + ["--json", str(report)] + shard,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                 for shard, report in zip(shards, reports)]
        for proc in procs:
            proc.wait()
        missing = [str(r) for r in reports if not r.exists()]
        if missing:
            sys.exit(f"qmllint wrote no report (crashed?): {', '.join(missing)}")
        entries = [e for report in reports for e in json.loads(report.read_text())["files"]]
        prefix = str(tree / "qs") + "/"
    found, lines = {}, collections.defaultdict(list)
    for entry in entries:
        name = entry["filename"].removeprefix(prefix)
        for w in entry["warnings"]:
            # Messages may name a file by its path in the temporary tree
            message = w["message"].replace(prefix, "")
            key = f"{w.get('id', 'unknown')}: {message}"
            found.setdefault(name, collections.Counter())[key] += 1
            lines[(name, key)].append(w.get("line"))
    return found, lines


def main():
    found, lines = lint()
    if "--update-baseline" in sys.argv:
        baseline = {f: dict(sorted(c.items())) for f, c in sorted(found.items())}
        BASELINE.write_text(json.dumps(baseline, indent=2) + "\n")
        print(f"baseline: {sum(sum(c.values()) for c in found.values())} warnings")
        return
    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
    new, gone = [], []
    for name, counts in sorted(found.items()):
        known = baseline.get(name, {})
        for key, n in sorted(counts.items()):
            if n > known.get(key, 0):
                at = ",".join(str(ln) for ln in lines[(name, key)] if ln)
                new.append(f"{name}:{at}: {key}" + (f" ({n - known.get(key, 0)} new)" if known.get(key) else ""))
    for name, known in baseline.items():
        for key, n in known.items():
            if n > found.get(name, {}).get(key, 0):
                gone.append(f"{name}: {key} ({n - found.get(name, {}).get(key, 0)} gone)")
    for line in new:
        print(f"error: {line}")
    for line in gone:
        print(f"error: fixed, still baselined: {line}")
    if new:
        print(f"{len(new)} new qmllint warnings (fix them, or --update-baseline if they're false positives)")
    if gone:
        print(f"{len(gone)} baselined warnings are gone: run with --update-baseline to drop them")
    if new or gone:
        sys.exit(1)
    print("qmllint ok")


if __name__ == "__main__":
    main()
