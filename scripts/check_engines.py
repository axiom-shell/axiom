#!/usr/bin/env python3
"""The engine checks: what lives in qml/components/methods/ and how the engines listed in
scripts/engines.json call each other (docs/dev/core/engines.md > Checks). Rules: `RULES` below, one statement each; a
failing rule's statement prints under the failures.

A hit is `<file>: <rule> <symbol>`, the symbol `<member>:<token>` (the root member enclosing it, else
the file's name) with a repeat numbered `#2`... Every hit is held to scripts/engines-baseline.json, which
only shrinks: a hit not in it fails, a baselined hit that's gone fails (delete the entry), an entry
added since the base fails unless its rule or its file is new there (the rule absent from the base's
RULES, a file of an engine absent from the base's manifest) or it moved: the same rule and symbol was
listed at the base under a file where it no longer is, and their count doesn't grow. The base is read on
every run. A hit is waived by an entry in scripts/engines-exceptions.json (rules and reason; an
entry that waives nothing fails).

  scripts/check_engines.py                    every hit past the baseline; exit 1 on any
  scripts/check_engines.py --base REF         read the base from REF (default: HEAD^1 in GitHub
                                              Actions, else the merge-base with origin/main)
  scripts/check_engines.py --update-baseline  add the hits of a rule or engine new since the base to
                                              the baseline, re-key a moved entry, drop the fixed ones
"""
import argparse
import collections
import itertools
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_docs  # noqa: E402
import manifests  # noqa: E402
import qml_modules  # noqa: E402

ROOT = qml_modules.ROOT
MANIFEST = manifests.ENGINES.relative_to(ROOT).as_posix()
SELF = "scripts/check_engines.py"
DOC = "docs/dev/core/engines.md"
TRACE_FILE = "qml/services/core/EngineTrace.qml"
EXCEPTIONS = ROOT / "scripts" / "engines-exceptions.json"
BASELINE = "scripts/engines-baseline.json"

RULES = {
    "placed": "a folder under methods/ that is neither a listed engine's folder nor a `$domains` key; a listed folder, `files` or `helpers` path that doesn't exist",
    "purity": "in methods/: an import other than QtQuick, qs.components.methods and the folders the file's engine or `$domains` entry `uses` (a root file, and a listed engine's `files`, have no `uses`); Timer, Date.now(, new Date(), Math.random, console., Qt.callLater",
    "facade-only": "outside an engine's files: a use of an internal file; a stage called from a file its Caller column (engines.md > Stages) doesn't allow; a kit used outside `itemPaths`; an extra called from a plug-in folder without `\"plugins\": true`",
    "api": "in a facade: `api` not JSON, not the first member, a function with no key or a key with no function, an `in` that isn't the function's destructure, an `out` producer that isn't an engine file's member",
    "shape": "in a facade: an `api` key that isn't a stage or an extra, an `in` key a verb doesn't allow or a required one missing, a function not in the one form; in an engine file: more lines than the file shape allows, a function over 60 lines, an expression with two ternaries",
    "dag": "a cycle in the forward graph (signature edges model -> solve -> drawn, `fedBy`, api `feeds`), in the `$domains` `uses` or among an engine folder's files (a file naming another's stem and `.` or ` {`); an owner or adapter calling two stages of one engine with no edge or `unfed` between them; an edge from a `drawn` node into another stage; a cross-engine `fedBy` or `intakes` entry whose seam isn't a row of engines.md > Seam register, and a register row between two listed engines with no such entry; an `intakes` rule no row of the engine's rows file names",
    "tables": "the manifest's `tables` entries, and each table in its file: a row with the wrong keys or no `why`, a repeated id, an uncovered or doubled cell, an ordered table without a catch-all, a `\"rule\": \"<id>\"` literal that names no row or function",
    "alone": "a match of an `alone` entry's regex in a file outside its `only` paths; the key itself not a list",
    "contract": "an engine's rows file: an `api` key or a rule id no row names, a row whose `call` isn't an `api` key, a row with `args`",
    "edit-points": "an `editPoints` symbol that isn't a file or a member of a file the engine holds; the key itself not an object",
    "doc": "the manifest's `doc` file missing, or lacking one of the eleven headings in order",
    "apply": "in an engine's adapters and itemPaths: a Qt.callLater without `// allowed: apply <what>` or `// allowed: settle <what>` on its line; an onContactsChanged, onStretchChanged, onCoverChanged, onPillsChanged or onRequestsChanged handler; a setRequest( call",
    "trace": "EngineTrace used anywhere under qml/ other than through .record(, .forget( or .tracing, outside qml/services/core/EngineTrace.qml; any EngineTrace use in an engine's folder or files",
}

