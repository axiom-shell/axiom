#!/usr/bin/env python3
"""Check that the three package lists agree.

install.sh, components/methods/Packages.qml (the onboarder's install hints)
and the AUR PKGBUILDs (packaging/aur/*/PKGBUILD) each say what installs
axiom's dependencies; this fails when they drift:
- every key in install.sh's PACKAGES names the same Arch and Fedora package
  as Packages.packages (a COPR as Packages' `repo`, "-" and "n/a" as null)
- every key install.sh's REQUIRED and FEATURES use is in PACKAGES
- each PKGBUILD's depends are the Arch packages of REQUIRED (less git: a
  package doesn't self-update), and its optdepends are exactly the Arch
  packages of the compositors and of FEATURES

Prints `error    <file>: <message>` per problem, as check_structure does.

  scripts/check_packages.py
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INSTALL = ROOT / "install.sh"
PACKAGES_QML = ROOT / "components/methods/Packages.qml"
PKGBUILDS = sorted((ROOT / "packaging/aur").glob("*/PKGBUILD"))
DISTROS = ("arch", "fedora")
COMPOSITORS = ("hyprland", "sway", "niri")

errors = []


def error(path, message):
    errors.append(f"error    {path.relative_to(ROOT)}: {message}")


def bash_array(text, name):
    """A bash array's items, as bash reads its definition"""
    match = re.search(rf"^{name}=\((?:[^\n]*\)$|.*?^\)$)", text, re.S | re.M)
    if not match:
        return None
    done = subprocess.run(["bash", "-c", f'{match.group(0)}\nprintf "%s\\0" "${{{name}[@]}}"'], capture_output=True, text=True)
    return [item for item in done.stdout.split("\0") if item] if done.returncode == 0 else None


def qml_packages():
    """Packages.packages as data: its root.<name> strings filled in"""
    text = PACKAGES_QML.read_text()
    strings = dict(re.findall(r'readonly property string (\w+): "([^"]*)"', text))
    start = text.index("readonly property var packages: (") + len("readonly property var packages: (")
    depth = 0
    for i in range(start, len(text)):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        if depth == 0:
            break
    body = re.sub(r"root\.(\w+)", lambda m: json.dumps(strings[m.group(1)]), text[start:i + 1])
    return json.loads(body)


def same(cell, entry):
    """Whether an install.sh cell says what a Packages entry does"""
    if cell in ("-", "n/a"):
        return entry is None
    name = cell.split(":")[-1]
    repo = cell.split(":")[0] if "/" in cell and ":" in cell else None
    if isinstance(entry, str):
        return repo is None and entry == name
    return isinstance(entry, dict) and entry.get("name") == name and entry.get("repo") == repo


def pkgbuild_arrays(path):
    """depends and optdepends, as makepkg reads them"""
    script = f'source "{path}"; printf "%s\\0" "${{depends[@]}}"; printf "\\1"; printf "%s\\0" "${{optdepends[@]}}"'
    done = subprocess.run(["bash", "-c", script], capture_output=True, text=True, cwd=path.parent)
    if done.returncode != 0:
        error(path, f"can't be read: {done.stderr.strip()}")
        return [], []
    depends, optdepends = done.stdout.split("\1")
    names = lambda items: [re.split(r"[<>=:]", item, maxsplit=1)[0].strip() for item in items.split("\0") if item]
    return names(depends), names(optdepends)


def main():
    text = INSTALL.read_text()
    rows = bash_array(text, "PACKAGES")
    required = bash_array(text, "REQUIRED")
    features = bash_array(text, "FEATURES")
    if rows is None or required is None or features is None:
        error(INSTALL, "PACKAGES, REQUIRED or FEATURES not found")
        return
    table = {}
    for row in rows:
        cells = row.split("|")
        if len(cells) != 1 + len(DISTROS):
            error(INSTALL, f"PACKAGES row {row!r} isn't key|arch|fedora")
            continue
        table[cells[0]] = dict(zip(DISTROS, cells[1:]))

    packages = qml_packages()
    for key, cells in table.items():
        if key not in packages:
            error(PACKAGES_QML, f"no key {key!r} (install.sh installs it)")
            continue
        for distro in DISTROS:
            if not same(cells[distro], packages[key].get(distro)):
                error(INSTALL, f"{key} on {distro} is {cells[distro]!r}, Packages.qml says {packages[key].get(distro)!r}")

    feature_keys = []
    for feature in features:
        name, keys, _ = (feature.split("|") + ["", ""])[:3]
        for key in keys.split():
            feature_keys.append(key)
            if key not in table:
                error(INSTALL, f"feature {name!r} uses {key!r}, which isn't in PACKAGES")
    for key in required + list(COMPOSITORS):
        if key not in table:
            error(INSTALL, f"{key!r} isn't in PACKAGES")

    arch = lambda keys: {table[key]["arch"] for key in keys if key in table and table[key]["arch"] not in ("-", "n/a")}
    # git and go only fetch and build it: the PKGBUILDs' makedepends
    want_depends = arch(key for key in required if key not in ("git", "go"))
    want_optdepends = arch(list(COMPOSITORS) + feature_keys) - want_depends
    for path in PKGBUILDS:
        depends, optdepends = pkgbuild_arrays(path)
        if set(depends) != want_depends:
            error(path, f"depends {sorted(depends)} aren't install.sh's required packages {sorted(want_depends)}")
        for name in sorted(set(optdepends) - want_optdepends):
            error(path, f"optdepends {name}, which no install.sh feature or compositor installs")
        for name in sorted(want_optdepends - set(optdepends)):
            error(path, f"no optdepends for {name} (install.sh offers it)")


main()
for line in errors:
    print(line)
print(f"packages: {len(errors)} errors" if errors else "packages ok")
sys.exit(1 if errors else 0)
