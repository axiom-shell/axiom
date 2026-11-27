#!/usr/bin/env python3
"""The naming check: the identifiers declared under qml/ and the names scripts/names.json retires. Rules: `RULES`
below, one statement each; a failing rule's statement prints under the failures.

A hit is `<file>: <rule> <symbol>`, the symbol `<member>:<token>` (the root member enclosing it, else the
file's name) with a repeat numbered `#2`... A hit is waived by an entry in scripts/names-exceptions.json
(a file glob, or a name: the hit's token, or `Owner.member`; rules and reason; an entry that waives nothing fails).

  scripts/check_names.py    every hit; exit 1 on any
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_docs  # noqa: E402
import manifests  # noqa: E402
import qml_modules  # noqa: E402

ROOT = qml_modules.ROOT
EXCEPTIONS = ROOT / "scripts" / "names-exceptions.json"

RULES = {
    "bool-is-prefix": "a bool is the bare state word (`dirty`, `visible`); `is<Noun>` only for a kind test",
    "side-order": "a side's attribute puts the side first (`startJoined`, not `joinedStart`); a coordinate puts it last (`boxStart`)",
    "getter-pairs": "one suffix per noun: Of reads an attribute, For answers a question, On names a screen, At a position",
    "signal-shape": "events are past tense (`closed`), requests are `<verb>Requested`; a `<x>Changed` signal belongs to a property `<x>`",
    "handler-shaped-property": "a property never starts `on[A-Z]`: it reads as a handler",
    "callback-param": "`done` is called once with the answer, `handler` on every event; never `callback`, `cb`, `then` or `fn`",
    "unit-suffix": "ms, px and fractions are unsuffixed (`delay`, `size`); readers convert once, outside qml/config/ nothing divides by 100",
    "collection-suffix": "lists and maps are plural nouns (`items`), never `List`, `Map` or `Set`",
    "short-params": "public parameters are full words; only `i j k n x y` and two-letter words (`id`, `to`) are short",
    "acronym-case": "acronyms are word-cased (`Url`, `Ipc`); the listed exceptions are in scripts/names-exceptions.json",
    "spelling": "American spelling in identifiers (`center`, `color`, `canceled`, `behavior`, `gray`)",
    "retired": "a retired name (scripts/names.json > retired): use its `new`",
}

# The kinds `is<Noun>` may test: a type of thing, not a state
KIND_TESTS = {"Break", "Color", "Custom", "Day", "Desktop", "DesktopMonitor", "Entry", "Hex", "Input", "Label", "Local",
              "Master", "Mic", "Run", "Screen", "Slider", "Streams", "Symbol", "Task", "User", "Value"}
REQUEST_VERBS = "show|hide|toggle|open|close|save|reset|remove|select"
CALLBACK_PARAMS = {"callback", "cb", "then", "fn"}
SHORT_PARAMS_OK = set("ijknxy") | {"id", "on", "to", "at", "by", "up", "ok"}

ID = re.compile(r"\bid\s*:\s*(\w+)")
GETTER = re.compile(r"([a-z]\w*?)(Of|For|On|At)")
SIDE_KEY = re.compile(r'"(\w+(?:Start|End))"\s*:\s*(?:true|false)\b')


def _params(raw):
    """The parameter names of a parameter list's text (parens included): `name`, `name: type`, `name = value`
    or `type name`."""
    return [m.group(1) for part in raw.strip("()").split(",") if (m := re.search(r"(\w+)\s*(?:[:=].*)?$", part))]


class Source:
    """One QML file: its text, the same without comments (`stripped`), and with string literals emptied too
    (`code`, same lines); its declared properties, functions, signals and ids."""

    def __init__(self, rel, text):
        self.rel, self.stem, self.text = rel, Path(rel).stem, text
        self.stripped = qml_modules.blank_comments(text)
        self.code = qml_modules.blank_strings(self.stripped)
        self.starts = [0] + [m.end() for m in re.finditer("\n", self.stripped)]
        self.properties, self.functions, self.signals = [], [], []
        for m in qml_modules.DECLARATION.finditer(self.code):
            at = self.at(m.start())
            if m.group(3):
                self.properties.append((m.group(2), m.group(3), at))
            elif m.group(5):
                self.signals.append((m.group(5), _params(m.group(6) or ""), at))
            else:
                self.functions.append((m.group(7), _params(m.group(8)), at))
        self.ids = [(m.group(1), self.at(m.start())) for m in ID.finditer(self.code)]

    def at(self, offset):
        """`offset` in `code` as the offset of the same place in `stripped`."""
        line = self.code.count("\n", 0, offset)
        return self.starts[line] + offset - (self.code.rfind("\n", 0, offset) + 1)

    def declared(self):
        """[(name, offset)] of every declared name: properties, functions, signals, their parameters, ids;
        the file's stem last with no offset."""
        names = [(name, at) for _, name, at in self.properties]
        for name, params, at in self.functions + self.signals:
            names += [(name, at)] + [(p, at) for p in params]
        return names + self.ids + [(self.stem, None)]


