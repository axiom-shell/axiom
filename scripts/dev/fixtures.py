#!/usr/bin/env python3
"""Records and checks the shared fixtures (tests/fixtures/shared/): the
cases the JS helpers and the axiom binary (Go) must agree on, byte for
byte (docs/dev/backend/README.md › Shared fixtures).

  scripts/dev/fixtures.py record     re-record the JS suites: runs tst_Config,
                                     tst_SchemaValidation, tst_SchemaLayout,
                                     tst_GreeterBundle,
                                     tst_ConfigOps and
                                     the compositor config helpers' tests
                                     (HELPERS) with
                                     recording on, and writes the calls they
                                     make as cases
  scripts/dev/fixtures.py ensure     record only when what the cases are
                                     made from changed since the last
                                     recording (scripts/generate.sh runs it)
  scripts/dev/fixtures.py golden <Name> [--allow <file>]
                                     re-record one golden (GOLDENS, or a listed
                                     engine's tests.golden) from its test.
                                     Changed, added or removed keys are written
                                     only when --allow lists them, as
                                     {"<group> <key>": {"rule": "<rule id>",
                                     "reason": "<one line>"}}; a listed key that
                                     didn't change is refused too. A golden with
                                     no file yet is written whole
  scripts/dev/fixtures.py check      the index lists exactly the cases on
                                     disk, each with its expected file, and
                                     every blob is used (CI)

The whole directory is generated and gitignored: CI records it before the
tests that replay it (both the JS and the Go side). Recording needs Qt 6's
qmltestrunner. It passes the kind ("fixture", or "golden <Name>") in
AXIOM_RECORDING, which run_tests.sh writes to tests/.recording for the run
(RepoFiles.recording reads it).

A case is <suite>/<test>/<name>.json ({op, args}) plus <name>.expected.json
(the exact bytes the JS helper produced). Arguments larger than BLOB_SIZE
are stored once under blobs/<hash>.json and referenced as {"$blob": hash};
the live schema is named by its path, {"$repoFile": "qml/config/json/…"}.
The expected bytes come from the JS engine the shell runs (V4, through
qmltestrunner) and are written untouched; arguments only need to parse to
the same values, so they are re-serialized here.

The format-1 migration's cases aren't here: they were frozen into the
binary's own testdata (backend/internal/migrate/legacy/testdata/) when the
shell's copy of the migrations was removed.
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import manifests  # noqa: E402

SHARED = ROOT / "tests/fixtures/shared"
# Goldens of no listed engine; a listed engine's goldens are its manifest
# tests.golden (manifests.golden_file); a golden has one home at a time
GOLDENS = {"BarStyleMatrix": "tests/barstyle/Matrix.js"}
# Suites recorded from the JS helpers (the rest are written by Go's tests)
# ConfigOps (config.set's ops, which the daemon's tests decode), InputSources
# (the xkb list the renderer derives too) and the bind and layer helpers the
# binary also ports, still used by the shell
# (backend/internal/compositor/render; the rest's cases are frozen there)
# Each helper's folder under qml/components/methods/ ("" is the root)
HELPERS = {"BindActions": "", "BindConditions": "", "BindKeys": "", "ConfigOps": "", "InputSources": "",
           "KeyNames": "", "LayerStack": "layer"}
RECORD_TESTS = ("Config", "SchemaValidation", "SchemaLayout", "GreeterBundle") + tuple(HELPERS)
BLOB_SIZE = 2048
# What the recorded cases are made from: a change to any re-records them
STAMP_INPUTS = ("qml/components/methods/SchemaValidation.qml", "tests/Shared.qml", "tests/RepoFiles.qml",
                "tests/tst_Config.qml", "tests/tst_SchemaValidation.qml",
                "qml/components/methods/SchemaLayout.qml", "tests/tst_SchemaLayout.qml",
                "qml/components/methods/GreeterBundle.qml", "tests/tst_GreeterBundle.qml",
                "qml/config/json/config.schema.json", "scripts/dev/fixtures.py",
                *(Path("qml/components/methods", folder, f"{h}.qml").as_posix() for h, folder in HELPERS.items()),
                *(f"tests/tst_{h}.qml" for h in HELPERS),
                "qml/components/methods/MonitorLayout.qml", "qml/components/methods/polkit/PolkitAgents.qml",
                "qml/components/methods/SwayState.qml", "qml/components/methods/NiriState.qml",
                "backend/internal/compositor/actions/table.json",
                "scripts/qml_modules.py", "scripts/run_tests.sh")


def main(argv):
    if len(argv) in (3, 5) and argv[1] == "golden" and (len(argv) == 3 or argv[3] == "--allow"):
        return golden(argv[2], argv[4] if len(argv) == 5 else None)
    if len(argv) != 2 or argv[1] not in ("record", "ensure", "check"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    if argv[1] == "ensure":
        if (SHARED / ".stamp").exists() and (SHARED / ".stamp").read_text() == stamp():
            return 0
        return record()
    return record() if argv[1] == "record" else check()


def stamp():
    """A hash of everything the cases are made from."""
    h = hashlib.sha256()
    for pattern in STAMP_INPUTS:
        for path in sorted(ROOT.glob(pattern)):
            h.update(path.relative_to(ROOT).as_posix().encode() + b"\0" + path.read_bytes() + b"\0")
    return h.hexdigest() + "\n"


# --- record ---

def record():
    SHARED.mkdir(parents=True, exist_ok=True)
    (SHARED / ".stamp").unlink(missing_ok=True)
    # What an earlier recording left that no suite writes any more
    for stale in ("legacy", "share", "corpus", "schemas", ".corpus"):
        shutil.rmtree(SHARED / stale, ignore_errors=True)
    out = run_tests(RECORD_TESTS, "FIXTURE", "fixture")

    records = [decode(line) for line in out.splitlines() if "@@FIXTURE " in line]
    if not records:
        print("no calls were recorded (did the tests run?)", file=sys.stderr)
        return 1
    # Every suite goes, so one no longer recorded (a helper removed) leaves
    # no cases behind
    for suite in SHARED.iterdir():
        if suite.is_dir() and suite.name != "blobs":
            shutil.rmtree(suite)
    blobs = SHARED / "blobs"
    shutil.rmtree(blobs, ignore_errors=True)
    blobs.mkdir()

    seen = {}  # (suite, case text) → name, so a repeated call is one case
    counters = {}
    written = 0
    for rec in records:
        spec = json.loads(rec["case"])
        spec["args"] = [store_blobs(arg, blobs) for arg in spec["args"]]
        case_text = dump(spec)
        key = (rec["suite"], case_text)
        if key in seen:
            continue
        name = case_name(rec, counters)
        seen[key] = name
        path = SHARED / rec["suite"] / name
        path.parent.mkdir(parents=True, exist_ok=True)
        (path.parent / (path.name + ".json")).write_text(case_text, encoding="utf-8")
        # The JS text exactly; a lone surrogate (which V4 writes unescaped)
        # can't be stored, so such a case must not be a JS-owned golden
        (path.parent / (path.name + ".expected.json")).write_bytes(rec["expected"].encode("utf-8"))
        written += 1
    write_index()
    (SHARED / ".stamp").write_text(stamp())
    print(f"recorded {written} cases ({len(records)} calls) into {SHARED.relative_to(ROOT)}")
    return 0


def run_tests(names, tag, kind):
    """Runs the named tests, failing if any of them fails; @@<tag> lines stay out of the failure print; kind is the recording marker's content."""
    proc = subprocess.run([str(ROOT / "scripts/run_tests.sh"), *names],
                          cwd=ROOT, env={**os.environ, "AXIOM_RECORDING": kind}, capture_output=True, text=True, errors="surrogateescape")
    output = proc.stdout + proc.stderr
    if proc.returncode != 0:
        print("\n".join(l for l in output.splitlines() if f"@@{tag}" not in l)[-4000:], file=sys.stderr)
        raise SystemExit("the recording tests failed; nothing was written")
    return output


