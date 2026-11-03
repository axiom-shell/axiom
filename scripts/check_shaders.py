#!/usr/bin/env python3
"""Check (or build) the compiled wallpaper shaders.

Qt 6 loads a ShaderEffect's shader only precompiled (.qsb), and axiom has
no build step, so each shader in qml/components/surfaces/wallpaper/shaders/
is committed twice: its source (`<name>.frag`, the shared `common.glsl`
prepended at build) and `<name>.frag.qsb`. `stamps.txt` there holds the
hash of the source each .qsb was built from; this fails when a source
changed since (or has no .qsb, or a .qsb has no source), without needing
qsb itself.

Prints `error    <file>: <message>` per problem, as check_structure does.

  scripts/check_shaders.py           check
  scripts/check_shaders.py --build   rebuild the stale ones (needs qsb, from
                                     qt6-shadertools)
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHADERS = ROOT / "qml/components/surfaces/wallpaper/shaders"
COMMON = SHADERS / "common.glsl"
STAMPS = SHADERS / "stamps.txt"
# The shading languages Qt Quick asks for (OpenGL (ES), Vulkan, Direct3D,
# Metal), in a pack Qt 6.4 and later reads
QSB_ARGS = ["--qt6", "--qsbversion", "64"]


def source(frag):
    return COMMON.read_text() + "\n#line 1\n" + frag.read_text()


def digest(frag):
    """The source's hash, with the arguments it's built with."""
    return hashlib.sha256((" ".join(QSB_ARGS) + "\n" + source(frag)).encode()).hexdigest()


def read_stamps():
    stamps = {}
    if STAMPS.exists():
        for line in STAMPS.read_text().splitlines():
            if line.strip() and not line.startswith("#"):
                hash_, name = line.split(None, 1)
                stamps[name.strip()] = hash_
    return stamps


def write_stamps(stamps):
    lines = ["# The source hash each .qsb was built from (scripts/check_shaders.py --build)"]
    lines += [f"{stamps[name]}  {name}" for name in sorted(stamps)]
    tmp = STAMPS.with_suffix(".tmp")
    tmp.write_text("\n".join(lines) + "\n")
    tmp.replace(STAMPS)


def qsb_tool():
    for candidate in (shutil.which("qsb6"), shutil.which("qsb"), "/usr/lib/qt6/bin/qsb"):
        if candidate and os.access(candidate, os.X_OK):
            return candidate
    return None


def main():
    build = "--build" in sys.argv[1:]
    frags = sorted(SHADERS.glob("*.frag"))
    stamps = read_stamps()
    stale = [f for f in frags if stamps.get(f.name) != digest(f) or not f.with_name(f.name + ".qsb").exists()]
    errors = []
    if build and stale:
        qsb = qsb_tool()
        if not qsb:
            print("error    qsb not found: install qt6-shadertools", file=sys.stderr)
            return 1
        with tempfile.TemporaryDirectory() as tmp:
            for frag in stale:
                full = Path(tmp) / frag.name
                full.write_text(source(frag))
                out = frag.with_name(frag.name + ".qsb")
                result = subprocess.run([qsb, *QSB_ARGS, "-o", str(out), str(full)], capture_output=True, text=True)
                if result.returncode != 0:
                    errors.append(f"error    {frag.relative_to(ROOT)}: qsb failed\n{result.stderr.strip()}")
                    continue
                stamps[frag.name] = digest(frag)
                print(f"built {out.relative_to(ROOT)}")
        stamps = {name: h for name, h in stamps.items() if (SHADERS / name).exists()}
        write_stamps(stamps)
        stale = [f for f in frags if stamps.get(f.name) != digest(f)]
    for frag in stale:
        if not frag.with_name(frag.name + ".qsb").exists():
            errors.append(f"error    {frag.relative_to(ROOT)}: no {frag.name}.qsb (run scripts/check_shaders.py --build)")
        else:
            errors.append(f"error    {frag.relative_to(ROOT)}: changed since its .qsb was built (run scripts/check_shaders.py --build)")
    for qsb in sorted(SHADERS.glob("*.qsb")):
        if not qsb.with_suffix("").exists():
            errors.append(f"error    {qsb.relative_to(ROOT)}: no source {qsb.with_suffix('').name}")
    for name in sorted(set(stamps) - {f.name for f in frags}):
        errors.append(f"error    {STAMPS.relative_to(ROOT)}: a stamp for {name}, which doesn't exist")
    for line in errors:
        print(line)
    if errors:
        return 1
    print("shaders ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
