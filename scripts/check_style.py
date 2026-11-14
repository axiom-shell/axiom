#!/usr/bin/env python3
"""The style lint: keep colours, text sizes, weights and text rendering on the Style roles.

A ratchet until PR 11 of the style stack (docs/dev/core/style.md; the rules'
reasons and the lifecycle are in docs/dev/testing.md > The checks): every file
holds at most the hits scripts/style-baseline.json records, and a file not in it
holds none. Rules:

  R1   `Theme.` reads (but the pickers' passthroughs), `Theme.resolveColor(` included
  R2   Qt.alpha/rgba/hsla/hsva/lighter/darker/tint, a quoted hex or CSS colour
  R3   a fractional opacity (a property named opacity or ...Opacity, an animation on it)
  R4   fontSizeBy(, fontSizeLarge, Appearance.fontSize as a text/icon size, a numeric
       textSize, a fitted size without its Style.type floor
  R5   font.bold; font.weight set to anything but a role's weight
  R6   a colour function called in UI (Tone., StyleTokens., Qt.color(, Utils.contrast(, ...);
       in a service or reader: a stored resolved colour
  R7   a colour property set to anything but a Style role, an ink, "transparent" or a
       property of the file itself
  R8   a ClippingRectangle with no color (its default is white)
  R9   a Qt Quick Controls visual that leaves a part to the Qt palette
  R10  a Canvas painting from Style with no Style.revision in its repaint key
  R11  a block re-declaring a property its type or a base of it declares (every .qml)
  R12  a global text role (or a tone its ink lacks) inside a Surface of a non-reading tone
  R13  font.bold on a StyledText or a type derived from it (every .qml)
  R14  wrapMode/elide/maximumLineCount on a StyledText: overflow:/maxLines:
  R15  a dead elide: an eliding StyledText in a Row(Layout) with no bound on it
  R16  a raw Text-family block with no TextRender renderType (every .qml)
  R17  layer.enabled / layer.effect over content
  R18  a scale over content with no `contentZoom` host

Not baselined (any hit fails): R11, R13, R15, R16. A line carrying
`// style-exempt: <reason>` counts 0; scripts/style-exceptions.json waives a file
(or glob) per rule.

  scripts/check_style.py                  the ratchet; exit 1 on a failure
  scripts/check_style.py --files F...     print the hits of these files (always exit 0)
  scripts/check_style.py --write-baseline once, in the PR that adds the ratchet
  scripts/check_style.py --shrink-baseline  lower every entry to the current counts
  scripts/check_style.py --raise F...     set these files' entries to their current counts
  scripts/check_style.py --roles          Style members nothing reads (report only)
"""
import fnmatch
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import qml_modules  # noqa: E402

ROOT = qml_modules.ROOT
QML = qml_modules.QML_ROOT
BASELINE = ROOT / "scripts" / "style-baseline.json"
EXCEPTIONS = ROOT / "scripts" / "style-exceptions.json"

RULES = [f"R{n}" for n in range(1, 19)]
BASELINED = {r for r in RULES if r not in ("R11", "R13", "R15", "R16")}
EVERYWHERE = {"R11", "R13", "R16"}
STYLE_LAYER_PIECES = {"Surface", "StateLayer", "FocusRing", "Skeleton", "StyledScrollIndicator", "BackdropScrim"}
STYLE_LAYER_CONFIG = {"Style", "StyleInk", "StyleTextRole", "BarColors", "Theme", "Appearance", "BarsConfig", "BarStyle"}

# The CSS colour names R2 refuses quoted ("transparent" stays allowed)
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

R1 = re.compile(r"(?<![\w.])Theme\.(?!(?:baseColorNames|roles|name|stringToColorMap)\b)")
R2 = re.compile(r"Qt\.(?:alpha|rgba|hsla|hsva|lighter|darker|tint)\(|[\"']#[0-9a-fA-F]{3,8}[\"']|[\"'](?:" + "|".join(CSS_NAMES) + r")[\"']")
R4_CALLS = re.compile(r"fontSizeBy\(|fontSizeLarge")
R4_SIZE_NAMES = ("textSize", "font.pixelSize", "iconSize")
R6_CALLS = re.compile(r"(?<![\w.])(?:Tone|StyleTokens|BarWidgetStyle)\.|Style\.shadow(?:Base)?Color\(|BarColors\.(?:widgetColors|pulseLadder)\(|"
                      r"Qt\.color\(|Utils\.(?:contrast|luminance|getContrastColor|isColorDark|fadeable)\(")
R6_STORED = re.compile(r"String\(.*?(?:(?<![\w.])(?:Theme|Style)\.|\w+Config\.\w*(?:[Cc]olor|[Bb]order))")
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