IMPORT = re.compile(r"^\s*import\s+([\w.]+)", re.M)
PURITY = {"Timer": r"\bTimer\s*\{", "Date.now": r"\bDate\.now\(", "new Date()": r"\bnew Date\(\s*\)",
          "Math.random": r"\bMath\.random\b", "console": r"\bconsole\.", "Qt.callLater": r"\bQt\.callLater\b"}
TRACE = re.compile(r"\bEngineTrace\.(\w*)(\()?")
TRACE_USES = {("record", "("), ("forget", "("), ("tracing", None)}
APPLY = {"Qt.callLater": r"\bQt\.callLater\b",
         **{f"on{n}Changed": rf"\bon{n}Changed\b" for n in ("Contacts", "Stretch", "Cover", "Pills", "Requests")},
         "setRequest": r"\bsetRequest\("}
ALLOWED = re.compile(r"// allowed: (?:apply|settle) \S")
STAGE_NAME = re.compile(r"`([^`]+)`")
# engines.md > Stages: verb -> (allowed input keys, [required groups: one key of each])
STAGES = {"model": ({"config", "state", "env", "tuning"}, [{"config", "state"}]),
          "solve": ({"request", "model", "prev", "env", "tuning"}, [{"request"}]),
          "reduce": ({"prev", "now", "entries", "event", "state", "env", "config", "tuning"},
                     [{"prev"}, {"now"}, {"entries", "event"}]),
          "drawn": ({"result", "motion", "state", "tuning"}, [{"result"}, {"motion"}])}
RULE_LITERAL = re.compile(r'"rule"\s*:\s*"([^"]*)"')
FACADE_LINES = 200
FILE_LINES = 500
FUNCTION_LINES = 60


def _expand(paths, suffix=""):
    """The repo-relative files under these files and folders that exist, sorted."""
    out = set()
    for p in paths:
        path = ROOT / p
        found = path.rglob("*") if path.is_dir() else [path] if path.is_file() else []
        out |= {f.relative_to(ROOT).as_posix() for f in found if f.is_file() and f.name.endswith(suffix)}
    return sorted(out)


def _matches(text, patterns):
    """[(offset in the comment-stripped code, token)] of every match of {token: regex}."""
    code = qml_modules.blank_comments(text)
    return [(m.start(), token) for token, rx in patterns.items() for m in re.finditer(rx, code)]


def _cycles(graph):
    """The cycles of {node: [next nodes]}, each [a, ..., a] starting at its smallest node."""
    found, seen, done = [], set(), set()

    def walk(node, path):
        for nxt in sorted(graph.get(node, ())):
            if nxt in path:
                cycle = path[path.index(nxt):]
                low = cycle.index(min(cycle))
                cycle = cycle[low:] + cycle[:low]
                if tuple(cycle) not in seen:
                    seen.add(tuple(cycle))
                    found.append(cycle + [cycle[0]])
            elif nxt not in done:
                walk(nxt, path + [nxt])
        done.add(node)

    for node in sorted(graph):
        if node not in done:
            walk(node, [node])
    return found


def _cycle_symbol(cycle):
    return f"{cycle[0]}:{'→'.join(cycle)}"


def _load_rows(path):
    """The `rows` array of a rows file: the JSON after `var rows =`, without its closing `;`."""
    body = Path(path).read_text().partition("var rows =")[2].strip().removesuffix(";")
    return json.loads(body)


def _seam_register():
    """{Id: (producers, consumers)} of the table under `## Seam register` in engines.md, each a set of the
    backticked `<engine>.<stage>` names of its Producer and Consumers cells; {} when there is no such heading."""
    doc = ROOT / DOC
    text = doc.read_text() if doc.exists() else ""
    rows, inside = {}, False
    for line in text.split("\n"):
        if line.startswith("#"):
            inside = line.strip() == "## Seam register"
        elif inside and line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 6 and cells[0] != "Id" and not set(cells[0]) <= set("-: "):
                rows[cells[0].strip("`")] = (set(STAGE_NAME.findall(cells[4])), set(STAGE_NAME.findall(cells[5])))
    return rows


def _new_rules(base):
    """The rule ids absent from the base's RULES and the files of each engine absent from the base's
    manifest; ValueError when the base can't be read."""
    new = qml_modules.new_rules(base, SELF, RULES)
    text = qml_modules.file_at(base, MANIFEST)
    at_base = manifests.engines(text=text)[0] if text is not None else {}
    for name, entry in manifests.engines()[0].items():
        if name not in at_base:
            held = manifests.held_paths(entry)
            new |= set(held) | set(_expand(held))
    return new


