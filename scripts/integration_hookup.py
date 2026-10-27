#!/usr/bin/env python3
"""Hooks a theme integration's axiom file into the app's own config.

Usage: integration_hookup.py status|apply KEY [--schema PATH | --targets JSON]

The targets are the `x-hookup` list of ThemeIntegrations.KEY in the config
schema, or the JSON list `--targets` gives (KEY then only names them: the
Hyprland page's lines that load axiom or start it). Each is one of:
  {file, text, place, ...}  something apply can do
  {text, where}             copy only: the settings page shows it to copy
  {file, from, place: "copy"}  a file to copy into place when missing

`file` (a path, or a list whose first existing entry is used) and `text`
may hold {config} ($XDG_CONFIG_HOME), {state} ($XDG_STATE_HOME) and {home}.
Places:
  end      append the text (later settings win)
  start    insert it first (CSS: @import must come first)
  top      before the first [section] header (TOML top-level keys, INI main)
  section  inside [section], which is added at the end when missing
  shellrc  the rc file of $SHELL (fish: conf.d/axiom.fish, as `set -gx`)
  copy     copy `from` (relative to scripts/) to `file` if that's missing
`accept` is a regex: a line matching it anywhere (not commented out) means
the target is already done, however it's spelled. `replace` (top/section/shellrc) is what happens to a line already setting a
key the text sets: "comment" (the default: commented out), "keep" (left
beside it) or "conflict" (nothing is done: copy only). `requires` names a
command without which the target is skipped; `comment` is the comment
prefix (default "#").

`wrapLink` is for a file that is a link to one the user can't write (a
theme's gtk.css under /usr/share/themes, a /nix/store file): Apply then
replaces the link with a file holding `wrapLink` ({link} = the file it
pointed at) and the text, and keeps the link as the backup. Without it,
such a target is skipped ("readonly"): nothing outside the user's own
files is ever written.

`note` replaces the settings page's line about where the text goes, and
`title` names the target above its path (two targets in one file).

`perProfile` makes a target one per browser profile: `file` is then
relative to each profile directory listed by the profiles.ini files in the
integration's `x-profiles` (Firefox and its forks), and with none found the
target is skipped ("profiles").

apply backs up each file it changes beside the real file (a symlink is
followed and kept) as <name>.axiom-bak-<time>, then writes it atomically.
A file it can't write (or whose directory it can't) is never touched.
Nothing is deleted: replaced lines are commented out. Prints JSON.
"""
import configparser
import json
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
# The schema axiom built for the running shell (axiom run sets it), else
# the tree's own build (scripts/generate.sh)
SCHEMA = Path(os.environ.get("AXIOM_SCHEMA") or SCRIPTS.parent / "config" / "json" / "config.schema.json")
HEADER = re.compile(r"^\s*\[")
NAMED_HEADER = re.compile(r"^\s*\[\s*([^\[\]\"]+?)\s*\]\s*(?:[#;].*)?$")
EXPORT = re.compile(r'^export\s+([A-Za-z_][A-Za-z0-9_]*)=(.*)$')


def dirs():
    home = os.environ.get("HOME") or str(Path.home())
    return {
        "home": home,
        "config": os.environ.get("XDG_CONFIG_HOME") or home + "/.config",
        "state": os.environ.get("XDG_STATE_HOME") or home + "/.local/state",
    }


def fill(text, d):
    return text.replace("{config}", d["config"]).replace("{state}", d["state"]).replace("{home}", d["home"])


def shown(path, d):
    """A path with $HOME as ~"""
    path = str(path)
    home = d["home"].rstrip("/")
    return "~" + path[len(home):] if path == home or path.startswith(home + "/") else path


def key_of(line, place):
    """The key a config line sets, or None"""
    line = line.strip()
    if place == "shellrc":
        m = EXPORT.match(line)
        return m.group(1) if m else None
    if not line or line[0] in "#;[" or "=" not in line:
        return None
    return line.split("=", 1)[0].strip() or None


def is_comment(line, comment):
    stripped = line.lstrip()
    return stripped.startswith(comment) or stripped.startswith("#") or stripped.startswith(";")


def fish_line(line):
    m = EXPORT.match(line.strip())
    if not m:
        return line
    value = m.group(2)
    return f"set -gx {m.group(1)} {value}"


def which(cmd):
    return shutil.which(cmd) is not None


def writable(path):
    """Whether apply could write `path` atomically and back it up: the file
    and its directory (the nearest existing one when it's missing)"""
    if os.path.lexists(path):
        return os.access(path, os.W_OK) and os.access(os.path.dirname(path), os.W_OK)
    parent = os.path.dirname(path)
    while parent and not os.path.isdir(parent):
        parent = os.path.dirname(parent)
    return bool(parent) and os.access(parent, os.W_OK)


