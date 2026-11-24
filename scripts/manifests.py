#!/usr/bin/env python3
"""The one reader of the engine manifest, scripts/engines.json.

Every check and tool reads the manifest through these functions, each taking
`text` (a manifest's JSON text; None = the tree's file) so a test or a base
revision's copy goes through the same parse and validation.

  scripts/manifests.py --tests-for PATH...   the tests of the engines holding these
                                             paths, one name per line
"""
import copy
import json
import posixpath
import sys

from qml_modules import ROOT

ENGINES = ROOT / "scripts" / "engines.json"

REQUIRED_KEYS = {"prefix": "", "facade": "", "files": [], "owners": [], "adapters": [], "tests": {}, "doc": "",
                 "editPoints": {}}
OPTIONAL_KEYS = {"folder": "", "helpers": [], "kits": [], "uses": [], "fedBy": {}, "intakes": {}, "itemPaths": [],
                 "pluginPaths": [], "feeder": "", "tables": {}, "alone": []}
TESTS_KEYS = {"rows": "", "golden": {}, "timeline": "", "sweep": [], "pixel": []}
FLAT_KEYS = {"prefix", "tables"}
DOMAIN_KEYS = {"uses", "tables", "prefix"}
ENGINE_DOC_HEADINGS = ["Role", "Inputs", "Stages", "Outputs", "Rules", "Owners, adapters, hosts", "Seams", "Tests",
                       "Checks", "Edit points", "Known gaps"]


def _parsed(text):
    """A manifest's text -> (data, errors): the parsed object (engines, `$flat`, `$domains`) and
    every error found in it (bad JSON, an unknown or missing key, a prefix used twice, a `fedBy` or `intakes`
    that isn't `{stage: [object]}` with string `from`, `seam` and `rule`)."""
    name = "scripts/engines.json"
    if text is None:
        try:
            text = ENGINES.read_text()
        except OSError as e:
            return {}, [f"{name}: can't read: {e}"]
    try:
        data = json.loads(text)
    except ValueError as e:
        return {}, [f"{name}: not JSON: {e}"]
    if not isinstance(data, dict):
        return {}, [f"{name}: not an object"]
    errors, owners = [], {}

    def claim_prefix(owner, entry):
        if entry.get("prefix"):
            if entry["prefix"] in owners:
                errors.append(f"{name}: prefix {entry['prefix']} is used by {owners[entry['prefix']]} and {owner}")
            owners.setdefault(entry["prefix"], owner)

    def check_keys(owner, entry, allowed, what="key"):
        if not isinstance(entry, dict):
            errors.append(f"{name}: {owner} is not an object")
            return False
        for key in entry:
            if key not in allowed:
                errors.append(f"{name}: {owner}: unknown {what} {key}")
        return True

    out = {}
    for engine, entry in data.items():
        if engine in ("$flat", "$domains"):
            continue
        if not check_keys(engine, entry, set(REQUIRED_KEYS) | set(OPTIONAL_KEYS)):
            continue
        for key in REQUIRED_KEYS:
            if key not in entry:
                errors.append(f"{name}: {engine}: missing key {key}")
        if isinstance(entry.get("tests"), dict):
            check_keys(f"{engine}.tests", entry["tests"], set(TESTS_KEYS))
            if "rows" not in entry["tests"]:
                errors.append(f"{name}: {engine}: missing key tests.rows")
        tests = entry["tests"] if isinstance(entry.get("tests"), dict) else {}
        entry = {**copy.deepcopy({**REQUIRED_KEYS, **OPTIONAL_KEYS}), **entry}
        entry["tests"] = {**copy.deepcopy(TESTS_KEYS), **tests}
        for key in ("fedBy", "intakes"):
            if not isinstance(entry[key], dict):
                errors.append(f"{name}: {engine}.{key} is not an object")
                entry[key] = {}
            bad = [s for s, items in entry[key].items() if not isinstance(items, list) or not all(
                isinstance(it, dict) and all(isinstance(it.get(k, ""), str) for k in ("from", "seam", "rule")) for it in items)]
            errors += [f"{name}: {engine}.{key}.{s} is not a list of objects with string from, seam and rule" for s in bad]
            entry[key] = {s: v for s, v in entry[key].items() if s not in bad}
        out[engine] = entry
        claim_prefix(engine, entry)
    sections = {}
    for section, allowed in (("$flat", FLAT_KEYS), ("$domains", DOMAIN_KEYS)):
        sections[section] = data.get(section, {})
        if not isinstance(sections[section], dict):
            errors.append(f"{name}: {section} is not an object")
            sections[section] = {}
        for helper, entry in sections[section].items():
            if check_keys(f"{section}.{helper}", entry, allowed):
                for key in sorted(allowed - ({"prefix"} if section == "$domains" else set())):
                    if key not in entry:
                        errors.append(f"{name}: {section}.{helper}: missing key {key}")
                        entry[key] = copy.deepcopy({**REQUIRED_KEYS, **OPTIONAL_KEYS}[key])
                claim_prefix(f"{section}.{helper}", entry)
    return {"engines": out, **sections}, errors