def _engine_files(entry):
    """An engine's own QML files: the .qml under its folder and files, sorted."""
    return _expand([p for p in (entry["folder"], *entry["files"]) if p], ".qml")


def _facade(entry):
    """The facade's repo-relative path: the .qml under the engine's folder and files named for it, else None."""
    return next((f for f in _engine_files(entry) if Path(f).stem == entry["facade"]), None)


def _api_of(facade):
    """The `api` object of a facade (a repo-relative path): {} when it has none, None when it isn't a JSON object."""
    try:
        api = gen_docs.json_property(ROOT / facade, "api", default={})
    except ValueError:
        return None
    return api if isinstance(api, dict) else None


def _placed(hits, engines, domains):
    listed = [e["folder"] for e in engines.values() if e["folder"]] + [f"{qml_modules.METHODS}/{d}" for d in domains]
    for folder in sorted((ROOT / qml_modules.METHODS).iterdir()):
        rel = folder.relative_to(ROOT).as_posix()
        if folder.is_dir() and not any(manifests.within(rel, p) for p in listed):
            hits.add(rel, "placed", folder.name)
    for name, entry in engines.items():
        for path in manifests.held_paths(entry):
            key = ("folder" if path == entry["folder"] else "files" if path in entry["files"]
                   else "helpers" if Path(path).parent.as_posix() == entry["folder"] and Path(path).stem in entry["helpers"] else None)
            if key and not (ROOT / path).exists():
                hits.add(MANIFEST, "placed", f"{name}.{key}:{path}")
        if _facade(entry) is None:
            hits.add(MANIFEST, "placed", f"{name}.facade:{entry['facade']}")


def _purity(hits, engines, domains):
    for f in _expand([qml_modules.METHODS], ".qml"):
        text = (ROOT / f).read_text()
        uses = next((e["uses"] for e in engines.values() if manifests.within(f, e["folder"])), None)
        if uses is None:
            uses = next((d["uses"] for k, d in domains.items() if manifests.within(f, f"{qml_modules.METHODS}/{k}")), [])
        allowed = {"QtQuick", "qs.components.methods", *(f"qs.components.methods.{u}" for u in uses)}
        code = qml_modules.blank_comments(text)
        found = [(m.start(1), m.group(1)) for m in IMPORT.finditer(code) if m.group(1) not in allowed]
        hits.add_at(f, "purity", text, found + _matches(text, PURITY))


def _graph(engines):
    """(edges, apis) of the listed engines. `apis` is {engine: {key: value}}, the facade `api` entries that are
    objects. `edges` is [(kind, from, to, item)] in manifest order, nodes `<engine>.<stage>`: "signature"
    (model to solve, solve to drawn, both stages), "feeds" (an `api` entry's `feeds`), "fedBy" (an item whose
    `from` is set and isn't `host`) and "intakes" (an item whose `from` is set); `item` is the manifest item
    ({} for the first two)."""
    edges, apis = [], {}
    for name, entry in engines.items():
        facade = _facade(entry)
        api = (_api_of(facade) if facade else {}) or {}
        apis[name] = {s: v for s, v in api.items() if isinstance(v, dict)}
        stages = {s for s, v in apis[name].items() if not v.get("extra")}
        node = lambda s: f"{name}.{s}"  # noqa: E731
        for a, b in (("model", "solve"), ("solve", "drawn")):
            if {a, b} <= stages:
                edges.append(("signature", node(a), node(b), {}))
        for key, value in apis[name].items():
            if value.get("feeds"):
                edges.append(("feeds", node(key), node(value["feeds"]), {}))
        for stage, items in entry["fedBy"].items():
            edges += [("fedBy", it["from"], node(stage), it) for it in items if it.get("from") and it["from"] != "host"]
        for stage, items in entry["intakes"].items():
            edges += [("intakes", it["from"], node(stage), it) for it in items if it.get("from")]
    return edges, apis


