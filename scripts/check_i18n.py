#!/usr/bin/env python3
"""Check the translation dictionaries in config/i18n against the source.

Keys come from:
  - every string literal passed to I18n.tr("...") in the QML, and
  - the config schema's titles, descriptions, card titles, empty labels,
    disabled notes, string enum values, `x-categories` names and card titles
    and `x-libraryGroups` names (the settings UI and the editors' libraries
    translate those themselves, so they need no code).

  scripts/check_i18n.py                 missing / unused entries per language,
                                        and files not in the canonical format;
                                        fails on all but an empty entry
  scripts/check_i18n.py --fill          also add missing keys (empty) to each file
  scripts/check_i18n.py --prune         also remove unused keys
  scripts/check_i18n.py --format        also rewrite each file in the format
                                        (--fill and --prune write it too)
  scripts/check_i18n.py --untranslated  UI-looking string literals not wrapped in I18n.tr()

It also keeps config/i18n/template/language.json, the empty dictionary a
new language starts from: every key with an empty translation, sorted, and
_meta holding English's date formats. --fill, --prune and --format rewrite
it; a plain run fails when it's stale. It sits in a subfolder so neither
the shell's language list nor this script's per-language pass sees it.

An empty or missing entry falls back to English at runtime, so a partly
translated file is always safe to ship. An empty one is the normal state
(the pre-commit hook adds new keys empty), so it's reported, never a
failure; a key absent from a file, an unused one, a file not in the format
and a stale template mean the hook didn't run, and fail.

The canonical format is json.dumps(indent=2, ensure_ascii=False) plus a
newline: anything else rewrites every line in a diff. Files are written
atomically (temp file + rename), since the shell reads the active one live.
"""
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
I18N = ROOT / "config" / "i18n"
TEMPLATE = I18N / "template" / "language.json"
SCHEMA = ROOT / "config" / "json" / "config.schema.json"
I18N_QML = ROOT / "config" / "I18n.qml"
QML_DIRS = ["components", "shell", "services", "config"]
SKIP = []

# "..." with escapes, as the first argument of I18n.tr(
TR_CALL = re.compile(r'I18n\.tr\(\s*"((?:[^"\\]|\\.)*)"')
# Property assignments that are UI text, for --untranslated: the whole
# value expression, so literals in ternaries and concatenations are seen
UI_PROP = re.compile(r'\b(text|title|label|placeholderText|tooltipText|description|subtitle):\s*(.+)$')
# Object-literal UI fields ("label": "Text", name: "Text" in option lists)
UI_FIELD = re.compile(r'"?(label|title|text|description|tooltip)"?\s*:\s*"((?:[^"\\]|\\.)*)"')
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"|`([^`]*)`')
# tr() whose first argument isn't a string literal
DYNAMIC_TR = re.compile(r'I18n\.tr\(\s*(?!["\)])')
# tr() calls (literal first argument), stripped before looking for literals
TR_LITERAL = re.compile(r'I18n\.tr\(\s*"(?:[^"\\]|\\.)*"')
# A literal compared against, or used as a key, isn't shown
COMPARED = re.compile(r'(===|!==|==|!=|case)\s*$')


def qml_files():
    for d in QML_DIRS:
        for f in (ROOT / d).rglob("*.qml"):
            rel = f.relative_to(ROOT).as_posix()
            if not any(rel.startswith(s) for s in SKIP):
                yield f, rel


def unescape(s):
    return json.loads(f'"{s}"')


def enum_label(value):
    """An enum value as the form shows it without x-enumLabels (Utils.enumLabel)."""
    if not re.fullmatch(r"[a-z][a-zA-Z0-9]*", value):
        return value
    spaced = re.sub(r"([a-z])([A-Z])", r"\1 \2", re.sub(r"([a-zA-Z]{2,})(\d)", r"\1 \2", value)).split(" ")
    rest = [w.lower() if re.match(r"[A-Z][a-z]", w) else w for w in spaced[1:]]
    return " ".join([spaced[0][0].upper() + spaced[0][1:]] + rest)


