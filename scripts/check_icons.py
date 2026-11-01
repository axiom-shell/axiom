#!/usr/bin/env python3
"""Check that every Material Symbols name axiom writes down is in the font.

An icon name the bundled font (assets/fonts, its names in
config/json/material-symbols.json) doesn't have draws as the word itself,
silently. This fails on a name, read from:

  - the built schema (config/json/config.schema.json): `x-icon`,
    `x-enumIcons` and `x-categories` icons, the default of every
    `x-control: icon` setting, and any `icon` / `…Icon` / `glyph` string in
    a default (Chat's presets)
  - QML: a string literal set to a property named `icon`, `…Icon`,
    `glyph` or `iconText` (each literal of a `cond ? "a" : "b"`), a
    `StyledIcon`'s `text`, and the values of an object literal held by a
    property named `…Icons` (KeybindManager's `_actionIcons`)

Only literals that read as a name (`[a-z][a-z0-9_]*`) count: a glyph, text
or a name built at runtime is left alone. A line marked
`// not an icon: <reason>` is skipped.

Prints `error    <file>:<line>: <message>` per problem, as check_structure
does.

  scripts/check_icons.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "config/json/material-symbols.json"
SCHEMA = ROOT / "config/json/config.schema.json"
DIRS = ["components", "services", "config", "shell"]
NAME = re.compile(r"^[a-z][a-z0-9_]*$")
STRING = re.compile(r'"([^"\\]*)"')
MARK = "// not an icon:"
# `icon: …`, `connectedIcon: …`, `glyph: …`, `property string icon: …`
ICON_PROP = re.compile(r"^\s*(?:readonly\s+)?(?:property\s+\w+\s+)?(icon|\w+Icon|glyph|iconText)\s*:\s*(.+)$")
ICON_MAP = re.compile(r"^\s*(?:readonly\s+)?property\s+var\s+\w*Icons\s*:\s*\(\{\s*$")
MAP_ENTRY = re.compile(r'^\s*"[^"]*"\s*:\s*"([^"]*)"')

errors = []


def error(path, line, message):
    errors.append(f"error    {path}:{line}: {message}")


def names_in(expression):
    """The string literals an expression can come out as, that read as
    icon names: those outside any call or array (`a ? "b" : "c"`,
    `x ?? "d"`), less compared ones (`x === "a"`)"""
    shown = re.sub(r'(?:===|!==|==|!=)\s*"[^"]*"', "", expression)
    shown = re.sub(r'"[^"]*"\s*(?:===|!==|==|!=)', "", shown)
    found, depth, i = [], 0, 0
    while i < len(shown):
        char = shown[i]
        if char == "/" and shown[i:i + 2] == "//":
            break
        if char == '"':
            end = shown.find('"', i + 1)
            if end < 0:
                break
            if depth == 0 and NAME.match(shown[i + 1:end]):
                found.append(shown[i + 1:end])
            i = end + 1
            continue
        depth += char in "([{"
        depth -= char in ")]}"
        i += 1
    return found


def check_schema(known):
    if not SCHEMA.exists():
        error(SCHEMA.relative_to(ROOT), 0, "not built: run scripts/generate.sh")
        return
    path = SCHEMA.relative_to(ROOT)

    def check(value, where):
        for name in str(value).split():
            if NAME.match(name) and name not in known:
                error(path, 0, f"{where}: no icon named {name!r}")

    def defaults(node, where):
        """icon strings anywhere inside a default"""
        if isinstance(node, dict):
            for key, value in node.items():
                if isinstance(value, str) and (key == "icon" or key.endswith("Icon") or key == "glyph"):
                    check(value, f"{where}.{key}")
                else:
                    defaults(value, f"{where}.{key}")
        elif isinstance(node, list):
            for i, item in enumerate(node):
                defaults(item, f"{where}[{i}]")

    def walk(node, where):
        if isinstance(node, dict):
            if isinstance(node.get("x-icon"), str):
                check(node["x-icon"], f"{where} x-icon")
            for value, icon in (node.get("x-enumIcons") or {}).items():
                check(icon, f"{where} x-enumIcons.{value}")
            for category in node.get("x-categories") or []:
                if isinstance(category, dict) and isinstance(category.get("icon"), str):
                    check(category["icon"], f"{where} x-categories {category.get('name', '')}")
            if node.get("x-control") == "icon" and isinstance(node.get("default"), str):
                check(node["default"], f"{where} default")
            if "default" in node:
                defaults(node["default"], f"{where} default")
            for key, value in node.items():
                if key != "default":
                    walk(value, f"{where}.{key}" if where else key)
        elif isinstance(node, list):
            for item in node:
                walk(item, where)

    walk(json.loads(SCHEMA.read_text()), "")


def check_qml(known):
    for folder in DIRS:
        for file in sorted((ROOT / folder).rglob("*.qml")):
            path = file.relative_to(ROOT)
            lines = file.read_text().splitlines()
            # StyledIcon blocks: their depth, to find their own `text:`
            icon_depths = []
            depth = 0
            in_map = False
            for number, line in enumerate(lines, 1):
                code = line.split("//")[0] if "//" in line and '"' not in line.split("//")[0][-1:] else line
                found = []
                if MARK not in line:
                    if in_map:
                        entry = MAP_ENTRY.match(line)
                        if entry and NAME.match(entry.group(1)):
                            found.append(entry.group(1))
                        if "})" in line:
                            in_map = False
                    elif ICON_MAP.match(line):
                        in_map = True
                    else:
                        prop = ICON_PROP.match(line)
                        if prop:
                            found += names_in(prop.group(2))
                        elif icon_depths and icon_depths[-1] == depth:
                            text = re.match(r"^\s*text\s*:\s*(.+)$", line)
                            if text:
                                found += names_in(text.group(1))
                for name in found:
                    if name not in known:
                        error(path, number, f"no icon named {name!r}")
                if re.search(r"\bStyledIcon\s*\{", code) and not re.search(r"\bStyledIcon\s*\{.*\}", code):
                    icon_depths.append(depth + 1)
                depth += code.count("{") - code.count("}")
                while icon_depths and depth < icon_depths[-1]:
                    icon_depths.pop()


def main():
    if not CATALOG.exists():
        print(f"error    {CATALOG.relative_to(ROOT)}: missing: run scripts/generate_icons.py")
        return 1
    known = {entry[0] for entry in json.loads(CATALOG.read_text())}
    check_schema(known)
    check_qml(known)
    for line in errors:
        print(line)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