def _dag(hits, engines, domains):
    graphs, (found, apis) = {}, _graph(engines)
    edges = {(a, b) for kind, a, b, _ in found if kind != "intakes"}
    linked = {frozenset((a, b)) for kind, a, b, _ in found if kind == "intakes" and a.split(".")[0] == b.split(".")[0]}
    for name, api in apis.items():
        graphs[name] = ({s for s, v in api.items() if not v.get("extra")}, api)
        for key, value in api.items():
            unfed = value.get("unfed")
            if isinstance(unfed, list) and all(isinstance(s, str) for s in unfed):
                linked |= {frozenset((f"{name}.{key}", f"{name}.{s}")) for s in unfed}
    linked |= {frozenset(e) for e in edges}
    graph = {}
    for a, b in edges:
        graph.setdefault(a, []).append(b)
    for cycle in _cycles(graph):
        hits.add(MANIFEST, "dag", _cycle_symbol(cycle))
    for a, b in sorted(edges):
        if a.endswith(".drawn") and not b.endswith(".drawn"):
            hits.add(MANIFEST, "dag", f"{a}:{a}→{b}")
    uses = {k: d["uses"] for k, d in domains.items()}
    for cycle in _cycles(uses):
        hits.add(MANIFEST, "dag", _cycle_symbol(cycle))
    for name, entry in engines.items():
        files = _expand([entry["folder"]], ".qml") if entry["folder"] else []
        code = {Path(f).stem: qml_modules.blank_comments((ROOT / f).read_text()) for f in files}
        inner = {s: [o for o in code if o != s and re.search(rf"\b{o}(?:\.| \{{)", code[s])] for s in code}
        for cycle in _cycles(inner):
            hits.add(next(f for f in files if Path(f).stem == cycle[0]), "dag", _cycle_symbol(cycle))
        stages = graphs[name][0]
        for f in _expand([*entry["owners"], *entry["adapters"]], ".qml"):
            text = (ROOT / f).read_text()
            called = [(m.start(), m.group(1)) for m in re.finditer(rf"\b{entry['facade']}\.(\w+)\(", qml_modules.blank_comments(text)) if m.group(1) in stages]
            seen = sorted({s for _, s in called})
            for i, a in enumerate(seen):
                for b in seen[i + 1:]:
                    if frozenset((f"{name}.{a}", f"{name}.{b}")) not in linked:
                        hits.add_at(f, "dag", text, [(min(at for at, s in called if s in (a, b)), f"{a}+{b}")])
    _seams(hits, engines)


def _seams(hits, engines):
    register = _seam_register()
    for name, entry in engines.items():
        rows = []
        try:
            rows = _load_rows(ROOT / entry["tests"]["rows"])
        except (OSError, ValueError):
            pass
        for kind in ("fedBy", "intakes"):
            for stage, items in entry[kind].items():
                for it in items:
                    if it.get("from") and it["from"].split(".")[0] != name and it.get("seam") not in register:
                        hits.add(MANIFEST, "dag", f"{name}.{stage}:{it.get('seam')}")
        for stage, items in entry["intakes"].items():
            for it in items:
                if it.get("rule") and not any(_pins(row, it["rule"]) for row in rows):
                    hits.add(entry["tests"]["rows"] or MANIFEST, "dag", f"{name}.{stage}:{it['rule']}")
    for seam, (producers, consumers) in sorted(register.items()):
        for p in sorted(producers):
            for c in sorted(consumers):
                to, stage = c.partition(".")[0], c.partition(".")[2]
                if p.partition(".")[0] in engines and to in engines:
                    entries = engines[to]["fedBy"].get(stage, []) + engines[to]["intakes"].get(stage, [])
                    if not any(it.get("seam") == seam and it.get("from") == p for it in entries):
                        hits.add(DOC, "dag", f"{seam}:{p}→{c}")


def _pins(row, rule):
    """Whether a rows-file row names `rule` as a string in its `expect` or a step's `expect`."""
    def has(value):
        if isinstance(value, dict):
            return any(has(v) for v in value.values())
        if isinstance(value, list):
            return any(has(v) for v in value)
        return value == rule

    if not isinstance(row, dict):
        return False
    steps = [s for s in row.get("steps", []) if isinstance(s, dict)] if isinstance(row.get("steps"), list) else []
    return any(has(x.get("expect")) for x in [row, *steps])


def _trace(hits, engines):
    inside = {f for e in engines.values() for f in _engine_files(e)}
    for path in qml_modules.qml_files():
        f = path.relative_to(ROOT).as_posix()
        if not path.exists() or f == TRACE_FILE:
            continue
        text = (ROOT / f).read_text()
        found = [(m.start(), f"EngineTrace.{m.group(1)}") for m in TRACE.finditer(qml_modules.blank_comments(text))
                 if f in inside or (m.group(1), m.group(2)) not in TRACE_USES]
        hits.add_at(f, "trace", text, found)