def schema_strings(node, out):
    if isinstance(node, dict):
        for key in ("title", "description", "x-group", "x-hookupNote", "x-emptyLabel", "x-disabledNote"):
            if isinstance(node.get(key), str):
                out.add(node[key])
        if isinstance(node.get("x-card"), dict) and isinstance(node["x-card"].get("title"), str):
            out.add(node["x-card"]["title"])
        if isinstance(node.get("x-categories"), list):
            out.update(c["name"] for c in node["x-categories"] if isinstance(c, dict) and isinstance(c.get("name"), str))
            out.update(c["cardTitle"] for c in node["x-categories"] if isinstance(c, dict) and isinstance(c.get("cardTitle"), str))
        if isinstance(node.get("x-libraryGroups"), list):
            out.update(g for g in node["x-libraryGroups"] if isinstance(g, str))
        if isinstance(node.get("x-hookup"), list):
            out.update(t["where"] for t in node["x-hookup"] if isinstance(t, dict) and isinstance(t.get("where"), str))
        if isinstance(node.get("x-enumLabels"), dict):
            out.update(v for v in node["x-enumLabels"].values() if isinstance(v, str))
        if node.get("type") == "string" and isinstance(node.get("enum"), list):
            labels = node.get("x-enumLabels") if isinstance(node.get("x-enumLabels"), dict) else {}
            out.update(enum_label(v) for v in node["enum"] if isinstance(v, str) and v not in labels)
        for value in node.values():
            schema_strings(value, out)
    elif isinstance(node, list):
        for value in node:
            schema_strings(value, out)


def tr_first_args(line):
    """The first argument of each I18n.tr( call on a line, as source text."""
    for m in re.finditer(r"I18n\.tr\(", line):
        depth, i, start = 0, m.end(), m.end()
        while i < len(line):
            c = line[i]
            if c == '"':
                i = line.index('"', i + 1) if '"' in line[i + 1:] else len(line)
                while i < len(line) and line[i - 1] == "\\":
                    i = line.index('"', i + 1)
            elif c in "([{":
                depth += 1
            elif c in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif c == "," and depth == 0:
                break
            i += 1
        yield line[start:i]


def branch_literals(arg):
    """String literals in a tr() argument, minus those in ternary conditions."""
    literals = []

    def mask(m):
        literals.append(m.group(1))
        return f"\x00{len(literals) - 1}\x00"

    masked = re.sub(r'"((?:[^"\\]|\\.)*)"', mask, arg)
    kept = re.sub(r"[^?:]*\?", "", masked)
    return [literals[int(i)] for i in re.findall(r"\x00(\d+)\x00", kept)]


def collect_keys():
    keys = {}
    for f, rel in qml_files():
        for line_no, line in enumerate(f.read_text().splitlines(), 1):
            for m in TR_CALL.finditer(line):
                keys.setdefault(unescape(m.group(1)), f"{rel}:{line_no}")
            # Both branches of I18n.tr(cond ? "A" : "B"), not the condition
            for arg in tr_first_args(line):
                for literal in branch_literals(arg):
                    if literal:  # a `?? ""` fallback isn't text
                        keys.setdefault(unescape(literal), f"{rel}:{line_no}")
    schema = set()
    root = json.loads(SCHEMA.read_text())
    schema_strings({"x-categories": root.get("x-categories", []), "x-libraryGroups": root.get("x-libraryGroups", [])}, schema)
    schema_strings(root["properties"], schema)
    schema_strings(root["definitions"], schema)
    for s in schema:
        keys.setdefault(s, "schema")
    return keys


def is_words(literal):
    """Words, not glyphs, format strings, ids, paths or colors."""
    literal = re.sub(r"\$\{[^}]*\}", "", literal)
    if literal.startswith(("#", "qrc:", "file:", "/", "image://")) or "." in literal.split(" ")[0] and " " not in literal:
        return False
    if re.fullmatch(r"[A-Z0-9]{2,4}|[a-z]+/[a-z]+", literal.strip()):
        return False  # acronyms (CPU) and units (km/h)
    return bool(re.search(r"[A-Za-z]{2,}", literal))


def shown_literals(expr):
    """String literals in a value expression that would reach the screen."""
    for arg in tr_first_args(expr):
        expr = expr.replace(arg, re.sub(r'"(?:[^"\\]|\\.)*"', "_", arg), 1)
    expr = TR_LITERAL.sub("I18n.tr(_", expr)
    # Date formats: I18n.formatDate(date, "ddd"), I18n.dateFormat("longDate")
    expr = re.sub(r'(I18n\.(?:formatDate|dateFormat)\([^;]*)', lambda m: re.sub(r'"(?:[^"\\]|\\.)*"', "_", m.group(1)), expr)
    for m in STRING.finditer(expr):
        literal = m.group(1) if m.group(1) is not None else m.group(2)
        before, after = expr[:m.start()], expr[m.end():]
        if COMPARED.search(before) or re.match(r"\s*(===|!==|==|!=|\]|:)", after) or before.rstrip().endswith("["):
            continue
        # Arguments to a call (formatDate formats, startsWith, ...), except
        # a concatenation's first operand
        if re.search(r"[\w\]\)]\.?\w*\(\s*$", before) and not before.rstrip().endswith("I18n.tr("):
            continue
        if m.group(2) is not None:
            # a template: its text parts, around the ${...} expressions
            literal = re.sub(r"\$\{[^}]*\}", " ", literal)
        if is_words(literal):
            yield literal