def _bool_is_prefix(src, facts):
    return [(at, name) for typ, name, at in src.properties
            if typ == "bool" and re.fullmatch(r"is[A-Z]\w*", name) and name[2:] not in KIND_TESTS]


def _side_order(src, facts):
    return ([(at, name) for typ, name, at in src.properties
             if typ == "bool" and re.fullmatch(r"\w+(?:Start|End)", name)
             and not re.search(r"(?:^_*(?:at|from)|(?:At|From))(?:Start|End)$|^_*can[A-Z]", name)]
            + [(m.start(), m.group(1)) for m in SIDE_KEY.finditer(src.stripped)])


def _getter_pairs(src, facts):
    return [(at, name) for name, _, at in src.functions
            if (m := GETTER.fullmatch(name.lstrip("_"))) and len(facts["suffixes"][m.group(1)]) > 1]


def _signal_shape(src, facts):
    found = []
    for name, _, at in src.signals:
        noun = name.removesuffix("Changed")
        if name.endswith("Changed") and noun and not any(p == noun for _, p, _ in src.properties):
            found.append((at, name))
        elif re.fullmatch(rf"(?:{REQUEST_VERBS})(?:[A-Z]\w*)?", name) and not re.search(r"[a-z]ed$", name):
            found.append((at, name))
    return found


def _handler_shaped_property(src, facts):
    return [(at, name) for _, name, at in src.properties if re.fullmatch(r"on[A-Z]\w*", name)]


def _callback_param(src, facts):
    return [(at, p) for _, params, at in src.functions for p in params if p in CALLBACK_PARAMS]


def _unit_suffix(src, facts):
    found = [(at, name) for name, at in src.declared() if at is not None and re.search(r"[a-z](?:Ms|Px)$", name)]
    if not src.rel.startswith("qml/config/"):
        ends = {gen_docs._skip_balanced(src.code, m.end() - 1)
                for m in re.finditer(r"\bMath\.(?:round|floor|ceil)\(", src.code)}
        found += [(src.at(m.start()), "/ 100") for m in re.finditer(r"/\s*100\b", src.code)
                  if len(src.code[:m.start()].rstrip()) not in ends]
    return found


def _collection_suffix(src, facts):
    return [(at, name) for typ, name, at in src.properties
            if re.fullmatch(r"\w+Set", name) or re.fullmatch(r"\w+(?:List|Map)", name) and (typ == "var" or typ.startswith("list<"))]


def _short_params(src, facts):
    return [(at, p) for name, params, at in src.functions if not name.startswith("_") for p in params
            if re.fullmatch(r"[A-Za-z]{1,2}", p) and p not in SHORT_PARAMS_OK | CALLBACK_PARAMS]