def _apply(hits, engines):
    for f in _expand(manifests.adapter_paths(engines), ".qml"):
        text = (ROOT / f).read_text()
        lines = text.split("\n")
        found = [(at, token) for at, token in _matches(text, APPLY)
                 if token != "Qt.callLater" or not ALLOWED.search(lines[qml_modules.blank_comments(text).count("\n", 0, at)])]
        hits.add_at(f, "apply", text, found)


def _form_keys(lines, member):
    """The keys a facade function destructures when it is in the one form (`  function <f>(input) {`, then
    `    const {…} = input;`), else None; `lines` are the file's lines, `member` its parse_qml member."""
    at = member["line"] - 1
    found = re.fullmatch(r"    const \{(.*)\} = input;", lines[at + 1]) if at + 1 < len(lines) else None
    if lines[at] != f"  function {member['name']}(input) {{" or not found:
        return None
    return {re.split(r"[=:]", part)[0].strip() for part in gen_docs.split_top(found.group(1), 0, len(found.group(1)))}


def _expressions(code):
    """[(offset, text)] of the expressions of comment-stripped `code`: each string's contents blanked to spaces, then
    split at `;`, `{`, `}` and line ends where no `(` or `[` is open; the offset is the first non-blank character."""
    text, i = list(code), 0
    while i < len(code):
        if code[i] in "\"'`":
            end = gen_docs._skip_string(code, i)
            for j in range(i + 1, min(end - 1, len(code))):
                if text[j] != "\n":
                    text[j] = " "
            i = end
        else:
            i += 1
    text = "".join(text) + "\n"
    out, depth, start = [], 0, 0
    for i, c in enumerate(text):
        if c in "([":
            depth += 1
        elif c in ")]":
            depth = max(0, depth - 1)
        elif depth == 0 and c in ";{}\n":
            part = text[start:i]
            if part.strip():
                out.append((start + len(part) - len(part.lstrip()), part.strip()))
            start = i + 1
    return out


def _table_entries(tables, files=None, folder=""):
    """([(key, kind, file, property, rows, ids)], [bad keys]) of an owner's `tables` object. A table's `<File>` is
    the stem of one of `files`, else a file of `folder`; `rows` is the property's JSON literal (None when it
    isn't one); `ids` are a cell or ordered table's row ids. A key that isn't `<File>.<property>` of an existing
    file's property, an entry that isn't an object, a `kind` other than cell, ordered or rank and an `id` that
    isn't a string is bad."""
    good, bad = [], []
    for key, entry in tables.items():
        stem, _, prop = key.partition(".")
        file = next((f for f in files if Path(f).stem == stem), None) if files is not None else f"{folder}/{stem}.qml"
        if not prop or "." in prop or not file or not (ROOT / file).is_file() or not isinstance(entry, dict) \
                or entry.get("kind") not in ("cell", "ordered", "rank") or not isinstance(entry.get("id", "name"), str):
            bad.append(key)
            continue
        try:
            rows = gen_docs.json_property(ROOT / file, prop, default=None)
        except ValueError:
            rows = None
        else:
            if rows is None:
                bad.append(key)
                continue
        ids = {r["id"] for r in rows if isinstance(r, dict) and isinstance(r.get("id"), str)} \
            if entry["kind"] != "rank" and isinstance(rows, list) else set()
        good.append((key, entry["kind"], file, prop, rows, ids))
    return good, bad


def _facade_only(hits, engines):
    for entry in engines.values():
        facade, main, folder, mine = entry["facade"], _facade(entry), entry["folder"], set(_engine_files(entry))
        api = (_api_of(main) if main else {}) or {}
        internal = [Path(f).stem for f in sorted(mine) if f != main and manifests.within(f, folder)
                    and Path(f).stem not in (*entry["helpers"], *entry["kits"])]
        callers = {"model": entry["owners"], "reduce": entry["owners"],
                   "solve": [*entry["owners"], *entry["adapters"]], "drawn": entry["adapters"]}
        extras = [x for x, v in api.items() if isinstance(v, dict) and v.get("extra") and not v.get("plugins")]
        for path in qml_modules.qml_files():
            f = path.relative_to(ROOT).as_posix()
            if not path.exists() or f in mine:
                continue
            patterns = {i: rf"\b{i}\." for i in internal}
            patterns.update({f"{facade}.{s}": rf"\b{facade}\.{s}\(" for s, paths in callers.items() if not any(manifests.within(f, p) for p in paths)})
            patterns.update({k: rf"\b{k}(?:\.| \{{)" for k in entry["kits"] if not any(manifests.within(f, p) for p in entry["itemPaths"])})
            if any(manifests.within(f, p) for p in entry["pluginPaths"]):
                patterns.update({f"{facade}.{x}": rf"\b{facade}\.{x}\(" for x in extras})
            text = path.read_text()
            hits.add_at(f, "facade-only", text, _matches(text, patterns))