# ---- values: the operand algorithm of R5 and R7 ----

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
    """The rules that apply to a file (every file gets R11, R13 and R16)."""
    p = rel
    rules = set(EVERYWHERE)
    name = Path(p).stem
    if p.startswith(("qml/services/", "qml/config/")):
        if name in STYLE_LAYER_CONFIG or p == "qml/services/core/ThemeManager.qml":
            return rules
        return rules | {"R1", "R2", "R6"}
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
    rules |= {f"R{n}" for n in range(4, 11)} | {"R12", "R14", "R15", "R17", "R18"}
    if p.startswith(("qml/components/bar/look/", "qml/components/bar/widgets/base/")):
        return rules
    return rules | {"R1", "R2", "R3", "R6"}


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
        if "R1" in rules:
            for _ in R1.finditer(line):
                add(hits, i, "R1", line.strip())
        if "R2" in rules:
            for _ in R2.finditer(line):
                add(hits, i, "R2", line.strip())
        if "R4" in rules:
            fitted = re.search(r"//\s*fitted:", raw[i - 1]) if i - 1 < len(raw) else None
            if fitted:
                m = re.match(r"^\s*(?:textSize|font\.pixelSize|iconSize)\s*:\s*(.*)$", slines[i - 1])
                if m and not re.search(r"Style\.(?:type|icon)\w+", m.group(1)):
                    add(hits, i, "R4", "a fitted size without its Style.type floor")
            skip_calls = bool(fitted and m)
            if not skip_calls:
                for _ in R4_CALLS.finditer(line):
                    add(hits, i, "R4", line.strip())
        if "R5" in rules:
            for _ in re.finditer(r"(?<![\w.])font\.bold\b", line):
                add(hits, i, "R5", line.strip())
        if "R6" in rules:
            if not rel.startswith(("qml/services/", "qml/config/")):
                for _ in R6_CALLS.finditer(line):
                    add(hits, i, "R6", line.strip())
            if rel.startswith(("qml/services/", "qml/config/")) and R6_STORED.search(line):
                add(hits, i, "R6", line.strip())
        if "R17" in rules:
            m = re.match(r"^\s*layer\.enabled\s*:\s*(.*)$", line)
            if m and m.group(1).strip() != "false":
                add(hits, i, "R17", line.strip())
            if re.match(r"^\s*layer\.effect\s*:", line):
                add(hits, i, "R17", line.strip())
        if "R16" in rules:
            m = re.match(r"^\s*renderType\s*:\s*(.*)$", line)
            if m and not m.group(1).strip().startswith("TextRender."):
                add(hits, i, "R16", line.strip())

    # a text-size line's own value: Appearance.fontSize as a size, a numeric textSize (R4)
    if "R4" in rules:
        for node in nodes:
            for name, line, value in node.props:
                if name in R4_SIZE_NAMES and (re.search(r"Appearance\.fontSize\b(?!By|Large)", value) or re.fullmatch(r"\d+(?:\.\d+)?", value.strip())):
                    if "fitted:" not in raw[line - 1]:
                        add(hits, line, "R4", f"{name}: {value}")
            if node.kind == "obj" and node.has("fontSizeMode") and (node.prop("fontSizeMode") or "").strip() != "Text.FixedSize" \
                    and not re.search(r"Style\.type\w+", node.prop("minimumPixelSize") or ""):
                add(hits, node.line, "R4", "a fontSizeMode block without minimumPixelSize: Style.type*")

    for node in nodes:
        if node.kind == "group":
            if "R13" in rules and node.type == "font" and node.has("bold") and node.parent and node.parent.kind == "obj" \
                    and index.derives(node.parent.type, rel, "StyledText"):
                add(hits, node.line, "R13", "font { bold }")
            continue
        styled = index.derives(node.type, rel, "StyledText")
        for name, line, value in node.props:
            if "R3" in rules and re.search(r"(?:^|\.)\w*[oO]pacity$", name):
                if any(float(x) not in (0.0, 1.0) for x in re.findall(r"(?<![\w.])(\d*\.\d+)", value)):
                    add(hits, line, "R3", f"{name}: {value}")
            if "R5" in rules and name == "font.weight":
                if not all(weight_leaf_ok(x) for x in leaves(value)):
                    add(hits, line, "R5", f"font.weight: {value}")
            if "R7" in rules and name in COLOUR_PROPS:
                if not all(colour_leaf_ok(x, ids) for x in leaves(value)):
                    add(hits, line, "R7", f"{name}: {value}")
            if "R13" in rules and name == "font.bold" and styled:
                add(hits, line, "R13", "font.bold on a StyledText")
            if "R14" in rules and name in ("wrapMode", "elide", "maximumLineCount") and styled:
                add(hits, line, "R14", f"{name}: {value}")
            if "R18" in rules and name == "scale" and not zoom_host(node):
                try:
                    one = float(value) == 1.0
                except ValueError:
                    one = False
                if not one:
                    add(hits, line, "R18", f"scale: {value}")
        if "R3" in rules and node.type and node.type.endswith("Animation"):
            on_opacity = (node.on == "opacity") or (node.prop("property") or "").strip('"\'') == "opacity" \
                or any(a.on == "opacity" for a in ancestors(node))
            if on_opacity:
                for name, line, value in node.props:
                    if name in ("from", "to") and re.fullmatch(r"\d*\.\d+", value.strip()) and float(value) not in (0.0, 1.0):
                        add(hits, line, "R3", f"{name}: {value}")
        if "R18" in rules and not zoom_host(node):
            if node.type == "Scale" and node.header.strip().startswith("transform"):
                add(hits, node.line, "R18", "transform: Scale")
            prop_v = (node.prop("property") or "").strip().strip("\"'")
            props_v = (node.prop("properties") or "")
            if prop_v == "scale" or re.search(r"\bscale\b", props_v):
                add(hits, node.line, "R18", "an animation on scale")
        if "R8" in rules and node.type == "ClippingRectangle" and not node.has("color"):
            add(hits, node.line, "R8", "ClippingRectangle with no color")
        if "R9" in rules and node.type in NEEDS:
            need = NEEDS[node.type]
            if node.type == "ScrollView":
                ok = any(x in s[node.open_at:node.close_at] for x in need)
            else:
                ok = any(node.has(x) for x in need)
            if not ok:
                add(hits, node.line, "R9", f"{node.type} leaves a part to the Qt palette")
        if "R10" in rules and node.type == "Canvas" and "Style.revision" not in text:
            for c in node.children:
                if c.kind == "js" and c.header.strip().endswith("onPaint:") and re.search(r"\bStyle\.\w", s[c.open_at:c.close_at]):
                    add(hits, node.line, "R10", "a Canvas painting from Style with no Style.revision")
        if "R16" in rules and node.type in TEXT_BLOCKS and not any(n == "renderType" and v.strip().startswith("TextRender.") for n, _, v in node.props):
            add(hits, node.line, "R16", f"{node.type} without a TextRender renderType")
        if "R15" in rules and styled and node.parent and node.parent.kind == "obj" and node.parent.type in ("RowLayout", "Row"):
            overflow = (node.prop("overflow") or "").strip()
            elide = (node.prop("elide") or "").strip()
            eliding = overflow == '"line"' or (elide and elide != "Text.ElideNone")
            bounded = (node.prop("Layout.fillWidth") or "").strip() == "true" or any(node.has(x) for x in ("Layout.maximumWidth", "Layout.preferredWidth", "width"))
            if eliding and not bounded:
                add(hits, node.line, "R15", "an eliding text with no bound in a row")

    # R11: a block re-declaring what its type or a base declares
    if "R11" in rules:
        for node in nodes:
            if node.kind != "obj" or not node.decls:
                continue
            for name, key in index.chain(node.type, rel):
                if key is None:
                    continue
                base = index.decls_of(key)
                for d, line in node.decls.items():
                    if d in base:
                        add(hits, line, "R11", f"`{d}` re-declares {name}.{d}")

    # R12: a global role inside a Surface of a non-reading tone
    if "R12" in rules:
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
                        add(hits, i, "R12", line.strip())
                continue
            if GLOBAL_ROLES.search(line):
                add(hits, i, "R12", line.strip())
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
        out[rel] = (counts, [h for h in hits if h[0] not in marked], stale, hits)
    return out, exceptions, errors