def decode(line):
    """A @@FIXTURE line's payload: hex UTF-16 code units → the JSON object."""
    hexed = line.split("@@FIXTURE ", 1)[1].strip()
    units = bytes.fromhex(hexed)
    # big-endian units, 4 hex digits each
    text = units.decode("utf-16-be", errors="surrogatepass")
    rec = json.loads(text)
    for field in ("case", "expected"):
        try:
            rec[field].encode("utf-8")
        except UnicodeEncodeError:
            raise SystemExit(f"{rec['test']}.{rec['function']}: a lone surrogate can't be a JS golden")
    return rec


def case_name(rec, counters):
    """<test>/<function or label>[.<tag>].<n>, n counting from 0."""
    base = rec["label"] or rec["function"] or "case"
    if rec["tag"]:
        base += "." + rec["tag"]
    base = rec["test"] + "/" + re.sub(r"[^A-Za-z0-9_.\-/]+", "_", base)
    n = counters.get((rec["suite"], base), 0)
    counters[(rec["suite"], base)] = n + 1
    return f"{base}.{n}"


def store_blobs(value, blobs):
    """value with every object/array larger than BLOB_SIZE stored as a blob."""
    if isinstance(value, dict) and list(value) == ["$repoFile"]:
        return value
    if isinstance(value, (dict, list)):
        if isinstance(value, dict):
            value = {k: store_blobs(v, blobs) for k, v in value.items()}
        else:
            value = [store_blobs(v, blobs) for v in value]
        compact = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        if len(compact) > BLOB_SIZE:
            digest = hashlib.sha256(compact.encode("utf-8")).hexdigest()[:20]
            path = blobs / f"{digest}.json"
            if not path.exists():
                path.write_text(dump(value), encoding="utf-8")
            return {"$blob": digest}
    return value