def engines(text=None):
    """{name: entry} of the listed engines (optional keys filled with their empty value) and the errors."""
    data, errors = _parsed(text)
    return data.get("engines", {}), errors


def flat(text=None):
    """`$flat`: {helper: {prefix, tables}}."""
    return _parsed(text)[0].get("$flat", {})


def domains(text=None):
    """`$domains`: {folder: {uses, tables, prefix?}}."""
    return _parsed(text)[0].get("$domains", {})


def within(path, held):
    held = held.rstrip("/")
    return bool(held) and (path == held or path.startswith(held + "/"))


def held_paths(entry):
    """The repo-relative paths (files or folders) a filled engine entry holds, empties dropped."""
    folder = entry["folder"]
    paths = [folder, *entry["files"], *(f"{folder}/{h}.qml" for h in entry["helpers"] if folder), *entry["itemPaths"],
             *entry["pluginPaths"], *entry["adapters"], *entry["owners"], posixpath.dirname(entry["tests"]["rows"])]
    return [p for p in paths if p]


def edit_point_rows(entry):
    """The `(kind, symbol)` rows of a filled engine entry's `editPoints`: the kinds case, rule, input,
    output, consumer and tuning in that order, then any other key in sorted order; a list value gives
    one row per item, in its order."""
    points, kinds = entry["editPoints"], ["case", "rule", "input", "output", "consumer", "tuning"]
    if not isinstance(points, dict):
        return []
    keys = [*(k for k in kinds if k in points), *sorted(k for k in points if k not in kinds)]
    return [(k, symbol) for k in keys for symbol in (points[k] if isinstance(points[k], list) else [points[k]])]


def missing_headings(doc, headings):
    """The names in `headings` that `doc` (a doc's text) lacks: heading `i` (0-based) must be the whole
    line `## {i+1} {name}`, after the line of the previous heading found (a heading out of order is
    missing)."""
    lines, at, missing = doc.split("\n"), 0, []
    for i, name in enumerate(headings):
        found = next((j for j in range(at, len(lines)) if lines[j] == f"## {i + 1} {name}"), None)
        if found is None:
            missing.append(name)
        else:
            at = found + 1
    return missing


def tests_for(paths, text=None):
    """The test names (sorted, unique) of every engine holding one of `paths`: its facade, sweep
    and golden names, and its pixel tests' names."""
    names = set()
    for entry in engines(text)[0].values():
        if any(within(p, h) for h in held_paths(entry) for p in paths):
            tests = entry["tests"]
            names.update([entry["facade"], *tests["sweep"], *tests["golden"],
                          *(posixpath.basename(p).removesuffix(".qml").removeprefix("tst_") for p in tests["pixel"])])
    names.discard("")
    return sorted(names)


def golden_file(name, text=None):
    """The golden file `tests.golden[name]` of a listed engine, or None."""
    for entry in engines(text)[0].values():
        if name in entry["tests"]["golden"]:
            return entry["tests"]["golden"][name]
    return None


def pixel_tests(text=None):
    """Every listed engine's pixel test paths, in one list."""
    return [p for e in engines(text)[0].values() for p in e["tests"]["pixel"]]


def main():
    args = sys.argv[1:]
    if args[:1] != ["--tests-for"]:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    for name in tests_for(args[1:]):
        print(name)


if __name__ == "__main__":
    main()
