#!/usr/bin/env python3
"""The engine checks: what lives in qml/components/methods/ and how the engines listed in
scripts/engines.json call each other (docs/dev/core/engines.md > Checks). Rules:

  placed  a folder under methods/ that is neither a listed engine's folder nor a `$domains` key; a
          listed folder, `files` or `helpers` path that doesn't exist
  purity  in methods/: an import other than QtQuick, qs.components.methods and the folders the file's
          engine or `$domains` entry `uses` (a root file, and a listed engine's `files`, have no `uses`);
          Timer, Date.now(, new Date(), Math.random, console., Qt.callLater
  dag     a cycle in the forward graph (signature edges model -> solve -> drawn, `fedBy`, api `feeds`),
          in the `$domains` `uses` or among an engine folder's files (a file naming another's stem and
          `.` or ` {`); an owner or adapter calling two stages of one engine with no edge or `unfed`
          between them; an edge from a `drawn` node into another stage; a cross-engine `fedBy` or
          `intakes` entry whose seam isn't a row of engines.md > Seam register, and a register row
          between two listed engines with no such entry; an `intakes` rule no row of the engine's
          rows file names
  trace   EngineTrace used anywhere under qml/ other than through .record(, .forget( or .tracing, outside
          qml/services/core/EngineTrace.qml; any EngineTrace use in an engine's folder or files
  apply   in an engine's adapters and itemPaths: a Qt.callLater without `// allowed: apply <what>` or
          `// allowed: settle <what>` on its line; an onContactsChanged, onStretchChanged,
          onCoverChanged, onPillsChanged or onRequestsChanged handler; a setRequest( call

A hit is `<file>: <rule> <symbol>`, the symbol `<member>:<token>` (the root member enclosing it, else
the file's name) with a repeat numbered `#2`... Every hit is held to scripts/engines-baseline.json, which
only shrinks: a hit not in it fails, a baselined hit that's gone fails (delete the entry), an entry
added since the base fails unless its rule or its file is new there (the rule absent from the base's
RULES, a file of an engine absent from the base's manifest). The base is read on every run. A hit is
waived by an entry in scripts/engines-exceptions.json (rules and reason; an entry that waives nothing
fails).

  scripts/check_engines.py                    every hit past the baseline; exit 1 on any
  scripts/check_engines.py --base REF         read the base from REF (default: HEAD^1 in GitHub
                                              Actions, else the merge-base with origin/main)
  scripts/check_engines.py --update-baseline  add the hits of a rule or engine new since the base to
                                              the baseline, drop the fixed ones
"""
import argparse
import ast
import fnmatch
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_docs  # noqa: E402
import manifests  # noqa: E402
import qml_modules  # noqa: E402

ROOT = qml_modules.ROOT
METHODS = "qml/components/methods"
MANIFEST = manifests.ENGINES.relative_to(ROOT).as_posix()
SELF = "scripts/check_engines.py"
DOC = "docs/dev/core/engines.md"
TRACE_FILE = "qml/services/core/EngineTrace.qml"
EXCEPTIONS = ROOT / "scripts" / "engines-exceptions.json"
BASELINE = "scripts/engines-baseline.json"

RULES = ["placed", "purity", "dag", "trace", "apply"]

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


def _code(text):
    """`text` with its // comments removed (the line count stays)."""
    return re.sub(r"//[^\n]*", "", text)


def _expand(paths, suffix=""):
    """The repo-relative files under these files and folders that exist, sorted."""
    out = set()
    for p in paths:
        path = ROOT / p
        found = path.rglob("*") if path.is_dir() else [path] if path.is_file() else []
        out |= {f.relative_to(ROOT).as_posix() for f in found if f.is_file() and f.name.endswith(suffix)}
    return sorted(out)