def _acronym_case(src, facts):
    found = []
    for name, at in src.declared():
        word = name.lstrip("_")
        if "_" in word:
            continue
        for run in re.finditer(r"[A-Z]{3,}", word):
            token = run.group()
            if re.match(r"[a-z]{2}", word[run.end():]):
                token = token[:-1]
            if len(token) >= 3:
                found.append((at, token))
    return found


def _spelling(src, facts):
    return [(at, name) for name, at in src.declared() if re.search(
        r"(?:^_*|(?<=_)|(?<=[a-z0-9])(?=[A-Z]))(?:[Cc]entre|[Cc]olour|[Cc]ancelled|[Bb]ehaviour|[Gg]rey)", name)]


def _retired(src, facts):
    """A retired plain name declared or read as a member (`.name`, a lowercase key: a type key's site is its file
    stem); a dotted one as `Owner.member`, or the `function member` of `Owner.qml`."""
    plain = [k for k in facts["retired"] if "." not in k]
    found = [(at, name) for name, at in src.declared() if name in plain]
    found += [(src.at(m.start()), m.group(1)) for m in re.finditer(r"\.(\w+)\b", src.code) if m.group(1) in plain and m.group(1)[0].islower()]
    for key in facts["retired"]:
        owner, dot, member = key.partition(".")
        if dot:
            found += [(src.at(m.start()), key) for m in re.finditer(rf"\b{owner}\.{member}\b", src.code)]
            if src.stem == owner:
                found += [(at, key) for name, _, at in src.functions if name == member]
    return found


DETECTIONS = {
    "bool-is-prefix": _bool_is_prefix, "side-order": _side_order, "getter-pairs": _getter_pairs,
    "signal-shape": _signal_shape, "handler-shaped-property": _handler_shaped_property,
    "callback-param": _callback_param, "unit-suffix": _unit_suffix, "collection-suffix": _collection_suffix,
    "short-params": _short_params, "acronym-case": _acronym_case, "spelling": _spelling, "retired": _retired,
}


def survey(only=None):
    """({file: {rule: [symbol]}} past the exceptions, errors): every hit of the rules in `only` (default all)."""
    retired, errors = manifests.retired()
    sources = [Source(f.relative_to(ROOT).as_posix(), f.read_text()) for f in qml_modules.qml_files() if f.is_file()]
    suffixes = {}
    for src in sources:
        for name, _, _ in src.functions:
            if m := GETTER.fullmatch(name.lstrip("_")):
                suffixes.setdefault(m.group(1), set()).add(m.group(2))
    facts = {"retired": retired, "suffixes": suffixes}
    hits = qml_modules.Hits()
    for src in sources:
        for rule, detect in DETECTIONS.items():
            if only is None or rule in only:
                found = detect(src, facts)
                hits.add_at(src.rel, rule, src.text, [(at, token) for at, token in found if at is not None])
                for at, token in found:
                    if at is None:
                        hits.add(src.rel, rule, f"{src.stem}:{token}")
    found = hits.found()
    exceptions, more = qml_modules.load_exceptions(EXCEPTIONS, set(RULES))
    errors += more + qml_modules.waive(found, exceptions, "scripts/names-exceptions.json")
    return found, errors


def retired_sites():
    """The `names.json` retired keys with a site under qml/ that no exception waives."""
    found, _ = survey(only=("retired",))
    return {re.sub(r"#\d+$", "", symbol.rpartition(":")[2])
            for rules in found.values() for symbol in rules.get("retired", ())}


def check():
    found, errors = survey()
    return errors + [f"{f}: {r} {s}" for f, rules in found.items() for r, syms in rules.items() for s in syms]


def main():
    errors = check()
    if errors:
        print("\n".join(errors))
        print("\n".join(qml_modules.rule_statements(errors, RULES)))
        print(f"\n{len(errors)} naming check failure(s)")
        sys.exit(1)
    print("names ok")


if __name__ == "__main__":
    main()