def dump(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


# --- golden ---

def golden(name, allow):
    """Records one golden from its test; the exit code."""
    in_manifest, in_goldens = manifests.golden_file(name), GOLDENS.get(name)
    if in_manifest and in_goldens:
        print(f"{name} is in GOLDENS and in scripts/engines.json's tests.golden; keep one", file=sys.stderr)
        return 2
    rel = in_manifest or in_goldens
    if not rel:
        print(f"no golden named {name} (GOLDENS: {', '.join(GOLDENS)})", file=sys.stderr)
        return 2
    try:
        allowed = read_allow(allow) if allow else {}
    except (OSError, ValueError) as err:
        print(f"{allow}: {err}", file=sys.stderr)
        return 2
    path = ROOT / rel
    old = None
    if path.exists():
        try:
            old = golden_data(path.read_text(encoding="utf-8"))
        except ValueError:
            print(f"can't read {rel}'s data", file=sys.stderr)
            return 1
    out = run_tests([name], "MATRIX", f"golden {name}")

    data = {}
    for line in out.splitlines():
        if "@@MATRIX " not in line:
            continue
        group, key, value = decode_matrix(line)
        if key in data.get(group, {}):
            print(f"{group} {key}: recorded twice", file=sys.stderr)
            return 1
        data.setdefault(group, {})[key] = value
    if not data:
        print("no cases were recorded (did the test run?)", file=sys.stderr)
        return 1

    flat = {f"{g} {k}": v for g, keys in data.items() for k, v in keys.items()}
    if old is None:
        problems = [f"{key}: in --allow but unchanged" for key in sorted(allowed)]
        counts = f"{len(flat)} keys"
    else:
        was = {f"{g} {k}": v for g, keys in old.items() for k, v in keys.items()}
        changed = {key for key in flat if key in was and flat[key] != was[key]}
        added, removed = set(flat) - set(was), set(was) - set(flat)
        diff = {**{k: "changed" for k in changed}, **{k: "added" for k in added}, **{k: "removed" for k in removed}}
        problems = [f"{key}: {how}, not in --allow" for key, how in sorted(diff.items()) if key not in allowed]
        problems += [f"{key}: in --allow but unchanged" for key in sorted(set(allowed) - set(diff))]
        counts = (f"{len(changed)} changed, {len(added)} added, {len(removed)} removed" if diff else "data unchanged")
    if problems:
        print("\n".join(problems) + "\nnothing written", file=sys.stderr)
        return 1
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(golden_text(name, data), encoding="utf-8")
    print(f"{rel}: {'written (' + counts + ')' if old is None else counts}")
    return 0


def decode_matrix(line):
    """A @@MATRIX line's (group, key, value): `<group> <key>\t<value>` after the tag."""
    head, value = line.split("@@MATRIX ", 1)[1].rstrip("\r\n").split("\t", 1)
    group, key = head.split(" ", 1)
    return group, key, value


def golden_data(text):
    """A golden file's data section (`var expected = …;`) parsed; ValueError if it has none or isn't groups of keys."""
    head, found, body = text.partition("var expected = ")
    if not found:
        raise ValueError("no data section")
    data = json.loads(body.rstrip().removesuffix(";"))
    if not (isinstance(data, dict) and all(isinstance(keys, dict) for keys in data.values())):
        raise ValueError("data section isn't groups of keys")
    return data


def golden_text(name, data):
    """The whole golden file: header and the data section, groups and keys sorted."""
    ordered = {g: dict(sorted(data[g].items())) for g in sorted(data)}
    return (".pragma library\n"
            f"// Generated by scripts/dev/fixtures.py golden {name} from tests/tst_{name}.qml; never edited by hand.\n"
            "var expected = " + dump(ordered).rstrip("\n") + ";\n")


def read_allow(path):
    """The --allow file: {"<group> <key>": {"rule": …, "reason": …}}; ValueError if it isn't."""
    allowed = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(allowed, dict):
        raise ValueError("not a JSON object")
    for key, why in allowed.items():
        if not (isinstance(why, dict) and all(isinstance(why.get(f), str) and why[f] for f in ("rule", "reason"))):
            raise ValueError(f"{key}: needs a non-empty rule and reason")
    return allowed


# --- index and check ---

def cases_on_disk():
    names = []
    for path in SHARED.rglob("*.json"):
        rel = path.relative_to(SHARED).as_posix()
        if rel.startswith(("blobs/", ".")) or rel == "index.json" or rel.endswith(".expected.json"):
            continue
        names.append(rel[:-len(".json")])
    return sorted(names)


def write_index():
    (SHARED / "index.json").write_text(dump({
        "_comment": "Every shared case, written by scripts/dev/fixtures.py (and by the axiom binary's tests for the suites Go owns). See docs/dev/backend/README.md.",
        "cases": cases_on_disk(),
    }), encoding="utf-8")


def check():
    if not (SHARED / "index.json").exists():
        print(f"{SHARED.relative_to(ROOT)} isn't recorded: scripts/generate.sh --fixtures (or scripts/dev/fixtures.py record)")
        return 1
    problems = []
    index = json.loads((SHARED / "index.json").read_text())
    listed, found = index["cases"], cases_on_disk()
    for name in sorted(set(found) - set(listed)):
        problems.append(f"{name}: not in index.json")
    for name in sorted(set(listed) - set(found)):
        problems.append(f"{name}: in index.json but missing")
    used = set()
    for name in found:
        if not (SHARED / (name + ".expected.json")).exists():
            problems.append(f"{name}: no .expected.json")
        text = (SHARED / (name + ".json")).read_text(encoding="utf-8")
        used.update(re.findall(r'"\$blob": "([0-9a-f]+)"', text))
    blob_dir = SHARED / "blobs"
    blob_names = {p.stem for p in blob_dir.glob("*.json")} if blob_dir.exists() else set()
    for blob in sorted(blob_names):
        nested = (blob_dir / f"{blob}.json").read_text(encoding="utf-8")
        used.update(re.findall(r'"\$blob": "([0-9a-f]+)"', nested))
    for blob in sorted(blob_names - used):
        problems.append(f"blobs/{blob}.json: unused")
    for blob in sorted(used - blob_names):
        problems.append(f"blobs/{blob}.json: missing")
    for p in problems:
        print(p)
    if problems:
        print(f"{len(problems)} problems in {SHARED.relative_to(ROOT)} (scripts/dev/fixtures.py record rewrites the JS suites)")
        return 1
    print(f"{len(found)} shared cases ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
