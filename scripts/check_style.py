#!/usr/bin/env python3
"""The style lint: keep colours, text sizes, weights and text rendering on the Style roles.

Every hit fails (docs/dev/core/style.md; the checks are listed in
docs/dev/testing.md > The checks). The rules are `RULES`: each id and what it fails.

Every hit fails; a line is waived with `// style-exempt: <reason>`, a file with an
entry in scripts/style-exceptions.json (rules and reason; an entry no longer needed
fails). A public `Style` member nothing reads fails too.

  scripts/check_style.py                  every hit, then the role check; exit 1 on any
  scripts/check_style.py --files F...     the hits of these files only; exit 1 on any
  scripts/check_style.py --roles          only the role check (Style members nothing reads)
"""
import fnmatch
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import qml_modules  # noqa: E402

ROOT = qml_modules.ROOT
QML = qml_modules.QML_ROOT
EXCEPTIONS = ROOT / "scripts" / "style-exceptions.json"

RULES = {
    "theme-read": "a `Theme.` read (but the pickers' passthroughs), `Theme.resolveColor(` included",
    "raw-color": "Qt.alpha/rgba/hsla/hsva/lighter/darker/tint, a quoted hex or CSS color",
    "fractional-opacity": "a fractional opacity (a property named opacity or ...Opacity, an animation on it)",
    "text-size": "fontSizeBy(, fontSizeLarge, Appearance.fontSize as a text/icon size, a numeric textSize, a fitted size without its Style.type floor",
    "font-weight": "font.bold; font.weight set to anything but a role's weight",
    "color-function": "a color function called in UI (Tone., StyleTokens., Qt.color(, Utils.contrast(, ...); in a service or reader: a stored resolved color",
    "color-property": "a color property set to anything but a Style role, an ink, \"transparent\" or a property of the file itself",
    "clip-color": "a ClippingRectangle with no color (its default is white)",
    "palette-part": "a Qt Quick Controls visual that leaves a part to the Qt palette",
    "canvas-revision": "a Canvas painting from Style with no Style.revision in its repaint key",
    "redeclared-property": "a block re-declaring a property its type or a base of it declares (every .qml)",
    "global-text-role": "a global text role (or a tone its ink lacks) inside a Surface of a non-reading tone",
    "bold-styled-text": "font.bold on a StyledText or a type derived from it (every .qml)",
    "styled-text-overflow": "wrapMode/elide/maximumLineCount on a StyledText: overflow:/maxLines:",
    "dead-elide": "a dead elide: an eliding StyledText in a Row(Layout) with no bound on it",
    "text-render-type": "a raw Text-family block with no TextRender renderType (every .qml)",
    "layer-over-content": "layer.enabled / layer.effect over content",
    "unhosted-scale": "a scale over content with no `contentZoom` host",
    "widget-radius": "`Widget.radius` read in UI: use Style.radius / Style.radiusInner",
    "transparent-glide": "a color with a glide (ColorGlide / Behavior / ColorAnimation) bound to a bare \"transparent\": the fade passes through black; rest on Tone.cleared(<fill>)",
    "trough-read": "`Style.trough` read outside the trough pieces (StyledVolumeBar, StyledSlider, LevelMeter, SegmentMeter, PercentageCircle): draw the bar with one of them",
}
EVERYWHERE = {"redeclared-property", "bold-styled-text", "text-render-type"}
TROUGH_PIECES = {"StyledVolumeBar", "StyledSlider", "LevelMeter", "SegmentMeter", "PercentageCircle"}
STYLE_LAYER_PIECES = {"Surface", "StateLayer", "FocusRing", "Skeleton", "StyledScrollIndicator", "BackdropScrim"}
STYLE_LAYER_CONFIG = {"Style", "StyleInk", "StyleTextRole", "BarColors", "Theme", "Appearance", "BarsConfig", "BarStyle"}

# The CSS colour names raw-color refuses quoted ("transparent" stays allowed)
CSS_NAMES = """aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood
cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey
darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey
darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite
gold goldenrod gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon
lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue
lightslategray lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid
mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin
navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff
peru pink plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue
slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white whitesmoke yellow
yellowgreen""".split()