# ---- the ratchet ----

def load_baseline():
    if not BASELINE.exists():
        return None, ["scripts/style-baseline.json is missing (python3 scripts/check_style.py --write-baseline)"]
    try:
        data = json.loads(BASELINE.read_text())
    except ValueError as e:
        return None, [f"scripts/style-baseline.json is not JSON: {e}"]
    errors = []
    if not isinstance(data, dict):
        return None, ["scripts/style-baseline.json is not an object of files"]
    for path, rules in data.items():
        if not isinstance(rules, dict) or not all(r in BASELINED and isinstance(n, int) and n > 0 for r, n in rules.items()):
            errors.append(f"scripts/style-baseline.json: {path}: not {{rule: count > 0}} for a baselined rule")
    return data, errors


def write_baseline(data):
    BASELINE.write_text(json.dumps(data, sort_keys=True, indent=1) + "\n")


def baseline_counts(result):
    return {rel: {r: n for r, n in counts.items() if r in BASELINED and n} for rel, (counts, *_rest) in result.items()
            if any(r in BASELINED and n for r, n in counts.items())}


def check():
    result, exceptions, errors = survey()
    base, shape = load_baseline()
    errors += shape
    base = base or {}
    for rel, (counts, detail, stale, hits) in sorted(result.items()):
        for rule in sorted(counts):
            n = counts[rule]
            if rule in BASELINED:
                allowed = base.get(rel, {}).get(rule, 0)
                if n > allowed:
                    first = next((h for h in detail if h[1] == rule), None)
                    where = f"{rel}:{first[0]}" if first else rel
                    errors.append(f"{where}: {rule} {n} hits, the baseline allows {allowed}" + (f" ({first[2]})" if first else ""))
            else:
                for line, r, text_, _n in detail:
                    if r == rule:
                        errors.append(f"{rel}:{line}: {rule} {text_}")
        for line in stale:
            errors.append(f"{rel}:{line}: a `// style-exempt:` line with no hit (stale waiver)")
    for rel in sorted(base):
        if rel not in result:
            errors.append(f"{rel}: in the baseline but no longer scanned (python3 scripts/check_style.py --shrink-baseline)")
    for pattern, entry in sorted(exceptions.items()):
        matched = [rel for rel in result if fnmatch.fnmatch(rel, pattern)]
        if not matched:
            errors.append(f"scripts/style-exceptions.json: {pattern} matches no file")
            continue
        for rule in entry["rules"]:
            if not any(any(h[1] == rule for h in result[rel][3]) for rel in matched):
                errors.append(f"scripts/style-exceptions.json: {pattern} lists {rule}, which no file under it hits")
    return errors


