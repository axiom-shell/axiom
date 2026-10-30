#!/usr/bin/env python3
"""Guard the naming conventions the shell loads by.

Much of the shell has no lookup tables: a schema type or popout name *is*
a file name, loaded by URL at runtime. A typo, a rename or a missing import
only shows up when something tries to instantiate it. This checks, without
running anything:

  - every schema type (BarWidget → bar/widgets, OverlayView → views,
    OverlayModule → content) and every PopoutAnchor popoutName (→ content)
    has its type folder <root>/<Type>/<Type>.qml, and nothing is left under
    retired directories
  - every URL-loaded folder with several files is imported by name
    somewhere (qs only makes sibling types visible to URL-loaded files in
    directories it scanned)
  - every `import qs.…` names a directory that exists
  - every file starts with `pragma ComponentBehavior: Bound` (or Singleton)
  - no file instantiates a type that two of its visible directories define
  - every `SomethingManager.` names a service that exists, and nothing
    references a near-miss of a project singleton (a typo)
  - no reader falls back with `??` on its section (`_c.key ?? x`): every
    default is filled at load, so the fallback is dead and hides a missing
    schema default
  - every overlay module goes on the desktop too (`x-hosts`), and one that
    takes typing (a text field in it or its parts) says so (`x-keyboard`,
    false when it deliberately stays read-only there)
  - only the files in scripts/quickshell-io-allowlist.json use Process,
    FileView, Socket or Quickshell.execDetached directly, and
    the list only shrinks (these move to the axiom daemon)
  - no singleton is over SINGLETON_LINES lines, but the pure helpers and
    the compositor backends (split one before it grows past)
  - no Repeater model or acquire() request in the UI reads a polled
    service's member (one owning a ConsumerRegistry or DeadlineTicker),
    in the expression or through a property of the file; a model may
    count one (`.length`, `.count`)
  - no `duration:` is a number of ms (Appearance.animFast / animNormal /
    animSlow follow the animation speed), but a line marked
    `// behaviour timing: <reason>` (a blink, a pause)
  - nothing formats a date with Qt.formatDateTime / formatDate /
    formatTime (I18n.formatDate follows the language), and only General
    reads Quickshell.screens (its outputs leave out the stand-ins shown
    while no monitor is connected), but a line marked
    `// allowed: <reason>` (a file name, a window that must exist with no
    monitor)
and warns about files in the loaded directories that nothing registers or
uses. A new rule gets its breaking file in tests/scripts/test_scripts.py's
CheckStructure.

  scripts/check_structure.py        errors (exit 1) and warnings
"""
import difflib
import json
import re
import sys
from pathlib import Path

from qml_modules import qml_files

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "config" / "json" / "config.schema.json"

# (schema oneOf definition, root its types load from, file prefix): a type
# is a folder <root>/<Type>/ with <prefix><Type>.qml (docs/dev/core/config-v2.md,
# rule 11). Custom widget elements are Custom<Type>.qml, so an element
# named after a Qt type (Text, Image, List) never shadows it
LOADERS = [
    ("BarWidget", "components/bar/widgets", ""),
    ("OverlayView", "components/views", ""),
    ("OverlayModule", "components/content", ""),
    ("CustomElement", "components/content/parts/custom/elements", "Custom"),
]
# Bar popouts load content/<popoutName>/<popoutName>.qml, from the same root
# as overlay modules (a content type can be both)
POPOUT_DIR = "components/content"
# Beside the type folders, the folders of what they share (lowercase)
SHARED_FOLDERS = {"base", "parts"}
# Directories retired by restructuring: nothing may live or be imported there
RETIRED = ["components/widgets", "components/stolen"]
# Quickshell.Io's side effects, frozen to the files that use them now
IO_ALLOWLIST = ROOT / "scripts" / "quickshell-io-allowlist.json"
IO_KINDS = {
    "Process": re.compile(r"(?<![\w.])Process\s*\{"),
    "FileView": re.compile(r"(?<![\w.])FileView\s*\{"),
    "Socket": re.compile(r"(?<![\w.])Socket\s*\{"),
    "execDetached": re.compile(r"\bQuickshell\.execDetached\("),
}