class Hits:
    """The hits of a run, {file: {rule: [symbol]}} once numbered."""

    def __init__(self):
        self.pending = {}

    def add(self, file, rule, symbol, at=0):
        """A hit; `at` orders the hits of one file and rule (a repeat is numbered in that order)."""
        self.pending.setdefault((file, rule), []).append((at, symbol))

    def add_at(self, rel, rule, text, found):
        """The hits of `rel`'s text: `found` is [(offset in the code, token)]."""
        lines = text.split("\n")
        code = _code(text)
        for at, token in found:
            line = code.count("\n", 0, at)
            member = Path(rel).stem
            for raw in lines[: line + 1]:
                m = gen_docs.MEMBER.match(raw)
                if m:
                    member = m.group(3) or m.group(5) or m.group(7)
                elif re.match(r"  \S", raw) and raw[2] not in "})]":
                    member = Path(rel).stem
            self.add(rel, rule, f"{member}:{token}", at)

    def found(self):
        out = {}
        for (file, rule), hits in sorted(self.pending.items()):
            out.setdefault(file, {})[rule] = qml_modules.numbered([s for _, s in sorted(hits, key=lambda h: h[0])])
        return out


def _matches(text, patterns):
    """[(offset in the comment-stripped code, token)] of every match of {token: regex}."""
    code = _code(text)
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


def _base_rules(base):
    """RULES in the base's copy of this file ([] when the file is absent); ValueError when the base
    can't be read or its RULES isn't one assignment of a list literal."""
    text = qml_modules.file_at(base, SELF)
    if text is None:
        return []
    try:
        values = [ast.literal_eval(n.value) for n in ast.parse(text).body
                  if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "RULES" for t in n.targets)
                  and isinstance(n.value, ast.List)]
    except (SyntaxError, ValueError):
        values = []
    if len(values) != 1:
        raise ValueError(f"{SELF}: can't read RULES at the base {base}")
    return values[0]


def _new_rules(base):
    """The rule ids absent from the base's RULES and the files of each engine absent from the base's
    manifest; ValueError when the base can't be read."""
    new = set(RULES) - set(_base_rules(base))
    text = qml_modules.file_at(base, MANIFEST)
    at_base = manifests.engines(text=text)[0] if text is not None else {}
    for name, entry in manifests.engines()[0].items():
        if name not in at_base:
            held = manifests.held_paths(entry)
            new |= set(held) | set(_expand(held))
    return new


def _facade(entry):
    """The facade's repo-relative path: the .qml under the engine's folder and files named for it, else None."""
    return next((f for f in _expand([entry["folder"], *entry["files"]], ".qml") if Path(f).stem == entry["facade"]), None)


def _placed(hits, engines, domains):
    listed = [e["folder"] for e in engines.values() if e["folder"]] + [f"{METHODS}/{d}" for d in domains]
    for folder in sorted((ROOT / METHODS).iterdir()):
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
    for f in _expand([METHODS], ".qml"):
        text = (ROOT / f).read_text()
        uses = next((e["uses"] for e in engines.values() if manifests.within(f, e["folder"])), None)
        if uses is None:
            uses = next((d["uses"] for k, d in domains.items() if manifests.within(f, f"{METHODS}/{k}")), [])
        allowed = {"QtQuick", "qs.components.methods", *(f"qs.components.methods.{u}" for u in uses)}
        code = _code(text)
        found = [(m.start(1), m.group(1)) for m in IMPORT.finditer(code) if m.group(1) not in allowed]
        hits.add_at(f, "purity", text, found + _matches(text, PURITY))