THEME_READ = re.compile(r"(?<![\w.])Theme\.(?!(?:baseColorNames|roles|name|stringToColorMap)\b)")
RAW_COLOR = re.compile(r"Qt\.(?:alpha|rgba|hsla|hsva|lighter|darker|tint)\(|[\"']#[0-9a-fA-F]{3,8}[\"']|[\"'](?:" + "|".join(CSS_NAMES) + r")[\"']")
TEXT_SIZE_CALLS = re.compile(r"fontSizeBy\(|fontSizeLarge")
TEXT_SIZE_NAMES = ("textSize", "font.pixelSize", "iconSize")
COLOR_FUNCTION_CALLS = re.compile(r"(?<![\w.])(?:Tone|StyleTokens|BarWidgetStyle)\.|Style\.shadow(?:Base)?Color\(|BarColors\.(?:widgetColors|pulseLadder)\(|"
                      r"Qt\.color\(|Utils\.(?:contrast|luminance|getContrastColor|isColorDark|fadeable)\(")
COLOR_FUNCTION_STORED = re.compile(r"String\(.*?(?:(?<![\w.])(?:Theme|Style)\.|\w+Config\.\w*(?:[Cc]olor|[Bb]order))")
COLOUR_PROPS = {"textColor", "color", "border.color", "iconColor", "fillColor", "litColor", "lineColor", "valueColor", "statusColor"}
READING_TONES = {"page", "sunken", "surface", "raised"}
GLOBAL_ROLES = re.compile(r"Style\.(?:text|textMuted|textFaint|textDisabled|textAccent|(?:success|warning|error|info)Text|divider|accent|accentAlt|"
                          r"success|warning|error|info|series|focusRing)\b")
INK_LACKS = {"disabled", "success", "warning", "error", "info"}
TEXT_BLOCKS = {"Text", "TextInput", "TextEdit", "TextField", "TextArea"}
NEEDS = {"Popup": ("background",), "ComboBox": ("background",), "ScrollIndicator": ("contentItem",), "ScrollBar": ("contentItem",),
         "ScrollView": ("ScrollBar.vertical:", "ScrollBar.vertical {", "ScrollBar.vertical.policy: ScrollBar.AlwaysOff"),
         "TextField": ("selectionColor",), "TextArea": ("selectionColor",), "TextInput": ("selectionColor",), "TextEdit": ("selectionColor",)}
EXEMPT = re.compile(r"//\s*style-exempt:\s*\S")


# ---- reading a file ----

def lex(text):
    """(S, T): the text without comments, and that with the insides of strings blanked too; newlines kept."""
    s, t = [], []
    i, n = 0, len(text)
    quote = None
    while i < n:
        c = text[i]
        if quote:
            if c == "\\" and i + 1 < n:
                s.append(text[i:i + 2])
                t.append("  " if text[i + 1] != "\n" else " \n")
                i += 2
                continue
            if c == quote or c == "\n":
                quote = None if c == quote else quote
                s.append(c)
                t.append(c)
            else:
                s.append(c)
                t.append(" ")
            i += 1
            continue
        if c in "\"'`":
            quote = c
            s.append(c)
            t.append(c)
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            blank = re.sub(r"[^\n]", " ", text[i:j])
            s.append(blank)
            t.append(blank)
            i = j
        else:
            s.append(c)
            t.append(c)
            i += 1
    return "".join(s), "".join(t)


class Node:
    """One brace block: a typed object (kind "obj"), a group property (`font { }`) or a JS body."""

    def __init__(self, kind, typ, header, open_at, parent):
        self.kind, self.type, self.header, self.open_at = kind, typ, header, open_at
        self.close_at = None
        self.parent = parent
        self.children = []
        self.inline = None
        self.on = None
        self.root = False
        self.line = self.end_line = 0
        self.props = []  # (name, line, value)
        self.decls = {}  # declared property/alias/signal name -> line

    def prop(self, name):
        for n, line, value in self.props:
            if n == name:
                return value
        return None

    def has(self, name):
        return any(n == name for n, _, _ in self.props)

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()


TYPED = re.compile(r"(?:^|[\s:;({,\[?])((?:[a-z]\w*\.)*[A-Z]\w*)(?:\s+on\s+([\w.]+))?\s*$")
INLINE = re.compile(r"component\s+(\w+)\s*:\s*((?:[a-z]\w*\.)*[A-Z]\w*)\s*$")
GROUP = re.compile(r"(?:^|[;\s])([a-z]\w*)\s*$")
JS_WORDS = {"else", "try", "finally", "do"}
DECL = re.compile(r"^(?:(?:readonly|required|default|final|virtual|override)\s+)*property\s+(?:alias\s+|<[^>]*>\s*|[\w.<>]+\s+)?(\w+)\s*(?::\s*(.*))?$", re.S)
SIGNAL = re.compile(r"^signal\s+(\w+)")
PROP = re.compile(r"^([\w.]+)\s*:\s*(.*)$", re.S)


def line_starts(text):
    starts = [0]
    for m in re.finditer("\n", text):
        starts.append(m.end())
    return starts