def untranslated():
    for f, rel in qml_files():
        text = f.read_text()
        lines = text.splitlines()
        declared = bool(re.search(r'//.*(I18n\.tr\("|i18n: keys from)', text))
        for line_no, line in enumerate(lines, 1):
            code = line.split("//")[0] if "://" not in line else line
            if not code.strip() or "console." in code:
                continue
            m = UI_PROP.search(code)
            if m:
                for literal in shown_literals(m.group(2)):
                    yield f"{rel}:{line_no}: {m.group(1)}: {literal!r}"
            for field in UI_FIELD.finditer(code):
                if not (m and field.start() >= m.start(2)) and is_words(field.group(2)):
                    yield f"{rel}:{line_no}: {field.group(1)}: {field.group(2)!r}"
            for arg in tr_first_args(code):
                rest = re.sub(r'"(?:[^"\\]|\\.)*"', "", arg)
                # A condition choosing between literals is fine
                rest = re.sub(r"[^?:]*\?", "", rest)
                if not re.search(r"[A-Za-z_]", re.sub(r"[?:()\s]", "", rest)):
                    continue
                # Keys chosen at runtime: declared in a comment in the file
                # (// I18n.tr("key") ...), or the file says its keys come
                # from callers/the schema (// i18n: keys from callers)
                if not declared:
                    yield f"{rel}:{line_no}: dynamic tr() without declared keys: {code.strip()[:90]}"


def english_formats():
    """English's named date formats: I18n.qml's _formats object."""
    block = re.search(r"_formats: \(\{(.*?)\}\)", I18N_QML.read_text(), re.S).group(1)
    return dict(re.findall(r'"(\w+)":\s*"((?:[^"\\]|\\.)*)"', block))


def template(keys):
    return {"_meta": {"name": "", "locale": "", "formats": english_formats()},
            "strings": {k: "" for k in sorted(keys)}}


def canonical(data):
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def write_atomic(path, text):
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def main():
    if "--untranslated" in sys.argv:
        found = list(untranslated())
        print("\n".join(found) or "no untranslated UI literals found")
        return 1 if found else 0

    keys = collect_keys()
    status = 0
    for path in sorted(I18N.glob("*.json")):
        text = path.read_text(encoding="utf-8")
        data = json.loads(text)
        strings = data.setdefault("strings", {})
        missing = [k for k in keys if not strings.get(k)]
        unused = [k for k in strings if k not in keys]
        absent = [k for k in keys if k not in strings]
        empty = [k for k in missing if k in strings]
        print(f"{path.name}: {len(keys) - len(missing)}/{len(keys)} translated, {len(missing)} missing, {len(unused)} unused")
        for k in empty[:40]:
            print(f"  missing  {keys[k]}: {k!r}")
        if len(empty) > 40:
            print(f"  ... and {len(empty) - 40} more")
        for k in absent:
            print(f"  absent   {keys[k]}: {k!r}")
        for k in unused:
            print(f"  unused   {k!r}")
        if "--fill" in sys.argv:
            for k in missing:
                strings.setdefault(k, "")
        if "--prune" in sys.argv:
            for k in unused:
                del strings[k]
        if {"--fill", "--prune", "--format"} & set(sys.argv):
            if canonical(data) != text:
                write_atomic(path, canonical(data))
        elif text != canonical(json.loads(text)):
            print("  format   not in the canonical format (2-space indent): run with --format")
            status |= 1
        status |= 1 if absent or unused else 0

    expected = canonical(template(keys))
    current = TEMPLATE.read_text(encoding="utf-8") if TEMPLATE.exists() else None
    if current != expected:
        if {"--fill", "--prune", "--format"} & set(sys.argv):
            TEMPLATE.parent.mkdir(exist_ok=True)
            write_atomic(TEMPLATE, expected)
            print(f"{TEMPLATE.relative_to(ROOT)}: rewritten")
        else:
            print(f"{TEMPLATE.relative_to(ROOT)}: stale: run with --fill")
            status |= 1
    return status


if __name__ == "__main__":
    sys.exit(main())
