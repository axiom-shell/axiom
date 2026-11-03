#!/usr/bin/env python3
"""Write qml/config/themes/template/theme.json, the theme a new one is copied
from: the fallback palette and every semantic name with its dark map, from
qml/config/json/theme-defaults.json (the same defaults that fill what a theme
leaves out). It sits in a subfolder so ThemeManager's scan (showDirs:
false) doesn't list it. The pre-commit hook runs this; never edit the
template by hand.

  scripts/gen_theme_template.py           rewrite it if stale
  scripts/gen_theme_template.py --check   exit 1 if stale, writing nothing
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULTS = ROOT / "qml" / "config" / "json" / "theme-defaults.json"
TEMPLATE = ROOT / "qml" / "config" / "themes" / "template" / "theme.json"


def template():
    defaults = json.loads(DEFAULTS.read_text())
    return {
        "name": "",
        "author": "",
        "variant": "dark",
        "paired": "",
        "colors": defaults["colors"],
        "semantic": defaults["semantic"]["dark"],
    }


def main():
    expected = json.dumps(template(), ensure_ascii=False, indent=2) + "\n"
    current = TEMPLATE.read_text(encoding="utf-8") if TEMPLATE.exists() else None
    if current == expected:
        return 0
    rel = TEMPLATE.relative_to(ROOT)
    if "--check" in sys.argv:
        print(f"{rel}: stale: run scripts/gen_theme_template.py")
        return 1
    TEMPLATE.parent.mkdir(exist_ok=True)
    tmp = TEMPLATE.with_name(f".{TEMPLATE.name}.tmp")
    tmp.write_text(expected, encoding="utf-8")
    os.replace(tmp, TEMPLATE)
    print(f"{rel}: rewritten")
    return 0


if __name__ == "__main__":
    sys.exit(main())
