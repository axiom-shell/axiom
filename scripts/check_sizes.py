#!/usr/bin/env python3
"""Keep sizes outside the bars on the Interface scale and Density.

Text grows with `Widget.scale` (Appearance.fontSize), and so do the
`Widget` sizes (height, padding, spacing, iconButton, smallHeight,
smallPadding, `Widget.px(n)`). A size written as a bare number stays the
same at every scale, so next to the text around it it comes out cramped at
150 % and loose at 75 %. This warns (never fails) on:

  - a size property (one named …width, …height, …size, …spacing,
    …margin(s), …padding, …pad, …radius, …length, …thickness or …inset: width,
    Layout.preferredHeight, anchors.leftMargin, textSize), or a
    `property int|real` of that name, set to a number of 3 or more
  - a number of 3 or more inside such a property's expression, added,
    subtracted or chosen (`Widget.height - 4`, `Math.max(6, …)`,
    `wide ? 8 : 4`, `-48`). Factors are fine: a number multiplied or
    divided by, or inside a group something is multiplied by
    (`fontSize * (a ? 4 : 3)`, but not `(height - 4) / 2`),
    and grid units (`span(8)`), Widget.px / fontSizeBy arguments
  - a font size offset, `Appearance.fontSize + n` (or fontSizeLarge):
    the offset stays the same at every scale; use
    `Appearance.fontSizeBy(n)`

Left alone: qml/components/bar/ (each bar sizes its own widgets),
qml/components/methods/ (pure helpers: sizes are handed in), hairlines
(0–2 px, `border.width` / `borderWidth`) and `sourceSize` (an image's
decoded resolution). A size that is measured against the screen or a
measuring font, a placeholder or a layout weight is a false positive:
ignore the warning.

  scripts/check_sizes.py            warnings only (always exit 0)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIRS = ["qml/components", "qml/shell"]
SKIP = ["qml/components/bar/", "qml/components/methods/"]

SIZE_WORD = r"(?:[wW]idth|[hH]eight|[sS]ize|[sS]pacing|[mM]argins?|[pP]adding|[rR]adius|[lL]ength|[tT]hickness|[pP]ad|[iI]nset)"
# width, Layout.preferredHeight, anchors.leftMargin, textSize, troughHeight, …
SIZE_NAME = r"(?:[\w.]*" + SIZE_WORD + r")"
NUMBER = r"(\d+(?:\.\d+)?)"
# `name: 12` (an assignment) or `property int name: 12` (a default)
ASSIGN = re.compile(r"^\s*(?:readonly\s+)?(?:property\s+(?:int|real)\s+)?(" + SIZE_NAME + r")\s*:\s*" + NUMBER + r"\s*(?://.*)?$")
# `name: <any expression>`, for the numbers inside it
EXPR = re.compile(r"^\s*(?:readonly\s+)?(?:property\s+(?:int|real)\s+)?(" + SIZE_NAME + r")\s*:\s*(.+?)\s*(?://.*)?$")
LITERAL = re.compile(r"(?<![\w.\[])\d+(?:\.\d+)?(?![\w.\]])")
# Calls whose numbers are no px: grid units, already scaled, colors
NOT_PX = ("Widget.px", "fontSizeBy", "span", "Qt.size", "Qt.rgba", "Qt.alpha")
EXEMPT = ("border.width", "borderWidth", "sourceSize")
# `Appearance.fontSize - 2`, not `Appearance.fontSize * 2`
FONT_OFFSET = re.compile(r"Appearance\.(fontSize(?:Large)?)\s*[-+]\s*\d")


def _scaled_by(text, at):
    """Whether `text[:at]` ends in a factor's operator (`*`, `/`), past a
    call's name (`/ Math.max(`)."""
    before = re.sub(r"[\w.]+$", "", text[:at].rstrip()).rstrip()
    return before[-1:] in ("*", "/")


def expression_literals(rhs):
    """The px numbers (3 or more) in a size expression: each one added,
    subtracted or chosen, not a factor or inside a NOT_PX call."""
    stack, groups = [], []
    for i, c in enumerate(rhs):
        if c == "(":
            stack.append(i)
        elif c == ")" and stack:
            groups.append((stack.pop(), i))
    found = []
    for m in LITERAL.finditer(rhs):
        if float(m.group(0)) < 3:
            continue
        after = rhs[m.end():].lstrip()[:1]
        if rhs[:m.start()].rstrip()[-1:] in ("*", "/") or after in ("*", "/"):
            continue
        enclosing = [(o, c) for o, c in groups if o < m.start() < c]
        # A group something is multiplied or divided by holds factors; a
        # group that is multiplied (`(height - 4) / 2`) is px all the same
        if any(_scaled_by(rhs, o) or rhs[:o].rstrip().endswith(NOT_PX) for o, c in enclosing):
            continue
        found.append((m.start(), m.group(0)))
    return found


def find_literals(text):
    """(line number, property, value) for each literal size in QML text."""
    found = []
    for n, line in enumerate(text.split("\n"), 1):
        if any(name in line for name in EXEMPT):
            continue
        m = ASSIGN.match(line)
        if m:
            if float(m.group(2)) >= 3:
                found.append((n, m.group(1), m.group(2)))
        elif e := EXPR.match(line):
            for _, value in expression_literals(e.group(2)):
                found.append((n, e.group(1), value))
        offset = FONT_OFFSET.search(line)
        if offset:
            found.append((n, offset.group(1), offset.group(0)))
    return found


def main():
    errors = []
    for d in DIRS:
        for path in sorted((ROOT / d).rglob("*.qml")):
            rel = path.relative_to(ROOT).as_posix()
            if any(rel.startswith(s) for s in SKIP):
                continue
            for n, name, value in find_literals(path.read_text()):
                errors.append(f"{rel}:{n}: {name}: {value}")
    for e in errors:
        print(e)
    if errors:
        print(
            f"\n{len(errors)} literal size(s) (warning): prefer a Widget size (height, padding, "
            "spacing, iconButton, smallHeight, smallPadding), Widget.px(n) or "
            "Appearance.fontSizeBy(n)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