def resolve_target(target, d):
    """Fills in the file, text and lines a target works with"""
    t = dict(target)
    place = t.get("place", "")
    t["text"] = fill(t.get("text", ""), d)
    if place == "shellrc":
        shell = os.path.basename(os.environ.get("SHELL", ""))
        if shell == "zsh":
            t["file"] = (os.environ.get("ZDOTDIR") or d["home"]) + "/.zshrc"
        elif shell == "bash":
            t["file"] = d["home"] + "/.bashrc"
        elif shell == "fish":
            t["file"] = d["config"] + "/fish/conf.d/axiom.fish"
            t["text"] = "\n".join(fish_line(line) for line in t["text"].splitlines())
            t["shell"] = "fish"
        else:
            t["file"] = None
            t["skipped"] = "shell"
        t.setdefault("shell", shell)
    elif "file" in t:
        files = t["file"] if isinstance(t["file"], list) else [t["file"]]
        files = [fill(f, d) for f in files]
        t["file"] = next((f for f in files if os.path.lexists(f)), files[0])
    return t


def scope(lines, place, section):
    """[start, end) of the lines a target's keys live in, or None for a
    section that isn't there"""
    if place == "top":
        end = next((i for i, line in enumerate(lines) if HEADER.match(line)), len(lines))
        return 0, end
    if place == "section":
        for i, line in enumerate(lines):
            m = NAMED_HEADER.match(line)
            if m and m.group(1) == section:
                end = next((j for j in range(i + 1, len(lines)) if HEADER.match(lines[j])), len(lines))
                return i + 1, end
        return None
    return 0, len(lines)


def profile_dirs(inis, d):
    """Every profile directory the profiles.ini files list, in order, once"""
    found = []
    for ini in inis:
        path = Path(fill(ini, d))
        if not path.is_file():
            continue
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            parser.read(path)
        except configparser.Error:
            continue
        for name in parser.sections():
            section = parser[name]
            if not name.startswith("Profile") or "Path" not in section:
                continue
            relative = section.get("IsRelative", "1") == "1"
            profile = path.parent / section["Path"] if relative else Path(section["Path"])
            if profile.is_dir() and str(profile) not in found:
                found.append(str(profile))
    return found


def expand(targets, profiles, d):
    """The targets, each perProfile one repeated for every profile"""
    out = []
    for target in targets:
        if not target.get("perProfile"):
            out.append(target)
            continue
        dirs_ = profile_dirs(profiles, d)
        if not dirs_:
            out.append({k: v for k, v in target.items() if k != "file"} | {"skipped": "profiles"})
        for profile in dirs_:
            out.append(dict(target, file=os.path.join(profile, target["file"])))
    return out


def plan(t):
    """What applying a resolved target would do, and whether it's done"""
    place = t.get("place", "")
    comment = t.get("comment", "#")
    path = t.get("file")
    out = {"text": t["text"], "place": place, "skipped": t.get("skipped", ""), "where": t.get("where", ""),
           "note": t.get("note", ""), "title": t.get("title", ""), "copyOnly": not path and not t.get("skipped"),
           "exists": False, "link": False, "done": False, "replaces": [], "alongside": [], "conflicts": [],
           "createsSection": False, "wraps": False, "shell": t.get("shell", ""),
           "section": t.get("section", ""), "requires": t.get("requires", "")}
    if not path or out["skipped"]:
        return out, None
    if t.get("requires") and not which(t["requires"]):
        out["skipped"] = "requires"
        return out, None
    real = os.path.realpath(path)
    out.update({"exists": os.path.isfile(real), "link": os.path.islink(path) or real != os.path.abspath(path),
                "path": path, "resolved": real})
    if place == "copy":
        out["done"] = out["exists"]
        if not out["done"] and not writable(real):
            out["skipped"] = "readonly"
        return out, None
    lines = Path(real).read_text().splitlines() if out["exists"] else []
    if not writable(real):
        # A link to a file the user doesn't own: replaced by a file loading
        # it when the target says how, else left alone
        if os.path.islink(path) and t.get("wrapLink") and os.access(os.path.dirname(os.path.abspath(path)), os.W_OK):
            out["wraps"] = True
        else:
            out["skipped"] = "readonly"
    want = [line for line in t["text"].splitlines() if line.strip()]
    span = scope(lines, place, t.get("section"))
    if place == "section" and span is None:
        out["createsSection"] = True
        span = (len(lines), len(lines))
    start, end = span
    region = [line.strip() for line in lines[start:end]]
    missing = [line for line in want if line.strip() not in region]
    # An equivalent line anywhere (another spelling of the path, a key set
    # elsewhere) counts as hooked up too
    accept = re.compile(t["accept"]) if t.get("accept") else None
    if accept and any(accept.search(line.strip()) for line in lines if not is_comment(line, comment)):
        missing = []
    out["done"] = out["exists"] and not missing
    if out["done"]:
        out["skipped"] = ""
        out["wraps"] = False
    elif out["skipped"]:
        return out, None
    if place in ("top", "section", "shellrc") and missing:
        keys = {key_of(line, place) for line in missing} - {None}
        if t.get("shell") == "fish":
            keys = set()
        same = [line for line in lines[start:end]
                if not is_comment(line, comment) and key_of(line, place) in keys]
        how = t.get("replace", "comment")
        bucket = {"comment": "replaces", "keep": "alongside", "conflict": "conflicts"}[how]
        out[bucket] = [line.strip() for line in same]
    return out, (lines, missing, span)