# A singleton past this is doing several jobs: split it. The pure helpers
# (components/methods/, unit-tested tables of rules) and the compositor
# backends (one compositor's whole contract each) may grow past it
SINGLETON_LINES = 800
SINGLETON_EXEMPT = re.compile(r"components/methods/.*|services/compositor/(Hyprland|Sway|Niri)Manager\.qml")

errors, warnings = [], []


def rel(path):
    return path.relative_to(ROOT).as_posix()


def schema_types(schema, name):
    defs = schema["definitions"]
    types = []
    for option in defs[name]["oneOf"]:
        target = defs.get(option.get("$ref", "").split("/")[-1], option)
        const = target.get("properties", {}).get("type", {}).get("const")
        if const:
            types.append(const)
    return types


def binding(code, start):
    """A QML binding's expression from `start`: to the end of its line, or
    of the brackets it opens."""
    depth, i = 0, start
    while i < len(code):
        c = code[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if not depth:
                break
            depth -= 1
        elif c in "\n;" and not depth:
            break
        i += 1
    return code[start:i]


def main():
    schema = json.loads(SCHEMA.read_text())
    sources = {rel(f): f.read_text() for f in qml_files()}
    everything = "\n".join(sources.values())
    imports = set(re.findall(r"^import (qs(?:\.\w+)+)", everything, re.M))

    def used_as_type(name, besides):
        """Instantiated or referenced by name anywhere but its own file."""
        pattern = re.compile(r"\b" + re.escape(name) + r"\b")
        return any(pattern.search(text) for path, text in sources.items() if path != besides)

    # Schema types -> folders. A root holds only type folders (and the
    # shared ones); a folder whose files use each other is imported
    # somewhere, so qs scans it for the one loaded by URL
    for definition, directory, prefix in LOADERS:
        types = schema_types(schema, definition)
        for t in types:
            if not (ROOT / directory / t / f"{prefix}{t}.qml").exists():
                errors.append(f"{definition} type '{t}' has no {directory}/{t}/{prefix}{t}.qml")
        for f in sorted((ROOT / directory).glob("*.qml")):
            errors.append(f"{rel(f)}: a root holds only type folders: move it to {directory}/{f.stem}/ (or base/)")
        for d in sorted(p for p in (ROOT / directory).iterdir() if p.is_dir()):
            if d.name in SHARED_FOLDERS:
                continue
            if not (d / f"{prefix}{d.name}.qml").exists():
                errors.append(f"{rel(d)}/: a type folder without {prefix}{d.name}.qml")
            if directory == POPOUT_DIR:
                continue  # content: checked below, with popout names
            if d.name not in types and not used_as_type(d.name, f"{rel(d)}/{prefix}{d.name}.qml"):
                warnings.append(f"{rel(d)}/: not a {definition} type and not used anywhere")

    # qs scans a module folder only when the import graph from shell.qml
    # reaches it, never through a file loaded by URL (every type file). So
    # whatever a type file imports, and a type folder whose files use each
    # other, must be imported by a statically reached file (the hosts do,
    # with `// qmllint disable unused-imports`)
    def imports_of(text):
        return set(re.findall(r"^import (qs(?:\.\w+)+)", text, re.M))
    scanned, todo = set(), imports_of(sources["shell.qml"])
    while todo:
        module = todo.pop()
        if module in scanned:
            continue
        scanned.add(module)
        for f in (ROOT / Path(*module.split(".")[1:])).glob("*.qml"):
            todo |= imports_of(sources.get(rel(f), "")) - scanned
    unreached = {}
    for _, directory, _ in LOADERS:
        for f in sorted((ROOT / directory).rglob("*.qml")):
            own = "qs." + rel(f.parent).replace("/", ".")
            needed = imports_of(sources[rel(f)])
            if len(list(f.parent.glob("*.qml"))) > 1:
                needed.add(own)
            for module in sorted(needed - scanned):
                unreached.setdefault(module, rel(f))
    for module, path in sorted(unreached.items()):
        errors.append(f"{path} needs {module}, which no file reached from shell.qml imports: qs won't scan it (import it in the host that loads it)")

    # Processes, file views, sockets and IPC handlers are moving to the
    # axiom daemon: only the files listed in quickshell-io-allowlist.json
    # use them directly, each only the kinds listed, and the list only
    # shrinks (an entry no longer used is an error too). New code goes
    # through CommandManager, FileManager, StateManager or IpcTarget
    allowed = json.loads(IO_ALLOWLIST.read_text())["files"]
    used = {}
    for path, text in sources.items():
        if path.startswith("tests/"):
            continue
        code = re.sub(r"//[^\n]*", "", text)
        kinds = [kind for kind, pattern in IO_KINDS.items() if pattern.search(code)]
        if kinds:
            used[path] = kinds
    for path, kinds in sorted(used.items()):
        for kind in kinds:
            if kind not in allowed.get(path, []):
                errors.append(f"{path}: uses {kind} directly (only the files in {rel(IO_ALLOWLIST)} may; "
                              "go through CommandManager, FileManager, StateManager or IpcTarget, or the axiom daemon)")
    for path, kinds in sorted(allowed.items()):
        for kind in kinds:
            if kind not in used.get(path, []):
                errors.append(f"{rel(IO_ALLOWLIST)}: {path} no longer uses {kind}: remove it from the list (it only shrinks)")

    # Services live in their group's folder (services/AGENTS.md › Folders):
    # one directly in services/ would escape the singleton checks below,
    # check_docs and the API pages, which all read services/*/
    for path in sources:
        if re.fullmatch(r"services/[^/]+\.qml", path):
            errors.append(f"{path}: directly in services/ (put it in its group's folder: services/AGENTS.md › Folders)")

    # IPC targets are IpcTargets (registered with axiom, which calls them
    # over the shell's connection): an IpcHandler is out of `axiom ipc`'s
    # reach and of ipc.md
    for path, text in sources.items():
        if re.search(r"\bIpcHandler\s*\{", text):
            errors.append(f"{path}: an IpcHandler: use IpcTarget (services/core/IpcTarget.qml)")

    # An optional call on a computed member crashes V4's compiler (Qt 6.12)
    # when the file loads: a hot reload of the live shell segfaults it
    optional_call = re.compile(r"\]\s*\?\.\(")
    for path, text in sources.items():
        for n, line in enumerate(text.split("\n"), 1):
            code = line.split("//", 1)[0]
            if optional_call.search(code):
                errors.append(f"{path}:{n}: an optional call on a computed member (x[k]?.()) crashes Qt's QML compiler: take it into a const first (docs/dev/core/qml-pitfalls.md)")

    # Every library type joins one of the root's `x-libraryGroups` (the
    # editors' libraries group by them); required modules aren't offered
    library_groups = schema.get("x-libraryGroups", [])
    for definition in ("BarWidget", "OverlayModule"):
        for option in schema["definitions"][definition]["oneOf"]:
            name = option.get("$ref", "").split("/")[-1]
            target = schema["definitions"].get(name, option)
            if target.get("x-required"):
                continue
            group = target.get("x-libraryGroup")
            if group not in library_groups:
                errors.append(f"{definition} {name}: x-libraryGroup {group!r} isn't one of the schema's x-libraryGroups")

    # Modules on overlay pages go on the desktop too: `x-hosts` leaving out
    # "desktop" while listing "overlay" is how new modules once missed it.
    # One with a text field (in its file or a content part it uses) must
    # say whether the desktop hands it the keyboard: `x-keyboard`
    content_parts = {f.stem: f.read_text() for f in (ROOT / "components/content/parts").rglob("*.qml")}
    content_parts.update({f.stem: f.read_text() for f in (ROOT / POPOUT_DIR).glob("*/*.qml") if f.stem != f.parent.name})
    typing = re.compile(r"\b(?:StyledTextEntry|StyledTextArea|TextInput|TextEdit|TextArea|TextField)\s*\{|wantsKeyboardFocus:\s*true")

    def with_parts(text, seen):
        for part, body in content_parts.items():
            if part not in seen and re.search(rf"\b{part}\s*\{{", text):
                seen.add(part)
                text += with_parts(body, seen)
        return text
    for option in schema["definitions"]["OverlayModule"]["oneOf"]:
        name = option.get("$ref", "").split("/")[-1]
        target = schema["definitions"].get(name, option)
        const = target["properties"]["type"]["const"]
        hosts = target.get("x-hosts", ["overlay", "edgeMenu", "desktop"])
        if "overlay" in hosts and "desktop" not in hosts:
            errors.append(f"OverlayModule {const}: x-hosts lists overlay but not desktop (every module goes on the desktop)")
        source = ROOT / POPOUT_DIR / const / f"{const}.qml"
        if "desktop" in hosts and "x-keyboard" not in target and source.exists() and typing.search(with_parts(source.read_text(), set())):
            errors.append(f"OverlayModule {const}: has a text field but no x-keyboard (true so the desktop hands it the keyboard, false to keep it read-only there)")

    # Hand-built settings parts: x-card's `file` loads
    # views/Settings/<file>Card.qml, x-intro views/Settings/<Name>.qml (by
    # URL, so a typo only shows in the log)
    def annotated(node, found):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "x-card" and isinstance(value, dict) and value.get("file"):
                    found.append((key, value["file"]))
                elif key == "x-intro":
                    found.append((key, value))
                annotated(value, found)
        elif isinstance(node, list):
            for value in node:
                annotated(value, found)
        return found
    for key, name in annotated(schema, []):
        target = f"components/views/Settings/{name}{'Card' if key == 'x-card' else ''}.qml"
        if not (ROOT / target).exists():
            errors.append(f"schema {key} {name!r} has no {target}")

    # Tool pages (x-tool) are always in config: the Overlay.items default
    # carries every one (and a migration adds a new one to existing configs)
    default_views = {v.get("type") for v in schema["properties"]["Overlay"]["properties"]["items"]["default"]}
    for option in schema["definitions"]["OverlayView"]["oneOf"]:
        target = schema["definitions"].get(option.get("$ref", "").split("/")[-1], option)
        if target.get("x-tool"):
            const = target["properties"]["type"]["const"]
            if const not in default_views:
                errors.append(f"tool page {const} isn't in the Overlay.items default")

    # Every IPC target is in docs/usage.md's IPC table, and the table names
    # no target that's gone
    targets = {}
    for path, text in sources.items():
        for m in re.finditer(r"\bIpcTarget\s*\{", text):
            found = re.search(r'target:\s*"(\w+)"', text[m.end():m.end() + 400])
            if found:
                targets.setdefault(found.group(1), path)
    usage = (ROOT / "docs/usage.md").read_text()
    table = usage[usage.find("<summary><b>IPC targets"):]
    table = table[:table.find("</details>")]
    listed = set(re.findall(r"^\| `(\w+)`", table, re.M))
    for target, path in sorted(targets.items()):
        if target not in listed:
            errors.append(f"{path}: IPC target {target!r} is missing from the IPC table in docs/usage.md")
    for target in sorted(listed - set(targets)):
        errors.append(f"docs/usage.md: IPC target {target!r} has no IpcTarget")

    # Every file says what it's for above its root object (docs/dev/generated/files.md)
    for path, text in sources.items():
        lines = text.split("\n")
        start = next((i for i, line in enumerate(lines) if re.match(r"[A-Z][\w.]*\s*\{", line)), None)
        if start is None:
            continue
        j = start - 1
        while j >= 0 and not lines[j].strip():
            j -= 1
        if j < 0 or not (lines[j].startswith("//") or lines[j].rstrip().endswith("*/")):
            errors.append(f"{path}: no purpose comment above its root object")

    # Popout names -> content files
    names = {}
    for path, text in sources.items():
        for m in re.finditer(r'popoutName:\s*"([^"]+)"', text):
            names.setdefault(m.group(1), path)
    for name, path in sorted(names.items()):
        # A name with a slash is another file in a type's folder (Paths.contentUrl)
        file = name if "/" in name else f"{name}/{name}"
        if not (ROOT / POPOUT_DIR / f"{file}.qml").exists():
            errors.append(f'{path}: popoutName "{name}" has no {POPOUT_DIR}/{file}.qml')
    # A content type is fine if it's an overlay module type, a popout name,
    # or used by name somewhere
    module_types = set(schema_types(schema, "OverlayModule"))
    for d in sorted(p for p in (ROOT / POPOUT_DIR).iterdir() if p.is_dir() and p.name not in SHARED_FOLDERS):
        if d.name not in names and d.name not in module_types and not used_as_type(d.name, f"{rel(d)}/{d.name}.qml"):
            warnings.append(f"{rel(d)}/: not an overlay module, no PopoutAnchor opens it, and nothing uses it")

    # Retired directories stay empty
    for d in RETIRED:
        leftovers = list((ROOT / d).rglob("*.qml")) if (ROOT / d).exists() else []
        for f in leftovers:
            errors.append(f"{rel(f)}: lives under retired {d}/")

    # Every file starts with `pragma ComponentBehavior: Bound` (delegates see
    # only their required properties, and ids in nested components resolve)
    # or `pragma Singleton`
    for path, text in sources.items():
        # the first line that isn't a comment (a header, qs's //@ pragmas)
        head = next((line.strip() for line in text.split("\n") if line.strip() and not line.strip().startswith("//")), "")
        if head not in ("pragma ComponentBehavior: Bound", "pragma Singleton"):
            errors.append(f"{path}: doesn't start with pragma ComponentBehavior: Bound (or pragma Singleton)")
        lines = text.count("\n")
        if head == "pragma Singleton" and lines > SINGLETON_LINES and not SINGLETON_EXEMPT.fullmatch(path):
            errors.append(f"{path}: a singleton of {lines} lines (over {SINGLETON_LINES}): split it")

    # qs.* imports resolve
    for path, text in sources.items():
        for m in re.finditer(r"^import (qs(?:\.\w+)+)", text, re.M):
            target = ROOT.joinpath(*m.group(1).split(".")[1:])
            if not target.is_dir():
                errors.append(f"{path}: import {m.group(1)} — no such directory")

    # Only the Hyprland* services read Quickshell.Hyprland: the rest goes
    # through HyprlandManager (docs/dev/hyprland/ipc.md)
    for path, text in sources.items():
        if re.search(r"^import Quickshell\.Hyprland\b", text, re.M) and not re.fullmatch(r"services/compositor/Hyprland\w*\.qml", path):
            errors.append(f"{path}: imports Quickshell.Hyprland (only the Hyprland* services may; use CompositorManager)")

    # Likewise only a backend's own services talk to its compositor: read
    # its Quickshell module, run its CLI, use its socket or its services
    # directly (docs/dev/compositor/README.md): (prefix, the compositor,
    # its Quickshell module or None, what talks to it)
    backends = [
        ("Sway", "sway", "I3", r"\bSwayManager\.|\bSwayIpcManager\.|\"swaymsg\""),
        ("Niri", "niri", None, r"\bNiriManager\.|\"NIRI_SOCKET\"|\[\"niri\","),  # its CLI: ["niri", "msg", …]
    ]
    for prefix, name, module, talks in backends:
        for path, text in sources.items():
            # (CompositorKind names the variables that say which one runs)
            if re.fullmatch(rf"services/compositor/{prefix}\w*\.qml", path) or path in ("services/compositor/CompositorManager.qml", "components/methods/CompositorKind.qml"):
                continue
            code = "\n".join(line.split("//", 1)[0] for line in text.splitlines())
            if module and re.search(rf"^import Quickshell\.{module}\b", text, re.M):
                errors.append(f"{path}: imports Quickshell.{module} (only the {prefix}* services may; use CompositorManager)")
            if re.search(talks, code):
                errors.append(f"{path}: talks to {name} directly (only the {prefix}* services may; use CompositorManager)")

    # The rest of the shell reaches the compositor through CompositorManager
    # (docs/dev/compositor/README.md). HyprlandManager is its Hyprland
    # backend: besides the Hyprland* services, only CompositorManager uses it.
    facade = "services/compositor/CompositorManager.qml"
    for path, text in sources.items():
        code = "\n".join(line.split("//", 1)[0] for line in text.splitlines())
        if re.search(r"\bHyprlandManager\.", code) and not re.fullmatch(r"services/compositor/Hyprland\w*\.qml", path) and path != facade:
            errors.append(f"{path}: uses HyprlandManager (only the Hyprland* services and CompositorManager may; use CompositorManager)")

    # A backend's state helpers are its own (HyprState, SwayState,
    # NiriState): outside its services and helpers, the rest of the shell
    # goes through CompositorManager and CompositorConfigManager
    # (docs/dev/compositor/config-modes.md)
    for path, text in sources.items():
        code = "\n".join(line.split("//", 1)[0] for line in re.sub(r"/\*.*?\*/", "", text, flags=re.S).splitlines())
        if not path.startswith(("services/", "components/", "shell/", "config/")):
            continue
        if not re.fullmatch(r"(services/compositor|components/methods)/Hypr\w*\.qml", path) and re.search(r"\bHyprState\.", code):
            errors.append(f"{path}: uses a Hyprland helper (only the Hyprland* services and helpers may; go through CompositorManager / CompositorConfigManager)")
        for prefix, name, _, _ in backends:
            if not re.fullmatch(rf"(services/compositor|components/methods)/{prefix}\w*\.qml", path) and re.search(rf"\b{prefix}State\.", code):
                errors.append(f"{path}: uses a {name} helper (only the {prefix}* services and helpers may; go through CompositorManager / CompositorConfigManager)")

    # Singleton references: FooManager. must be a service, and a near-miss
    # of any project singleton (AudioManger.) is a typo
    external = {"ToplevelManager"}  # Quickshell's own
    singletons = {f.stem for d in ("services/*", "config", "components/methods") for f in ROOT.glob(f"{d}/*.qml")}
    services = {f.stem for f in ROOT.glob("services/*/*.qml")} | external
    for path, text in sources.items():
        # without strings and comments
        code = re.sub(r'"(?:[^"\\\n]|\\.)*"|`[^`]*`', '""', text)
        code = re.sub(r"//[^\n]*", "", code)
        for name in sorted(set(re.findall(r"(?<![\w.])([A-Z]\w+)\.", code))):
            if name in singletons or name in external:
                continue
            if name.endswith("Manager") and name not in services:
                errors.append(f"{path}: {name} is not a service")
                continue
            close = difflib.get_close_matches(name, singletons, n=1, cutoff=0.85)
            if close:
                errors.append(f"{path}: {name} — did you mean {close[0]}?")

    # Repeater models and acquire() requests never come from live values
    # (AGENTS.md › UI conventions): a model re-evaluated per sample once
    # pushed qs past 25 GB. Live means a member of a polled service (one
    # polling through a ConsumerRegistry or DeadlineTicker, not
    # BackendManager's or NotesManager's acquire()), read in the expression
    # or through one property of the same file. A model may count one
    # (`.length`, `.count`: an int notifies only when it changes); a request
    # may not read one at all
    polled = {f.stem for f in ROOT.glob("services/*/*.qml") if re.search(r"\b(?:ConsumerRegistry|DeadlineTicker)\s*\{", f.read_text())}
    chain = re.compile(r"(?<![\w.])(?:root\.)?([A-Za-z_]\w*)((?:\??\.\w+)*)")

    def live_reads(expr, props, counts, depth=0):
        found = []
        for m in chain.finditer(expr):
            name, members = m.group(1), re.findall(r"\w+", m.group(2))
            if (expr[m.end():m.end() + 1] == "(" and len(members) < 2) or (counts and members[-1:] in (["length"], ["count"])):
                continue
            if name in polled and members and members[0] not in ("acquire", "release"):
                found.append(f"{name}.{members[0]}")
            elif name in props and not depth:
                found += [f"{name} → {r}" for r in live_reads(props[name], props, counts, 1)]
        return found
    for path, text in sources.items():
        if not path.startswith(("components/", "shell/")):
            continue
        code = re.sub(r"//[^\n]*", "", re.sub(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'', '""', text))
        props = {m.group(1): binding(code, m.end()) for m in re.finditer(r"\bproperty\s+[\w<>.]+\s+(\w+)\s*:", code)}
        for m in re.finditer(r"(?<![\w.])Repeater\s*\{", code):
            model = re.search(r"(?<![\w.])model:\s*", code[m.end():m.end() + 800])
            found = model and live_reads(binding(code, m.end() + model.end()), props, True)
            if found:
                errors.append(f"{path}:{code.count(chr(10), 0, m.start()) + 1}: a Repeater model from live values ({', '.join(found)}): key it by a count (`model: rows.length`)")
        requests = [(m.start(), binding(code, m.end())) for m in re.finditer(r"\b\w+\.acquire\(", code)]
        requests += [(m.start(), props.get(m.group(1)[0].lower() + m.group(1)[1:], "")) for m in re.finditer(r"\bon(\w+)Changed:[^\n]*\bacquire\(", code)]
        for at, request in requests:
            found = live_reads(request, props, False)
            if found:
                errors.append(f"{path}:{code.count(chr(10), 0, at) + 1}: an acquire() request from live values ({', '.join(found)}): build it from config")

    # Motion follows the animation speed setting: a `duration:` is
    # Appearance.animFast / animNormal / animSlow (AGENTS.md › Config,
    # Animation). A bare number is only a behaviour timing (a blink, a
    # pause), marked on its line
    for path, text in sources.items():
        for n, line in enumerate(text.split("\n"), 1):
            if re.search(r"\bduration:\s*[1-9]\d*\s*(?:[;}]|//|$)", line) and "// behaviour timing:" not in line:
                errors.append(f"{path}:{n}: a duration in ms: use Appearance.animFast / animNormal / animSlow (or mark a blink or pause `// behaviour timing: <reason>`)")

    # Dates the user reads follow the language: I18n.formatDate(date,
    # I18n.dateFormat(name)), never Qt.formatDateTime (AGENTS.md › Translation).
    # Surfaces go on General.outputs / screensFor(target): Quickshell.screens
    # holds stand-ins while no monitor is connected, and a window left on
    # one can crash qs when they come back (General filters them). A use
    # that must stay says why on its line
    for path, text in sources.items():
        if path.startswith("tests/"):
            continue
        for n, line in enumerate(text.split("\n"), 1):
            code = line.split("//")[0]
            if "// allowed:" in line:
                continue
            if re.search(r"\bQt\.format(?:DateTime|Date|Time)\(", code):
                errors.append(f"{path}:{n}: Qt.formatDateTime: format dates through I18n.formatDate(date, I18n.dateFormat(name)) (or mark a use that must stay `// allowed: <reason>`)")
            if path != "config/General.qml" and re.search(r"\bQuickshell\.screens\b", code):
                errors.append(f"{path}:{n}: Quickshell.screens: build on General.outputs or General.screensFor(target) (or mark a window that must exist with no monitor `// allowed: <reason>`)")

    # Readers: the schema fills every default, so `_c.key ?? x` is dead
    for path, text in sources.items():
        if not path.startswith("config/"):
            continue
        for n, line in enumerate(re.sub(r"//[^\n]*", "", text).splitlines(), 1):
            m = re.search(r"\b_c(?:\.\w+)+\s*\?\?", line)
            if m:
                errors.append(f"{path}:{n}: `{m.group(0)}`: readers use no ?? fallback (the schema default is filled at load)")

    # A type instantiated from two directories a file can see would depend
    # on import order (bar widgets and content share some names by design)
    dir_types = {}
    for f in qml_files():
        if rel(f).startswith(("components/", "shell/")):
            dir_types.setdefault("qs." + rel(f.parent).replace("/", "."), set()).add(f.stem)
    for path, text in sources.items():
        own = "qs." + str(Path(path).parent).replace("/", ".")
        visible = [d for d in set(re.findall(r"^import (qs(?:\.\w+)+)", text, re.M)) | {own} if d in dir_types]
        code = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', re.sub(r"//[^\n]*", "", text))
        for name in sorted(set(re.findall(r"(?<![\w.])([A-Z]\w+)\s*\{", code)) - {Path(path).stem}):
            sources_of = [d for d in visible if name in dir_types[d]]
            if len(sources_of) > 1:
                errors.append(f"{path}: {name} is defined in {' and '.join(sorted(sources_of))}; import only one")

    for e in errors:
        print(f"error    {e}")
    for w in warnings:
        print(f"warning  {w}")
    if not errors and not warnings:
        print("structure ok")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