def line_of(starts, pos):
    lo, hi = 0, len(starts)
    while lo < hi - 1:
        mid = (lo + hi) // 2
        if starts[mid] <= pos:
            lo = mid
        else:
            hi = mid
    return lo + 1


def parse(text):
    """The brace tree of a file: (top-level nodes, S, T, line starts)."""
    s, t = lex(text)
    starts = line_starts(t)
    top, stack = [], []
    for m in re.finditer(r"[{}]", t):
        i = m.start()
        if m.group() == "{":
            ls = starts[line_of(starts, i) - 1]
            prefix = t[ls:i]
            prefix = re.split(r"[;{}]", prefix)[-1]
            kind, typ, node = "js", None, None
            inline = INLINE.search(prefix)
            typed = TYPED.search(prefix)
            if inline and (not stack or stack[-1].kind != "js"):
                node = Node("obj", inline.group(2), prefix, i, stack[-1] if stack else None)
                node.inline = inline.group(1)
            elif typed and (not stack or stack[-1].kind != "js"):
                node = Node("obj", typed.group(1), prefix, i, stack[-1] if stack else None)
                node.on = typed.group(2)
            else:
                g = GROUP.search(prefix)
                if g and g.group(1) not in JS_WORDS and stack and stack[-1].kind == "obj" and prefix.strip() == g.group(1):
                    node = Node("group", g.group(1), prefix, i, stack[-1])
            if node is None:
                node = Node("js", None, prefix, i, stack[-1] if stack else None)
            node.line = line_of(starts, i)
            if typed and node.kind == "obj":
                node.line = line_of(starts, ls + typed.start(1))
            (stack[-1].children if stack else top).append(node)
            stack.append(node)
        elif stack:
            node = stack.pop()
            node.close_at = i
            node.end_line = line_of(starts, i)
    for node in stack:  # unbalanced: close at the end
        node.close_at = len(t) - 1
        node.end_line = line_of(starts, len(t) - 1)
    first = True
    for node in top:
        if node.kind == "obj" and node.inline is None and first:
            node.root = True
            first = False
    for node in top:
        for sub in node.walk():
            if sub.kind in ("obj", "group"):
                fill_body(sub, s, t, starts)
    return top, s, t, starts


CONT_END = re.compile(r"(?:\?|:|&&|\|\||\?\?|\+|-|\*|/|,|=|\()$")
CONT_START = re.compile(r"[?:.,)]|&&|\|\||\+|\*|/")


def statements(chars):
    """[(offset, text)]: the statements of a block body, split at `;` and at a newline outside brackets that no
    operator continues."""
    out, cur, depth, start = [], [], 0, None
    for pos, c in enumerate(chars):
        if start is None and not c.isspace():
            start = pos
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        end = False
        if depth <= 0 and c == ";":
            end = True
        else:
            cur.append(c)
            if depth <= 0 and c == "\n":
                joined = "".join(cur).strip()
                if joined and not CONT_END.search(joined) and not CONT_START.match(chars[pos + 1:].lstrip()[:2]):
                    end = True
        if end:
            stmt = "".join(cur).strip()
            if stmt and start is not None:
                out.append((start, stmt))
            cur, start = [], None
    stmt = "".join(cur).strip()
    if stmt and start is not None:
        out.append((start, stmt))
    return out


def fill_body(node, s, t, starts):
    """Statements directly in a block: its declarations and `name: value` lines."""
    base = node.open_at + 1
    body = list(s[base:node.close_at])
    for sub in node.children:
        for k in range(sub.open_at + 1 - base, sub.close_at - base):
            if body[k] != "\n":
                body[k] = " "
    for offset, stmt in statements("".join(body)):
        line = line_of(starts, base + offset)
        d = DECL.match(stmt)
        if d:
            node.decls[d.group(1)] = line
            if d.group(2) is not None:
                node.props.append((d.group(1), line, d.group(2).strip()))
            continue
        sg = SIGNAL.match(stmt)
        if sg:
            node.decls[sg.group(1)] = line
            continue
        p = PROP.match(stmt)
        if p:
            node.props.append((p.group(1), line, p.group(2).strip()))


# ---- values: the operand algorithm of font-weight and color-property ----