def _api(hits, engines):
    for entry in engines.values():
        facade = _facade(entry)
        if facade is None:
            continue
        api = _api_of(facade)
        if api is None:
            hits.add(facade, "api", "api:not literal")
            continue
        members = gen_docs.parse_qml(ROOT / facade)[1]
        lines = (ROOT / facade).read_text().splitlines()
        functions = {m["name"]: m for m in members if m["kind"] == "function"}
        files = {Path(f).stem: f for f in _engine_files(entry)}
        if not members or members[0]["name"] != "api":
            hits.add(facade, "api", "api:not first")
        for name in functions:
            if name not in api:
                hits.add(facade, "api", f"{name}:no api entry")
        for key, value in api.items():
            value = value if isinstance(value, dict) else {}
            if key not in functions:
                hits.add(facade, "api", f"api.{key}:no function")
            elif isinstance(value.get("in"), list) and all(isinstance(i, str) for i in value["in"]) \
                    and _form_keys(lines, functions[key]) not in (None, set(value["in"])):
                hits.add(facade, "api", f"api.{key}:in")
            if "unfed" in value and not (isinstance(value["unfed"], list) and all(isinstance(s, str) for s in value["unfed"])):
                hits.add(facade, "api", f"api.{key}:unfed")
            for producer in value["out"].values() if isinstance(value.get("out"), dict) else []:
                stem, _, member = str(producer).partition(".")
                if stem not in files or member not in {m["name"] for m in gen_docs.parse_qml(ROOT / files[stem])[1]}:
                    hits.add(facade, "api", f"api.{key}:{producer}")


def _shape(hits, engines):
    for entry in engines.values():
        facade = _facade(entry)
        api = _api_of(facade) if facade else None
        if api is not None:
            lines = (ROOT / facade).read_text().splitlines()
            functions = {m["name"]: m for m in gen_docs.parse_qml(ROOT / facade)[1] if m["kind"] == "function"}
            for key, value in api.items():
                value = value if isinstance(value, dict) else {}
                if key not in STAGES and not value.get("extra"):
                    hits.add(facade, "shape", f"api.{key}:not a stage")
                verb = key if key in STAGES else (next((v for v in STAGES if re.match(rf"{v}[A-Z]", key)), None) if value.get("extra") else None)
                if verb and isinstance(value.get("in"), list):
                    allowed, groups = STAGES[verb]
                    for item in value["in"]:
                        if not isinstance(item, str) or item not in allowed:
                            hits.add(facade, "shape", f"api.{key}:{item}")
                    for group in groups:
                        if not group & {i for i in value["in"] if isinstance(i, str)}:
                            hits.add(facade, "shape", f"api.{key}:needs {'|'.join(sorted(group))}")
                if key in functions and _form_keys(lines, functions[key]) is None:
                    hits.add(facade, "shape", f"{key}:form")
        for f in _engine_files(entry):
            text = (ROOT / f).read_text()
            if len(text.splitlines()) > (FACADE_LINES if f == facade else FILE_LINES):
                hits.add(f, "shape", f"{Path(f).stem}:lines")
            for m in gen_docs.parse_qml(ROOT / f)[1]:
                if m["kind"] == "function" and m["end"] - m["line"] + 1 > FUNCTION_LINES:
                    hits.add(f, "shape", f"{m['name']}:lines")
            found = [(at, "ternary") for at, expr in _expressions(qml_modules.blank_comments(text)) if len(re.findall(r"(?<!\?)\?(?![?.])", expr)) >= 2]
            hits.add_at(f, "shape", text, found)


def _axes_of(file):
    """A cell table file's `axes`: ({axis: [values]}, None), else (None, "no axes") when it has none or
    (None, "axes not literal") when it isn't JSON of that shape."""
    try:
        axes = gen_docs.json_property(ROOT / file, "axes", default=None)
    except ValueError:
        return None, "axes not literal"
    if axes is None:
        return None, "no axes"
    if not isinstance(axes, dict) or not all(
            isinstance(v, list) and all(isinstance(i, (str, int, float, bool)) for i in v) for v in axes.values()):
        return None, "axes not literal"
    return axes, None