def command_write():
    if BASELINE.exists():
        sys.exit("scripts/style-baseline.json exists; --write-baseline is for the first one")
    result, _, errors = survey()
    counts = baseline_counts(result)
    write_baseline(counts)
    print(f"wrote scripts/style-baseline.json: {len(counts)} files")


def command_shrink():
    result, _, _ = survey()
    base, _ = load_baseline()
    base = base or {}
    now = baseline_counts(result)
    out = {}
    for rel, rules in base.items():
        if rel not in now:
            print(f"dropped {rel}")
            continue
        kept = {r: min(n, now[rel].get(r, 0)) for r, n in rules.items() if now[rel].get(r, 0)}
        if kept != rules:
            print(f"shrank {rel}: " + ", ".join(f"{r} {rules[r]} → {kept.get(r, 0)}" for r in rules if kept.get(r, 0) != rules[r]))
        if kept:
            out[rel] = kept
    write_baseline(out)


def rel_of(path):
    p = Path(path)
    p = p if p.is_absolute() else Path.cwd() / p
    try:
        return p.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return Path(path).as_posix()


def command_raise(paths):
    if not paths:
        sys.exit("--raise needs at least one path")
    result, _, _ = survey()
    base, _ = load_baseline()
    base = base or {}
    now = baseline_counts(result)
    for path in paths:
        rel = rel_of(path)
        if rel not in result:
            sys.exit(f"{path}: not a scanned file")
        if rel not in now:
            sys.exit(f"{path}: no baselined hit to raise to")
        before = base.get(rel, {})
        print(f"raised {rel}: " + ", ".join(f"{r} {before.get(r, 0)} → {n}" for r, n in sorted(now[rel].items())))
        base[rel] = now[rel]
    write_baseline(base)


def command_files(paths):
    wanted = {rel_of(p) for p in paths}
    result, _, _ = survey(wanted)
    for rel in sorted(result):
        for line, rule, text_, _n in sorted(result[rel][1]):
            print(f"{rel}:{line}: {rule} {text_}")


def command_roles():
    style = (QML / "config" / "Style.qml").read_text()
    members = sorted(set(re.findall(r"readonly property \w+ (\w+):", style)) - {"revision"})
    sources = "\n".join(f.read_text(errors="replace") for f in all_files()
                        if f.stem not in ("Style", "StyleInk", "StyleTextRole"))
    for m in members:
        if not re.search(r"Style\." + m + r"\b", sources):
            print(f"unused: Style.{m}")


def main():
    args = sys.argv[1:]
    if not args:
        errors = check()
        if errors:
            print("\n".join(errors))
            print(f"\n{len(errors)} style failure(s); the ratchet only shrinks (docs/dev/testing.md > The checks)")
            sys.exit(1)
        print("style ok")
    elif args[0] == "--write-baseline":
        command_write()
    elif args[0] == "--shrink-baseline":
        command_shrink()
    elif args[0] == "--raise":
        command_raise(args[1:])
    elif args[0] == "--files":
        command_files(args[1:])
    elif args[0] == "--roles":
        command_roles()
    else:
        sys.exit(__doc__.strip())


if __name__ == "__main__":
    main()