def _dag(hits, engines, domains):
    edges, linked, graphs = set(), set(), {}
    for name, entry in engines.items():
        facade = _facade(entry)
        api = {}
        if facade:
            try:
                api = gen_docs.json_property(ROOT / facade, "api", default={})
            except ValueError:
                hits.add(facade, "dag", "api:not literal")
        stages = {s for s, v in api.items() if isinstance(v, dict) and not v.get("extra")}
        graphs[name] = (stages, {s: v for s, v in api.items() if isinstance(v, dict)})
        node = lambda s: f"{name}.{s}"  # noqa: E731
        for a, b in (("model", "solve"), ("solve", "drawn")):
            if {a, b} <= stages:
                edges.add((node(a), node(b)))
        for key, value in graphs[name][1].items():
            if value.get("feeds"):
                edges.add((node(key), node(value["feeds"])))
            linked |= {frozenset((node(key), node(s))) for s in value.get("unfed", [])}
        for stage, items in entry["fedBy"].items():
            for it in items:
                if it.get("from") and it["from"] != "host":
                    edges.add((it["from"], node(stage)))
        for stage, items in entry["intakes"].items():
            linked |= {frozenset((it["from"], node(stage))) for it in items if it.get("from", "").split(".")[0] == name}
    linked |= {frozenset(e) for e in edges}
    graph = {}
    for a, b in edges:
        graph.setdefault(a, []).append(b)
    for cycle in _cycles(graph):
        hits.add(MANIFEST, "dag", _cycle_symbol(cycle))
    for a, b in sorted(edges):
        if a.endswith(".drawn") and not b.endswith(".drawn"):
            hits.add(MANIFEST, "dag", f"{a}:{a}→{b}")
    uses = {k: [u for u in d["uses"]] for k, d in domains.items()}
    for cycle in _cycles(uses):
        hits.add(MANIFEST, "dag", _cycle_symbol(cycle))
    for name, entry in engines.items():
        files = _expand([entry["folder"]], ".qml") if entry["folder"] else []
        code = {Path(f).stem: _code((ROOT / f).read_text()) for f in files}
        inner = {s: [o for o in code if o != s and re.search(rf"\b{o}(?:\.| \{{)", code[s])] for s in code}
        for cycle in _cycles(inner):
            hits.add(next(f for f in files if Path(f).stem == cycle[0]), "dag", _cycle_symbol(cycle))
        stages = graphs[name][0]
        for f in _expand([*entry["owners"], *entry["adapters"]], ".qml"):
            text = (ROOT / f).read_text()
            called = [(m.start(), m.group(1)) for m in re.finditer(rf"\b{entry['facade']}\.(\w+)\(", _code(text)) if m.group(1) in stages]
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
    inside = set(_expand([p for e in engines.values() for p in (e["folder"], *e["files"]) if p]))
    for path in qml_modules.qml_files():
        f = path.relative_to(ROOT).as_posix()
        if not path.exists() or f == TRACE_FILE:
            continue
        text = (ROOT / f).read_text()
        found = [(m.start(), f"EngineTrace.{m.group(1)}") for m in TRACE.finditer(_code(text))
                 if f in inside or (m.group(1), m.group(2)) not in TRACE_USES]
        hits.add_at(f, "trace", text, found)


def _apply(hits, engines):
    for f in _expand([p for e in engines.values() for p in (*e["adapters"], *e["itemPaths"])], ".qml"):
        text = (ROOT / f).read_text()
        lines = text.split("\n")
        found = [(at, token) for at, token in _matches(text, APPLY)
                 if token != "Qt.callLater" or not ALLOWED.search(lines[_code(text).count("\n", 0, at)])]
        hits.add_at(f, "apply", text, found)


def survey():
    """({file: {rule: [symbol]}} past the exceptions, errors): every hit of the five rules."""
    engines, errors = manifests.engines()
    domains = manifests.domains()
    hits = Hits()
    _placed(hits, engines, domains)
    _purity(hits, engines, domains)
    _dag(hits, engines, domains)
    _trace(hits, engines)
    _apply(hits, engines)
    found = hits.found()
    exceptions, more = qml_modules.load_exceptions(EXCEPTIONS, set(RULES))
    errors += more
    for pattern, entry in sorted(exceptions.items()):
        for rule in entry["rules"]:
            if not any(fnmatch.fnmatch(file, pattern) and rule in found[file] for file in found):
                errors.append(f"scripts/engines-exceptions.json: {pattern} lists {rule}, which no file under it hits")
    for pattern, entry in sorted(exceptions.items()):
        for file in list(found):
            if fnmatch.fnmatch(file, pattern):
                for rule in entry["rules"]:
                    found[file].pop(rule, None)
                if not found[file]:
                    del found[file]
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
                print(f"{qml_modules.add_to_baseline(found, BASELINE, new_rules)} entries in {BASELINE}")
                return
        else:
            errors = check(base)
    except ValueError as e:
        errors = [str(e)]
    if errors:
        print("\n".join(errors))
        print(f"\n{len(errors)} engine check failure(s) ({DOC} > Checks)")
        sys.exit(1)
    print("engines ok")


if __name__ == "__main__":
    main()
