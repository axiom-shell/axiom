#!/usr/bin/env python3
"""Build qml/config/json/emoji.json, the launcher's emoji list (";" or /emoji).

Downloads Unicode's emoji-test.txt (the emoji, their names and groups, in
the standard order) and CLDR's English annotations (search keywords), and
keeps the fully-qualified emoji without skin tones. The result is committed:
nothing downloads at runtime. Run it again for a new Unicode release.

  scripts/generate_emoji.py [--version latest|16.0]

Each entry is {"e": emoji, "n": name, "g": group, "k": [keywords]}, one per
line so a regeneration diffs readably.
"""
import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "qml" / "config" / "json" / "emoji.json"

EMOJI_TEST = "https://unicode.org/Public/emoji/{version}/emoji-test.txt"
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json"
ANNOTATIONS = [
    (CLDR + "/cldr-annotations-full/annotations/en/annotations.json", "annotations"),
    (CLDR + "/cldr-annotations-derived-full/annotationsDerived/en/annotations.json", "annotationsDerived"),
]

SKIN_TONES = {chr(c) for c in range(0x1F3FB, 0x1F400)}
# "1F600 ; fully-qualified # 😀 E1.0 grinning face"
LINE = re.compile(r"^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E\d+\.\d+\s+(.+)$")


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read().decode("utf-8")


def bare(emoji):
    """CLDR keys mostly leave out the emoji presentation selector"""
    return emoji.replace("️", "")


def keywords():
    found = {}
    for url, key in ANNOTATIONS:
        data = json.loads(fetch(url))[key]["annotations"]
        for emoji, entry in data.items():
            found.setdefault(bare(emoji), entry.get("default", []))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", default="latest", help="Unicode emoji version (default: latest)")
    args = parser.parse_args()

    words = keywords()
    entries = []
    group = ""
    for line in fetch(EMOJI_TEST.format(version=args.version)).splitlines():
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            continue
        match = LINE.match(line)
        if not match or group == "Component":
            continue
        emoji, name = match.groups()
        if SKIN_TONES & set(emoji):
            continue
        name = name.strip()
        # Flags are named "flag: Japan"
        name = name.replace("flag: ", "flag ")
        extra = [k for k in words.get(bare(emoji), []) if k.lower() != name.lower()]
        entries.append({"e": emoji, "n": name, "g": group, "k": extra})

    if len(entries) < 1000:
        sys.exit(f"Only {len(entries)} emoji parsed: the source format may have changed")
    OUT.write_text("[\n" + ",\n".join(json.dumps(e, ensure_ascii=False) for e in entries) + "\n]\n", encoding="utf-8")
    print(f"Wrote {len(entries)} emoji to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
