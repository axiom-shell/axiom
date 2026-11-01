#!/usr/bin/env python3
"""Build the bundled icon font and its catalog from Google's Material Symbols.

Downloads Material Symbols Rounded (the variable font, its codepoints and
licence) at a pinned commit of google/material-design-icons and writes:
- assets/fonts/MaterialSymbolsRounded.ttf: the font with only the FILL and
  wght axes StyledIcon sets (GRAD 0, opsz 24, as Qt drew it anyway), about a
  third of the size, renamed "Axiom Material Symbols" so a system copy of
  the font can never be drawn in its place (Apache-2.0 allows both)
- assets/fonts/LICENSE and assets/fonts/VERSION (the commit)
- config/json/material-symbols.json: the icon picker's catalog (IconManager),
  each icon as [name, "search words"], most popular first. The words are
  Google's tags (fonts.google.com's metadata), split into words, less the
  name's own and the few that tag most icons ("icon", "symbol", ...)

The results are committed: nothing downloads at runtime. Needs fonttools
(`pip install fonttools` / python-fonttools), only to run this.

  scripts/generate_icons.py [--commit <sha>]
"""
import argparse
import collections
import io
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONT_OUT = ROOT / "assets" / "fonts" / "MaterialSymbolsRounded.ttf"
LICENSE_OUT = ROOT / "assets" / "fonts" / "LICENSE"
VERSION_OUT = ROOT / "assets" / "fonts" / "VERSION"
CATALOG_OUT = ROOT / "config" / "json" / "material-symbols.json"

# The commit the bundled font comes from: bump it (or pass --commit) for a
# newer font
COMMIT = "10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7"
RAW = "https://raw.githubusercontent.com/google/material-design-icons/{commit}/"
FONT = "variablefont/MaterialSymbolsRounded[FILL,GRAD,opsz,wght]"
METADATA = "https://fonts.google.com/metadata/icons?key=material_symbols&incomplete=true"
FAMILY = "Axiom Material Symbols"
STYLE = "Rounded"
# Words tagging more than this share of icons don't narrow a search
COMMON = 0.10


def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def raw(commit, path):
    return fetch(RAW.format(commit=commit) + urllib.parse.quote(path))


def build_font(data):
    try:
        from fontTools.ttLib import TTFont
        from fontTools.varLib import instancer
    except ImportError:
        sys.exit("fonttools is needed: pip install fonttools (Arch: python-fonttools)")
    font = TTFont(io.BytesIO(data))
    font = instancer.instantiateVariableFont(font, {"GRAD": 0, "opsz": 24})
    axes = sorted(axis.axisTag for axis in font["fvar"].axes)
    if axes != ["FILL", "wght"]:
        sys.exit(f"Unexpected axes left: {axes}")
    names = font["name"]
    full = f"{FAMILY} {STYLE}"
    for record in list(names.names):
        if record.nameID in (1, 16):
            names.setName(FAMILY, record.nameID, record.platformID, record.platEncID, record.langID)
        elif record.nameID in (2, 17):
            names.setName(STYLE, record.nameID, record.platformID, record.platEncID, record.langID)
        elif record.nameID == 4:
            names.setName(full, record.nameID, record.platformID, record.platEncID, record.langID)
        elif record.nameID == 6:
            names.setName(full.replace(" ", ""), record.nameID, record.platformID, record.platEncID, record.langID)
    FONT_OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(FONT_OUT)


def catalog(names):
    try:
        text = fetch(METADATA).decode("utf-8")
        icons = {icon["name"]: icon for icon in json.loads(text[text.index("{"):])["icons"]}
    except Exception as error:  # the metadata is unofficial: fall back to names
        print(f"No tags ({error}): the catalog has names only", file=sys.stderr)
        icons = {}
    words = {}
    counts = collections.Counter()
    for name in names:
        own = set(name.split("_"))
        tags = icons.get(name, {}).get("tags", [])
        found = {w for tag in tags for w in tag.lower().replace("-", " ").split() if len(w) > 1} - own
        words[name] = found
        counts.update(found)
    common = {w for w, c in counts.items() if c > len(names) * COMMON}
    order = sorted(names, key=lambda n: (-icons.get(n, {}).get("popularity", 0), n))
    return [[name, " ".join(sorted(words[name] - common))] for name in order]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--commit", default=COMMIT, help=f"google/material-design-icons commit (default: {COMMIT[:12]})")
    args = parser.parse_args()

    codepoints = raw(args.commit, FONT + ".codepoints").decode("utf-8")
    names = sorted({line.split()[0] for line in codepoints.splitlines() if line.strip()})
    if len(names) < 3000:
        sys.exit(f"Only {len(names)} icon names parsed: the source format may have changed")

    build_font(raw(args.commit, FONT + ".ttf"))
    LICENSE_OUT.write_bytes(raw(args.commit, "LICENSE"))
    VERSION_OUT.write_text(f"google/material-design-icons {args.commit}\n")

    entries = catalog(names)
    CATALOG_OUT.write_text("[\n" + ",\n".join(json.dumps(e) for e in entries) + "\n]\n", encoding="utf-8")
    print(f"Wrote {FONT_OUT.relative_to(ROOT)} ({FONT_OUT.stat().st_size // 1024} KiB) and {len(entries)} icons to {CATALOG_OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