def _tables_of(engines, flat, domains):
    """[(owner, tables, files, folder, entry)] of every rules-table owner: the engines, `$flat` and `$domains`."""
    owners = [(name, e["tables"], _engine_files(e), "", e) for name, e in engines.items()]
    owners += [(f"$flat.{k}", v["tables"], None, qml_modules.METHODS, None) for k, v in flat.items()]
    owners += [(f"$domains.{k}", v["tables"], None, f"{qml_modules.METHODS}/{k}", None) for k, v in domains.items()]
    return owners


def _tables(hits, engines, flat, domains):
    for owner, tables, files, folder, entry in _tables_of(engines, flat, domains):
        if not isinstance(tables, dict):
            hits.add(MANIFEST, "tables", f"{owner}.tables:not an object")
            continue
        good, bad = _table_entries(tables, files, folder)
        for key in bad:
            hits.add(MANIFEST, "tables", f"{owner}.tables:{key}")
        seen = set()
        for key, kind, file, prop, rows, _ in good:
            if not isinstance(rows, list):
                hits.add(file, "tables", f"{prop}:not literal")
                continue
            functions = {m["name"] for m in gen_docs.parse_qml(ROOT / file)[1] if m["kind"] == "function"}
            axes = None
            if kind == "cell":
                axes, problem = _axes_of(file)
                if problem:
                    hits.add(file, "tables", f"{prop}:{problem}")
            name_key = tables[key].get("id", "name")
            expected = {"id", "when", "then"} if kind != "rank" else {name_key, "rank"}
            cover = collections.Counter()
            for index, row in enumerate(rows, 1):
                row = row if isinstance(row, dict) else {}
                rid = row.get(name_key if kind == "rank" else "id")
                label = rid if isinstance(rid, str) and rid else f"#{index}"
                when = row.get("when")
                ok = set(row) - {"why"} == expected
                if kind == "cell" and axes:
                    ok = ok and isinstance(when, dict) and set(when) == set(axes) and all(
                        v in axes[a] for a, w in when.items() for v in (w if isinstance(w, list) else [w]))
                if kind == "ordered":
                    ok = ok and ((when is True and index == len(rows)) or (isinstance(when, str) and when in functions))
                if not ok:
                    hits.add(file, "tables", f"{prop}:{label} bad row")
                if not isinstance(row.get("why"), str) or not row["why"].strip():
                    hits.add(file, "tables", f"{prop}:{label} no why")
                if isinstance(rid, str) and rid:
                    if label in seen:
                        hits.add(file, "tables", f"{prop}:{label} duplicate")
                    seen.add(label)
                if kind == "cell" and axes and ok:
                    cover.update(itertools.product(*([(a, v) for v in (w if isinstance(w, list) else [w])] for a, w in sorted(when.items()))))
            if kind == "cell" and axes:
                for combo in itertools.product(*([(a, v) for v in axes[a]] for a in sorted(axes))):
                    text = ",".join(f"{a}={v}" for a, v in combo)
                    if cover[combo] == 0:
                        hits.add(file, "tables", f"{prop}:{text} uncovered")
                    elif cover[combo] > 1:
                        hits.add(file, "tables", f"{prop}:{text} twice")
            if kind == "ordered" and not (rows and isinstance(rows[-1], dict) and rows[-1].get("when") is True):
                hits.add(file, "tables", f"{prop}:no catch-all")
        if entry is not None:
            named = set().union(*(t[5] for t in good)) | {m["name"] for f in files for m in gen_docs.parse_qml(ROOT / f)[1] if m["kind"] == "function"}
            for f in files:
                text = (ROOT / f).read_text()
                found = [(m.start(), f"rule {m.group(1)}") for m in RULE_LITERAL.finditer(qml_modules.blank_comments(text)) if m.group(1) not in named]
                hits.add_at(f, "tables", text, found)


def _alone(hits, engines):
    for name, entry in engines.items():
        if not isinstance(entry["alone"], list):
            hits.add(MANIFEST, "alone", f"{name}.alone:not a list")
            continue
        for item in entry["alone"]:
            item = item if isinstance(item, dict) else {}
            regex = item.get("regex", "")
            try:
                pattern = re.compile(regex)
            except (re.error, TypeError):
                hits.add(MANIFEST, "alone", f"{name}.alone:{regex}")
                continue
            for path in qml_modules.qml_files():
                f = path.relative_to(ROOT).as_posix()
                if not path.exists() or any(manifests.within(f, p) for p in item.get("only", [])):
                    continue
                text = path.read_text()
                hits.add_at(f, "alone", text, [(m.start(), m.group()) for m in pattern.finditer(qml_modules.blank_comments(text)) if m.group()])