def status(targets, d):
    return [plan(resolve_target(t, d))[0] for t in targets]


def write_atomic(path, text, mode):
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + ".", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def apply_one(t, d, stamp):
    out, work = plan(t)
    result = {"path": shown(out.get("path", ""), d), "changed": False, "backup": "", "error": ""}
    if out["copyOnly"] or out["skipped"] or out["done"]:
        return result
    if out["conflicts"]:
        result["error"] = "conflict"
        return result
    real = out["resolved"]
    os.makedirs(os.path.dirname(real), exist_ok=True)
    if t.get("place") == "copy":
        shutil.copyfile(SCRIPTS / t["from"], real)
        result["changed"] = True
        return result
    lines, missing, (start, end) = work
    if out["wraps"]:
        # The link becomes the backup (still pointing where it did), and a
        # file of the user's takes its place
        path = out["path"]
        backup = f"{path}.axiom-bak-{stamp}"
        os.symlink(os.readlink(path), backup)
        result["backup"] = shown(backup, d)
        text = [t["wrapLink"].replace("{link}", real)] + missing
        write_atomic(path, "\n".join(text) + "\n", 0o644)
        result["changed"] = True
        return result
    comment = t.get("comment", "#")
    place = t.get("place", "")
    if place in ("top", "section", "shellrc") and t.get("replace", "comment") == "comment" and t.get("shell") != "fish":
        keys = {key_of(line, place) for line in missing} - {None}
        for i in range(start, end):
            if not is_comment(lines[i], comment) and key_of(lines[i], place) in keys:
                lines[i] = f"{comment} axiom: {lines[i]}"
    if place == "start":
        lines[0:0] = missing
    elif place == "top":
        # After any blank lines ending the top-level block, so it reads as
        # part of it, not of the section below
        at = end
        while at > start and not lines[at - 1].strip():
            at -= 1
        lines[at:at] = missing
    elif place == "section":
        if out["createsSection"]:
            if lines and lines[-1].strip():
                lines.append("")
            lines += [f"[{t['section']}]"] + missing
        else:
            at = end
            while at > start and not lines[at - 1].strip():
                at -= 1
            lines[at:at] = missing
    else:  # end, shellrc
        if lines and lines[-1].strip():
            lines.append("")
        lines += missing
    mode = 0o644
    if out["exists"]:
        mode = os.stat(real).st_mode & 0o777
        backup = f"{real}.axiom-bak-{stamp}"
        shutil.copy2(real, backup)
        result["backup"] = shown(backup, d)
    write_atomic(real, "\n".join(lines) + "\n", mode)
    result["changed"] = True
    return result


def apply(targets, d):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    results = []
    for target in targets:
        try:
            results.append(apply_one(resolve_target(target, d), d, stamp))
        except OSError as e:
            results.append({"path": "", "changed": False, "backup": "", "error": str(e)})
    return results


def main(argv):
    args = argv[1:]
    schema = SCHEMA
    given = None
    for flag in ("--schema", "--targets"):
        if flag in args:
            i = args.index(flag)
            if flag == "--schema":
                schema = Path(args[i + 1])
            else:
                given = json.loads(args[i + 1])
            del args[i:i + 2]
    if len(args) != 2 or args[0] not in ("status", "apply"):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    action, key = args
    d = dirs()
    if given is not None:
        targets = given
    else:
        props = json.loads(schema.read_text())["properties"]["ThemeIntegrations"]["properties"]
        if key not in props:
            print(f"Error: no integration '{key}'", file=sys.stderr)
            return 2
        targets = expand(props[key].get("x-hookup", []), props[key].get("x-profiles", []), d)
    if action == "status":
        rows = status(targets, d)
        for row in rows:
            for k in ("path", "resolved"):
                if k in row:
                    row[k] = shown(row[k], d)
        print(json.dumps({"key": key, "targets": rows}))
    else:
        print(json.dumps({"key": key, "results": apply(targets, d)}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
