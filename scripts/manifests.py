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


def _parsed(text):
    """A manifest's text -> (data, errors): the parsed object (engines, `$flat`, `$domains`) and
    every error found in it (bad JSON, an unknown or missing key, a prefix used twice)."""
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