def top_split(expr, op):
    """Split `expr` at the top-level occurrences of `op` (outside brackets and strings)."""
    parts, depth, quote, last, i = [], 0, None, 0, 0
    while i < len(expr):
        c = expr[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'`":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif depth == 0 and expr.startswith(op, i):
            parts.append(expr[last:i])
            i += len(op) - 1
            last = i + 1
        i += 1
    parts.append(expr[last:])
    return parts


def ternary(expr):
    """(a, b) of `c ? a : b` at top level, else None."""
    depth, quote, q_at, i = 0, None, None, 0
    while i < len(expr):
        c = expr[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'`":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif depth == 0 and c == "?" and not expr.startswith("??", i) and not expr.startswith("?.", i) and not expr.startswith("??", i - 1 if i else 0):
            q_at = i
            break
        elif depth == 0 and expr.startswith("??", i):
            i += 1
        i += 1
    if q_at is None:
        return None
    depth, nest, quote = 0, 0, None
    i = q_at + 1
    while i < len(expr):
        c = expr[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'`":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif depth == 0 and c == "?" and not expr.startswith("??", i) and not expr.startswith("?.", i):
            nest += 1
        elif depth == 0 and c == ":":
            if nest == 0:
                return expr[q_at + 1:i], expr[i + 1:]
            nest -= 1
        i += 1
    return None


def strip_parens(expr):
    expr = expr.strip()
    while expr.startswith("(") and expr.endswith(")"):
        depth, ok = 0, True
        for i, c in enumerate(expr):
            depth += c == "("
            depth -= c == ")"
            if depth == 0 and i < len(expr) - 1:
                ok = False
                break
        if not ok:
            break
        expr = expr[1:-1].strip()
    return expr


def leaves(expr):
    """The operands of a value: both branches of a conditional, both sides of `||` and `??`, the last of `&&`."""
    expr = strip_parens(expr.strip().rstrip(";"))
    if not expr:
        return []
    t = ternary(expr)
    if t:
        return leaves(t[0]) + leaves(t[1])
    for op in ("||", "??"):
        parts = top_split(expr, op)
        if len(parts) > 1:
            return [x for p in parts for x in leaves(p)]
    parts = top_split(expr, "&&")
    if len(parts) > 1:
        return leaves(parts[-1])
    return [expr]


def first_arg(call):
    m = re.match(r"^[\w.]+\(", call)
    if not m:
        return None
    inner = call[m.end():]
    depth = 0
    for i, c in enumerate(inner):
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return inner[:i]
            depth -= 1
        elif c == "," and depth == 0:
            return inner[:i]
    return inner


LITERAL = re.compile(r'^(?:-?\d[\d.]*|true|false|null|undefined)$')
BARE = re.compile(r"^[A-Za-z_]\w*$")


def colour_leaf_ok(leaf, ids):
    leaf = leaf.strip()
    if not leaf or LITERAL.match(leaf):
        return True
    if leaf in ('"transparent"', "'transparent'"):
        return True
    if leaf.startswith("Style."):
        if leaf.startswith("Style.edgeFill("):
            arg = first_arg(leaf[len("Style."):])
            return arg is not None and all(colour_leaf_ok(x, ids) for x in leaves(arg))
        return True
    if re.match(r"^(?:\w+\.)?ink\.\w+$", leaf):
        return True
    if leaf.startswith("root."):
        return True
    if re.match(r"^\w+Config\.", leaf):
        return True
    m = re.match(r"^(\w+)\.\w", leaf)
    if m and m.group(1) in ids:
        return True
    if BARE.match(leaf):
        return True
    return False


def weight_leaf_ok(leaf):
    leaf = leaf.strip()
    if not leaf or leaf.startswith("root."):
        return True
    return bool(re.match(r"^Style\.(?:weight\w+|role\w+\.weight)$", leaf))


# ---- the type index ----

class Index:
    """Repo QML types by file stem and inline component, to resolve a block's base chain."""

    def __init__(self, files):
        self.trees = {}
        self.by_stem = defaultdict(list)
        self.inline = defaultdict(dict)  # path -> name -> node
        self.root = {}  # path -> root node
        for f in files:
            rel = f.relative_to(ROOT).as_posix()
            text = f.read_text(errors="replace")
            top, s, t, starts = parse(text)
            self.trees[rel] = (top, s, t, starts, text)
            self.by_stem[f.stem].append(rel)
            for top_node in top:
                for node in top_node.walk():
                    if node.kind == "obj" and node.inline:
                        self.inline[rel][node.inline] = node
                    if node.root:
                        self.root[rel] = node

    def resolve(self, name, rel):
        """The (path, inline-name or None) of a repo type named `name` as seen from file `rel`, or None."""
        if name in self.inline.get(rel, {}):
            return (rel, name)
        cands = self.by_stem.get(name, [])
        if not cands:
            return None
        folder = rel.rsplit("/", 1)[0]
        for pref in (folder, "qml/components/reusable", "qml/components/forms"):
            for c in cands:
                if c.rsplit("/", 1)[0] == pref:
                    return (c, None)
        if len(cands) == 1:
            return (cands[0], None)
        return None

    def base_of(self, key):
        path, inline = key
        node = self.inline[path][inline] if inline else self.root.get(path)
        return (node.type, path) if node else None

    def chain(self, typ, rel):
        """[(name, key or None)] from `typ` up through repo types."""
        out, seen = [], set()
        while typ:
            key = self.resolve(typ, rel)
            out.append((typ, key))
            if key is None or key in seen:
                break
            seen.add(key)
            nxt = self.base_of(key)
            if not nxt:
                break
            typ, rel = nxt
        return out

    def derives(self, typ, rel, target):
        return any(n == target for n, _ in self.chain(typ, rel))

    def decls_of(self, key):
        path, inline = key
        node = self.inline[path][inline] if inline else self.root.get(path)
        return node.decls if node else {}


# ---- scope ----

def scope_of(rel):
    """The rules that apply to a file (every file gets `EVERYWHERE`)."""
    p = rel
    rules = set(EVERYWHERE)
    name = Path(p).stem
    if p.startswith(("qml/services/", "qml/config/")):
        if name in STYLE_LAYER_CONFIG or p == "qml/services/core/ThemeManager.qml":
            return rules
        return rules | {"theme-read", "raw-color", "color-function"}
    ui = p.startswith(("qml/components/", "qml/shell/")) or p in ("qml/shell.qml", "qml/greeter.qml")
    if not ui:
        return rules
    if p.startswith("qml/components/methods/"):
        return rules
    if p.startswith("qml/components/reusable/") and name in STYLE_LAYER_PIECES:
        return rules
    m = re.match(r"qml/components/bar/widgets/([^/]+)/", p)
    if m and m.group(1) != "base":
        return rules
    rules |= {"text-size", "font-weight", "color-function", "color-property", "clip-color", "palette-part", "canvas-revision", "global-text-role", "styled-text-overflow", "dead-elide", "layer-over-content", "unhosted-scale", "widget-radius", "transparent-glide", "trough-read"}
    if p.startswith(("qml/components/bar/look/", "qml/components/bar/widgets/base/")):
        return rules - {"color-function"}  # the bar's drawing kit draws the palette's colours (`check_style` › `color-function`)
    return rules | {"theme-read", "raw-color", "fractional-opacity", "color-function"}


def all_files():
    return [f for f in qml_modules.qml_files() if f.exists()]


# ---- the rules ----

def add(hits, line, rule, text, n=1):
    hits.append((line, rule, text, n))


def scan(rel, index):
    """Every hit of a file before waivers: [(line, rule, text, count)]."""
    top, s, t, starts, text = index.trees[rel]
    rules = scope_of(rel)
    slines = s.split("\n")
    raw = text.split("\n")
    hits = []
    ids = set(re.findall(r"\bid\s*:\s*(\w+)", t))
    nodes = [n for tn in top for n in tn.walk() if n.kind in ("obj", "group")]

    # per-line regex rules
    for i, line in enumerate(slines, 1):
        if "theme-read" in rules:
            for _ in THEME_READ.finditer(line):
                add(hits, i, "theme-read", line.strip())
        if "widget-radius" in rules and re.search(r"(?<![\w.])Widget\.radius\b", line):
            add(hits, i, "widget-radius", "Widget.radius: use Style.radius / Style.radiusInner")
        if "trough-read" in rules and re.search(r"(?<![\w.])Style\.trough\b", line) and not (rel.startswith("qml/components/reusable/") and Path(rel).stem in TROUGH_PIECES):
            add(hits, i, "trough-read", "Style.trough outside the trough pieces: draw the bar with StyledVolumeBar, StyledSlider, LevelMeter, SegmentMeter or PercentageCircle")
        if "raw-color" in rules:
            for _ in RAW_COLOR.finditer(line):
                add(hits, i, "raw-color", line.strip())
        if "text-size" in rules:
            fitted = re.search(r"//\s*fitted:", raw[i - 1]) if i - 1 < len(raw) else None
            if fitted:
                m = re.match(r"^\s*(?:textSize|font\.pixelSize|iconSize)\s*:\s*(.*)$", slines[i - 1])
                if m and not re.search(r"Style\.(?:type|icon)\w+", m.group(1)):
                    add(hits, i, "text-size", "a fitted size without its Style.type floor")
            skip_calls = bool(fitted and m)
            if not skip_calls:
                for _ in TEXT_SIZE_CALLS.finditer(line):
                    add(hits, i, "text-size", line.strip())
        if "font-weight" in rules:
            for _ in re.finditer(r"(?<![\w.])font\.bold\b", line):
                add(hits, i, "font-weight", line.strip())
        if "color-function" in rules:
            if not rel.startswith(("qml/services/", "qml/config/")):
                for _ in COLOR_FUNCTION_CALLS.finditer(line):
                    add(hits, i, "color-function", line.strip())
            if rel.startswith(("qml/services/", "qml/config/")) and COLOR_FUNCTION_STORED.search(line):
                add(hits, i, "color-function", line.strip())
        if "layer-over-content" in rules:
            m = re.match(r"^\s*layer\.enabled\s*:\s*(.*)$", line)
            if m and m.group(1).strip() != "false":
                add(hits, i, "layer-over-content", line.strip())
            if re.match(r"^\s*layer\.effect\s*:", line):
                add(hits, i, "layer-over-content", line.strip())
        if "text-render-type" in rules:
            m = re.match(r"^\s*renderType\s*:\s*(.*)$", line)
            if m and not m.group(1).strip().startswith("TextRender."):
                add(hits, i, "text-render-type", line.strip())

    # a text-size line's own value: Appearance.fontSize as a size, a numeric textSize (text-size)
    if "text-size" in rules:
        for node in nodes:
            for name, line, value in node.props:
                if name in TEXT_SIZE_NAMES and (re.search(r"Appearance\.fontSize\b(?!By|Large)", value) or re.fullmatch(r"\d+(?:\.\d+)?", value.strip())):
                    if "fitted:" not in raw[line - 1]:
                        add(hits, line, "text-size", f"{name}: {value}")
            if node.kind == "obj" and node.has("fontSizeMode") and (node.prop("fontSizeMode") or "").strip() != "Text.FixedSize" \
                    and not re.search(r"Style\.type\w+", node.prop("minimumPixelSize") or ""):
                add(hits, node.line, "text-size", "a fontSizeMode block without minimumPixelSize: Style.type*")

    for node in nodes:
        if node.kind == "group":
            if "bold-styled-text" in rules and node.type == "font" and node.has("bold") and node.parent and node.parent.kind == "obj" \
                    and index.derives(node.parent.type, rel, "StyledText"):
                add(hits, node.line, "bold-styled-text", "font { bold }")
            continue
        styled = index.derives(node.type, rel, "StyledText")
        animated = {c.on for c in node.children if c.kind == "obj" and c.on and (c.type in ("ColorGlide", "ColorAnimation")
                    or (c.type == "Behavior" and any(g.type == "ColorAnimation" for g in c.children)))}
        for name, line, value in node.props:
            if "fractional-opacity" in rules and re.search(r"(?:^|\.)\w*[oO]pacity$", name):
                if any(float(x) not in (0.0, 1.0) for x in re.findall(r"(?<![\w.])(\d*\.\d+)", value)):
                    add(hits, line, "fractional-opacity", f"{name}: {value}")
            if "font-weight" in rules and name == "font.weight":
                if not all(weight_leaf_ok(x) for x in leaves(value)):
                    add(hits, line, "font-weight", f"font.weight: {value}")
            if "color-property" in rules and name in COLOUR_PROPS:
                if not all(colour_leaf_ok(x, ids) for x in leaves(value)):
                    add(hits, line, "color-property", f"{name}: {value}")
            if "bold-styled-text" in rules and name == "font.bold" and styled:
                add(hits, line, "bold-styled-text", "font.bold on a StyledText")
            if "styled-text-overflow" in rules and name in ("wrapMode", "elide", "maximumLineCount") and styled:
                add(hits, line, "styled-text-overflow", f"{name}: {value}")
            if "transparent-glide" in rules and name in animated and name not in node.decls and any(x.strip() in ('"transparent"', "'transparent'") for x in leaves(value)):
                add(hits, line, "transparent-glide", f"{name}: {value}: a glide to transparent black; rest on Tone.cleared(<fill>)")
            if "unhosted-scale" in rules and name == "scale" and not zoom_host(node):
                try:
                    one = float(value) == 1.0
                except ValueError:
                    one = False
                if not one:
                    add(hits, line, "unhosted-scale", f"scale: {value}")
        if "fractional-opacity" in rules and node.type and node.type.endswith("Animation"):
            on_opacity = (node.on == "opacity") or (node.prop("property") or "").strip('"\'') == "opacity" \
                or any(a.on == "opacity" for a in ancestors(node))
            if on_opacity:
                for name, line, value in node.props:
                    if name in ("from", "to") and re.fullmatch(r"\d*\.\d+", value.strip()) and float(value) not in (0.0, 1.0):
                        add(hits, line, "fractional-opacity", f"{name}: {value}")
        if "unhosted-scale" in rules and not zoom_host(node):
            if node.type == "Scale" and node.header.strip().startswith("transform"):
                add(hits, node.line, "unhosted-scale", "transform: Scale")
            prop_v = (node.prop("property") or "").strip().strip("\"'")
            props_v = (node.prop("properties") or "")
            if prop_v == "scale" or re.search(r"\bscale\b", props_v):
                add(hits, node.line, "unhosted-scale", "an animation on scale")
        if "clip-color" in rules and node.type == "ClippingRectangle" and not node.has("color"):
            add(hits, node.line, "clip-color", "ClippingRectangle with no color")
        if "palette-part" in rules and node.type in NEEDS:
            need = NEEDS[node.type]
            if node.type == "ScrollView":
                ok = any(x in s[node.open_at:node.close_at] for x in need)
            else:
                ok = any(node.has(x) for x in need)
            if not ok:
                add(hits, node.line, "palette-part", f"{node.type} leaves a part to the Qt palette")
        if "canvas-revision" in rules and node.type == "Canvas" and "Style.revision" not in text:
            for c in node.children:
                if c.kind == "js" and c.header.strip().endswith("onPaint:") and re.search(r"\bStyle\.\w", s[c.open_at:c.close_at]):
                    add(hits, node.line, "canvas-revision", "a Canvas painting from Style with no Style.revision")
        if "text-render-type" in rules and node.type in TEXT_BLOCKS and not any(n == "renderType" and v.strip().startswith("TextRender.") for n, _, v in node.props):
            add(hits, node.line, "text-render-type", f"{node.type} without a TextRender renderType")
        if "dead-elide" in rules and styled and node.parent and node.parent.kind == "obj" and node.parent.type in ("RowLayout", "Row"):
            overflow = (node.prop("overflow") or "").strip()
            elide = (node.prop("elide") or "").strip()
            eliding = overflow == '"line"' or (elide and elide != "Text.ElideNone")
            bounded = (node.prop("Layout.fillWidth") or "").strip() == "true" or any(node.has(x) for x in ("Layout.maximumWidth", "Layout.preferredWidth", "width"))
            if eliding and not bounded:
                add(hits, node.line, "dead-elide", "an eliding text with no bound in a row")

    # redeclared-property: a block re-declaring what its type or a base declares
    if "redeclared-property" in rules:
        for node in nodes:
            if node.kind != "obj" or not node.decls:
                continue
            for name, key in index.chain(node.type, rel):
                if key is None:
                    continue
                base = index.decls_of(key)
                for d, line in node.decls.items():
                    if d in base:
                        add(hits, line, "redeclared-property", f"`{d}` re-declares {name}.{d}")

    # global-text-role: a global role inside a Surface of a non-reading tone
    if "global-text-role" in rules:
        surfaces = [n for n in nodes if n.kind == "obj" and index.derives(n.type, rel, "Surface")]

        def tone_of(node):
            value = node.prop("tone")
            if value is None:
                return None
            ls = leaves(value)
            strs = [re.fullmatch(r'"(\w+)"', x.strip()) for x in ls]
            if ls and all(strs):
                return {m.group(1) for m in strs}
            return None

        for i, line in enumerate(slines, 1):
            inner = [n for n in surfaces if n.line <= i <= n.end_line]
            if not inner:
                continue
            inner.sort(key=lambda n: (n.line, -n.end_line))
            host = max(inner, key=lambda n: (n.line, -n.end_line))
            tones = tone_of(host)
            if not tones or tones & READING_TONES:
                continue
            if re.match(r"^\s*tone\s*:", line) and host.line == i:
                continue
            if re.match(r"^\s*tone\s*:", line):
                owner = [n for n in nodes if n.kind == "obj" and n.line <= i <= n.end_line and index.derives(n.type, rel, "StyledText")]
                if owner:
                    lit = re.findall(r'"(\w+)"', line)
                    if any(x in INK_LACKS or (x == "onAccent" and tones != {"accent"}) for x in lit):
                        add(hits, i, "global-text-role", line.strip())
                continue
            if GLOBAL_ROLES.search(line):
                add(hits, i, "global-text-role", line.strip())
    return hits


def ancestors(node):
    p = node.parent
    while p:
        yield p
        p = p.parent


def zoom_host(node):
    """Whether the block or an enclosing block declares `contentZoom` itself (anywhere among its properties)."""
    return any("contentZoom" in n.decls for n in [node, *ancestors(node)])


def waived_counts(rel, hits, raw_lines, exceptions):
    """(counts per rule, stale waiver lines): the hits not waived by a `// style-exempt:` line or an exception entry."""
    marked = {i for i, line in enumerate(raw_lines, 1) if EXEMPT.search(line)}
    hit_lines = {h[0] for h in hits}
    stale = sorted(marked - hit_lines)
    skip = set()
    for pattern, entry in exceptions.items():
        if fnmatch.fnmatch(rel, pattern):
            skip |= set(entry["rules"])
    counts = defaultdict(int)
    for line, rule, _, n in hits:
        if line in marked or rule in skip:
            continue
        counts[rule] += n
    return dict(counts), stale


def survey(files=None):
    """{rel: (counts, detail hits, stale)} for the scanned files; the index always covers the whole tree."""
    exceptions, errors = qml_modules.load_exceptions(EXCEPTIONS, set(RULES))
    every = all_files()
    index = Index(every)
    out = {}
    for f in every:
        rel = f.relative_to(ROOT).as_posix()
        if files is not None and rel not in files:
            continue
        raw_lines = index.trees[rel][4].split("\n")
        hits = scan(rel, index)
        marked = {i for i, line in enumerate(raw_lines, 1) if EXEMPT.search(line)}
        counts, stale = waived_counts(rel, hits, raw_lines, exceptions)
        skip = set().union(*(set(e["rules"]) for pattern, e in exceptions.items() if fnmatch.fnmatch(rel, pattern)))
        out[rel] = (counts, [h for h in hits if h[0] not in marked and h[1] not in skip], stale, hits)
    return out, exceptions, errors


# ---- the check ----

def check():
    result, exceptions, errors = survey()
    for rel, (counts, detail, stale, hits) in sorted(result.items()):
        for line, rule, text_, _n in sorted(detail):
            errors.append(f"{rel}:{line}: {rule} {text_}")
        for line in stale:
            errors.append(f"{rel}:{line}: a `// style-exempt:` line with no hit (stale waiver)")
    for pattern, entry in sorted(exceptions.items()):
        matched = [rel for rel in result if fnmatch.fnmatch(rel, pattern)]
        if not matched:
            errors.append(f"scripts/style-exceptions.json: {pattern} matches no file")
            continue
        for rule in entry["rules"]:
            if not any(any(h[1] == rule for h in result[rel][3]) for rel in matched):
                errors.append(f"scripts/style-exceptions.json: {pattern} lists {rule}, which no file under it hits")
    return errors


def rel_of(path):
    p = Path(path)
    p = p if p.is_absolute() else Path.cwd() / p
    try:
        return p.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return Path(path).as_posix()


def command_files(paths):
    wanted = {rel_of(p) for p in paths}
    result, _, _ = survey(wanted)
    found = 0
    for rel in sorted(result):
        for line, rule, text_, _n in sorted(result[rel][1]):
            print(f"{rel}:{line}: {rule} {text_}")
            found += 1
    return found


# The functions of Style.qml that pick a role by a name: a role they return is read
# when the function is read outside Style (a literal `tone: "success"` reaches
# `successText` through `toneColor`).
SWITCHES = ("toneColor", "textRole", "iconSize", "inkOf")
STYLE_FILES = ("Style", "StyleInk", "StyleTextRole")


def function_body(text, name):
    m = re.search(r"\bfunction " + name + r"\(", text)
    if not m:
        return ""
    start = text.index("{", m.end())
    depth = 0
    for i in range(start, len(text)):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        if depth == 0:
            return text[start:i]
    return text[start:]


def unused_roles():
    """The public members of Style.qml nothing outside the style files reads."""
    path = QML / "config" / "Style.qml"
    if not path.exists():
        return []
    style = path.read_text()
    members = set(re.findall(r"^\s*(?:readonly\s+)?property\s+[\w.<>]+\s+(\w+)\s*:", style, re.M))
    members |= set(re.findall(r"^\s*function\s+(\w+)\s*\(", style, re.M))
    members = sorted(m for m in members if not m.startswith("_"))
    sources = "\n".join(f.read_text(errors="replace") for f in sorted(QML.rglob("*.qml")) if f.stem not in STYLE_FILES)
    read = {m for m in members if re.search(r"\bStyle\." + m + r"\b", sources)}
    for fn in SWITCHES:
        if fn in read:
            read |= set(re.findall(r"\broot\.(\w+)", function_body(style, fn)))
    return [m for m in members if m not in read]


def command_roles():
    found = unused_roles()
    for m in found:
        print(f"Style.qml: unused role {m}")
    return len(found)


def main():
    args = sys.argv[1:]
    if not args:
        errors = check()
        errors += [f"Style.qml: unused role {m}" for m in unused_roles()]
        if errors:
            print("\n".join(errors))
            print(f"\n{len(errors)} style failure(s) (docs/dev/testing.md > The checks)")
            sys.exit(1)
        print("style ok")
    elif args[0] == "--files":
        sys.exit(1 if command_files(args[1:]) else 0)
    elif args[0] == "--roles":
        sys.exit(1 if command_roles() else 0)
    else:
        sys.exit(__doc__.strip())


if __name__ == "__main__":
    main()