def _contract(hits, engines):
    for name, entry in engines.items():
        facade = _facade(entry)
        api = _api_of(facade) if facade else None
        if api is None:
            continue
        file = entry["tests"]["rows"] or MANIFEST
        try:
            rows = _load_rows(ROOT / entry["tests"]["rows"])
        except (OSError, ValueError):
            rows = None
        if not isinstance(rows, list):
            hits.add(file, "contract", f"{name}.rows:unreadable")
            continue
        called = {r["call"] for r in rows if isinstance(r, dict) and isinstance(r.get("call"), str)}
        for key in api:
            if key not in called:
                hits.add(file, "contract", f"api.{key}:no row")
        files = _engine_files(entry)
        rules = {m.group(1) for f in files for m in RULE_LITERAL.finditer(qml_modules.blank_comments((ROOT / f).read_text()))}
        if isinstance(entry["tables"], dict):
            rules |= set().union(*(t[5] for t in _table_entries(entry["tables"], files)[0]))
        for rule in sorted(rules):
            if not any(_pins(row, rule) for row in rows):
                hits.add(file, "contract", f"rule.{rule}:no row")
        for index, row in enumerate(rows):
            if not isinstance(row, dict):
                continue
            rid = row["id"] if isinstance(row.get("id"), str) else f"#{index + 1}"
            if isinstance(row.get("call"), str) and row["call"] not in api:
                hits.add(file, "contract", f"{rid}:call {row['call']}")
            if "args" in row:
                hits.add(file, "contract", f"{rid}:args")


def _edit_points(hits, engines):
    for name, entry in engines.items():
        if not isinstance(entry["editPoints"], dict):
            hits.add(MANIFEST, "edit-points", f"{name}.editPoints:not an object")
            continue
        members = {}
        for f in _expand(manifests.held_paths(entry), ".qml"):
            members.setdefault(Path(f).stem, set()).update(m["name"] for m in gen_docs.parse_qml(ROOT / f)[1])
        for kind, symbol in manifests.edit_point_rows(entry):
            stem, _, member = str(symbol).partition(".")
            if stem not in members or (member and member not in members[stem]):
                hits.add(MANIFEST, "edit-points", f"{name}.editPoints.{kind}:{symbol}")


def _doc(hits, engines):
    for name, entry in engines.items():
        doc = entry["doc"]
        if not doc or not (ROOT / doc).is_file():
            hits.add(MANIFEST, "doc", f"{name}.doc:{doc}")
            continue
        for heading in manifests.missing_headings((ROOT / doc).read_text(), manifests.ENGINE_DOC_HEADINGS):
            hits.add(doc, "doc", f"{name}:{manifests.ENGINE_DOC_HEADINGS.index(heading) + 1} {heading}")


def survey():
    """({file: {rule: [symbol]}} past the exceptions, errors): every hit of every rule."""
    engines, errors = manifests.engines()
    domains, flat = manifests.domains(), manifests.flat()
    hits = qml_modules.Hits()
    _placed(hits, engines, domains)
    _purity(hits, engines, domains)
    _dag(hits, engines, domains)
    _trace(hits, engines)
    _apply(hits, engines)
    _facade_only(hits, engines)
    _api(hits, engines)
    _shape(hits, engines)
    _tables(hits, engines, flat, domains)
    _alone(hits, engines)
    _contract(hits, engines)
    _edit_points(hits, engines)
    _doc(hits, engines)
    found = hits.found()
    exceptions, more = qml_modules.load_exceptions(EXCEPTIONS, set(RULES))
    errors += more + qml_modules.waive(found, exceptions, "scripts/engines-exceptions.json")
    return found, errors


def check(base):
    new_rules = _new_rules(base)
    found, errors = survey()
    return errors + qml_modules.ratchet(found, BASELINE, base, new_rules)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--base", default=None)
    parser.add_argument("--update-baseline", action="store_true")
    args = parser.parse_args()
    base = args.base or qml_modules.default_base()
    try:
        if args.update_baseline:
            new_rules = _new_rules(base)
            found, errors = survey()
            if not errors:
                print(f"{qml_modules.add_to_baseline(found, BASELINE, new_rules, base=base)} entries in {BASELINE}")
                return
        else:
            errors = check(base)
    except ValueError as e:
        errors = [str(e)]
    if errors:
        print("\n".join(errors))
        for line in qml_modules.rule_statements(errors, RULES):
            print(line)
        print(f"\n{len(errors)} engine check failure(s) ({DOC} > Checks)")
        sys.exit(1)
    print("engines ok")


if __name__ == "__main__":
    main()
