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
  - every overlay module with a text field says whether the desktop hands it
    the keyboard (`x-keyboard`, false when it deliberately stays read-only)
  - a module on the lock screen (or a part it uses) calls only reads and
    the service methods its `x-lockActions` cover, but a call marked
    `// lock-inert: <reason>`
  - the deleted chrome-drawing constructs stay deleted: no HoledItem or
    shadowHoles in qml/; HoledCopy, OutsideShadow and Appearance.translucent
    only in the files scripts/chrome-drawing-allowlist.json lists for each
    (an entry no longer used is an error); every BlurShape's `shown:` reads
    `backed`
  - no Repeater model or acquire() request in the UI reads a polled
    service's member (one owning an OwnerRegistry or DeadlineTicker), or,
    for a model, a push service's array rebuilt per push, in the
    expression or through a property of the file; a model may count one
    (`.length`, `.count`)
  - the config UI and onboarding build no hover tint (StateLayer), key
    handler, sunken box, `onRowClicked`, `first:` literal or kept pushed
    `text`, and no SegmentButton outside a SegmentRow, SegmentTabs or
    StyledToggle (views, content, surfaces), unless the file is listed in
    scripts/ui-local-exceptions.json with a reason (special drawing); the list
    only shrinks
  - nothing formats a date with Qt.formatDateTime / formatDate /
    formatTime (I18n.formatDate follows the language), but a line marked
    `// allowed: <reason>` (a file name)
  - no property is named on<X> beside a property, signal or function <x>
    (its file's, or a Qt type's it inherits: width, a window's screen, …): Qt never
    gives it its value
  - every bar widget is data on BarWidget: the WIDGET_RULES of
    bar_widget_template, its exceptions in scripts/bar-widget-exceptions.json
  - a bar widget's `popoutModule` (x-popoutModule) is a popoutName it
    opens, and one whose popoutName is an overlay module declares it; its
    anchors hand its values by `fromWidget` (the keys popoutModule lists),
    never `extraData`, and a widget without popoutModule has no `fromWidget`
  - every `axiom-<x>` window namespace in qml/ (and every
    BarsConfig.layerNamespace value) has one LayerStack.layers row, which
    names its layer, and no namespace has two (layer-namespace-row); a
    window binds its layer to its LayerSlot's and its namespace to its own
    `layerNamespace`, only the layer service reads the compositor's layer
    facts and WlrLayer, and no `backsOn(` takes a literal layer
    (layer-slot-binding)
  - no UI switches one of the shell's actions through its service's own
    toggle or setter (Wi-Fi, Bluetooth, caffeine, do not disturb, night
    light, dark mode, the mutes, the VPN, a recording, a session action,
    a screenshot, clearing notifications, the pomodoro, the stopwatch and
    timer, the media transport, the input source, identifying monitors) or
    ShellManager.runAction:
    it runs it through ActionsManager.run, as every other place that
    offers it
and warns about files in the loaded directories that nothing registers or
uses. A new rule gets its breaking file in tests/scripts/test_scripts.py's
CheckStructure.

The Quickshell boundary (quickshell-use): Quickshell APIs are for Wayland
(windows, screens, layers, focus, the session lock, capture, blur) and for
running the QML, in the files scripts/quickshell-exceptions.json lists, each
with its reason; four types (ShellScreen, ClippingRectangle, SystemClock,
ScriptModel) are allowed anywhere. Every use id of QUICKSHELL_USES is in one
of three sets: Wayland and toolkit uses a `files` entry can grant, and
daemon-set uses (system data, compositor IPC, files, processes) no file can
be granted. It fails on: (1) a use no entry grants and the baseline doesn't
list; (2) a `files` grant the file no longer uses; (3) an import of a module
the list's `never` bans; (4) `import Quickshell` with no use, or a
`Quickshell.<member>` it doesn't know; (5) a broken list; (6) a `files` path
that doesn't exist; (7) a daemon-set use in an entry. Each use id names its
home, the one place that owns the concern (Paths for the environment,
CompositorManager for compositor state, the surface's window file for a
window, a `*Manager` for a service module). A new use of a Quickshell API goes
in its concern's home; a new concern gets a home and an entry with its reason.

The naming and structure rules in `RULES` (one statement each, printed under
the failures) are held to scripts/structure-baseline.json, which only shrinks:
a hit not in it fails, a fixed entry left behind fails, and an entry added
since the base fails unless its rule is new there or it moved to another
file. A hit is `<file>: <rule> <symbol>`; scripts/structure-exceptions.json
waives one (a file glob, or a name; rules and reason; an entry that waives
nothing fails; quickshell-use's grants are scripts/quickshell-exceptions.json's, never this file).

  scripts/check_structure.py                    errors (exit 1) and warnings
  scripts/check_structure.py --base REF         read the base from REF (default: HEAD^1 in CI, else the
                                                merge-base with origin/main)
  scripts/check_structure.py --update-baseline  add the hits of a rule the same change adds, re-key a moved
                                                entry, drop the fixed ones
"""
import argparse
import difflib
import json
import re
import sys
from pathlib import Path

import gen_docs
import qml_modules
from qml_modules import qml_files

ROOT = Path(__file__).resolve().parent.parent
SELF = "scripts/check_structure.py"
BASELINE = "scripts/structure-baseline.json"
EXCEPTIONS = ROOT / "scripts" / "structure-exceptions.json"
RULES = {
    "private-reach": "a `_name` member is its own file's: never read as `other._name`, never an `id: _name`",
    "root-id": "a file's root object is `id: root`",
    "stem-unique": "a file's name is unique across qml/, tests/ and tests-layout/; a singleton never takes a plug-in's file name",
    "suffix-rules": "a suffix says what the file is: Manager and Editor in services/, Window makes a window, Panel extends Panel, Layer is the layer model's",
    "folder-case": "grouping folders are lowercase words joined; a folder of one kind under surfaces/ or content/parts/ is singular",
    "test-names": "test functions are `test_snake_case`; a `tst_<X>` tests exactly the stem <X>, never a near-stem of another",
    "singleton-children": "a singleton's members are properties, functions and signals: its child objects hang off a property",
    "quickshell-use": "a Quickshell API only in the files scripts/quickshell-exceptions.json lists, the four anywhere types, or a baseline entry; system data, compositor IPC, files and processes are the daemon's",
}
# The shell's QML: `qs.` module names are relative to it
QML_ROOT = ROOT / "qml"
SCHEMA = QML_ROOT / "config" / "json" / "config.schema.json"

# (schema oneOf definition, root its types load from, file prefix): a type
# is a folder <root>/<Type>/ with <prefix><Type>.qml (docs/dev/core/config-manager.md,
# › The shape of config.json). Custom widget elements are Custom<Type>.qml, so an element
# named after a Qt type (Text, Image, List) never shadows it
LOADERS = [
    ("BarWidget", "qml/components/bar/widgets", ""),
    ("OverlayView", "qml/components/views", ""),
    ("OverlayModule", "qml/components/content", ""),
    ("CustomElement", "qml/components/content/parts/custom/elements", "Custom"),
    ("OSDSystem", "qml/components/surfaces/osd/systems", ""),
]
# An OSD system's folder (docs/dev/features/osd.md › Engine): its pure
# definition <Type>.qml, its watcher <Type>Watch.qml (the only file that
# reads services, with design/ for its visuals) and schema.yaml. Every file
# in it is loaded by URL (Paths.osdSystemUrl) and none names another, so
# the folders are never imported by name; the bases are, by the host
OSD_SYSTEMS = "qml/components/surfaces/osd/systems"
OSD_ENGINE = "qs.components.surfaces.osd.engine"
# What a definition may import: pure, so the unit tests load it
OSD_DEFINITION_IMPORTS = {"QtQuick", "qs.components.methods", OSD_ENGINE}
# Bar popouts load content/<popoutName>/<popoutName>.qml, from the same root
# as overlay modules (a content type can be both)
POPOUT_DIR = "qml/components/content"
# Beside the type folders, the folders of what they share (lowercase)
SHARED_FOLDERS = {"base", "parts"}
# The words a file name ends in to say what the file is: a test name ending in one is a near-stem
STEM_SUFFIXES = ("Manager", "Config", "Engine", "Window", "Panel", "Pane", "Host", "Editor", "Surface", "Screen",
                 "Layer", "Card", "Base", "State", "Entry")
# The files that are the layer model (the only `*Layer` stems)
LAYER_MODEL = {"LayerManager", "LayerStack", "LayerSlot", "LayerOrigin", "LayerArrange"}
# The directories that hold the tests
TEST_DIRS = ("tests", "tests-layout")
# The folders whose child folders are grouping folders: lowercase and singular
GROUPING_PARENTS = ("qml/components/surfaces", "qml/components/content/parts")
WINDOW_TYPE = re.compile(r"(?<![\w.])\w+Window\s*\{")
# Directories retired by restructuring: nothing may live or be imported there
RETIRED = ["qml/components/widgets", "qml/components/stolen"]
# The files allowed Quickshell APIs, each with its reason (quickshell-use)
QUICKSHELL_EXCEPTIONS = ROOT / "scripts" / "quickshell-exceptions.json"
# {use id: (pattern over a file's code, set, home, advice)}: set is "wayland", "toolkit" or "daemon" (only the
# first two can be listed); advice None = the service-module advice (UI: read it through the service; services
# and readers: extend the home over BackendManager)
QUICKSHELL_USES = {
    "window": (re.compile(r"(?<![\w$])(?:PanelWindow|PopupWindow|FloatingWindow|QsWindow|ExclusionMode|Edges|PopupAdjustment|Region|RegionShape|Intersection)\b"),
               "wayland", "the surface's window file", "go through the surface's window file or a piece in components/hosts/window/"),
    "instances": (re.compile(r"(?<![\w$])(?:ShellRoot|Scope|Variants|LazyLoader)\b"), "toolkit", "the shell entry in qml/shell/",
                  "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "persist": (re.compile(r"(?<![\w$])PersistentProperties\b|(?<![\w$])Singleton\s*\{"), "toolkit", "the service that owns the state",
                "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "runtime": (re.compile(r"\bQuickshell\.(?:reload|shellDir|shellPath|processId|appId)\b"), "toolkit", "the file that reads the runtime",
                "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "env": (re.compile(r"\bQuickshell\.env\("), "toolkit", "Paths", "read it through Paths"),
    "screens": (re.compile(r"\bQuickshell\.screens\b"), "wayland", "General", "build on General.outputs or General.screensFor(target)"),
    "apps": (re.compile(r"(?<![\w$])DesktopEntr(?:ies|y)\b|\bQuickshell\.iconPath\b"), "daemon", "AppIconManager", None),
    "tray-menu": (re.compile(r"(?<![\w$])(?:QsMenuOpener|QsMenuHandle|QsMenuEntry|QsMenuButtonType)\b"), "daemon", "TrayMenuList", None),
    "screen-type": (re.compile(r"(?<![\w$])ShellScreen\b"), "wayland", "the anywhere section", "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "rounded-clip": (re.compile(r"(?<![\w$])ClippingRectangle\b"), "toolkit", "the anywhere section", "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "clock": (re.compile(r"(?<![\w$])SystemClock\b"), "toolkit", "the anywhere section", "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "diff-model": (re.compile(r"(?<![\w$])ScriptModel\b"), "toolkit", "the anywhere section", "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "layer-shell": (re.compile(r"(?<![\w$])(?:WlrLayershell|WlrLayer|WlrKeyboardFocus)\b"), "wayland", "the surface's window file",
                    "go through the surface's window file or a piece in components/hosts/window/"),
    "session-lock": (re.compile(r"(?<![\w$])WlSessionLock\w*"), "wayland", "Lockscreen",
                     "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "screencopy": (re.compile(r"(?<![\w$])ScreencopyView\b"), "wayland", "a capture window",
                   "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "foreign-toplevel": (re.compile(r"(?<![\w$])ToplevelManager\b"), "wayland", "the file that tracks the windows",
                         "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "background-effect": (re.compile(r"(?<![\w$])BackgroundEffect\b"), "wayland", "the surface's window file",
                          "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "shortcut-inhibit": (re.compile(r"(?<![\w$])ShortcutInhibitor\b"), "wayland", "KeyRecorder",
                         "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "icon-image": (re.compile(r"(?<![\w$])IconImage\b"), "toolkit", "the file that draws the icon",
                   "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "hyprland": (re.compile(r"(?<![\w$])Hyprland\.(?!dispatch\()"), "daemon", "CompositorManager", "go through CompositorManager"),
    "focus-grab": (re.compile(r"(?<![\w$])HyprlandFocusGrab\b"), "wayland", "HyprlandGrab",
                   "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "compositor-dispatch": (re.compile(r"(?<![\w$])(?:Hyprland|I3)\.dispatch\("), "daemon", "CompositorManager", "go through CompositorManager"),
    "i3": (re.compile(r"(?<![\w$])I3\.(?!dispatch\()|(?<![\w$])I3IpcListener\b"), "daemon", "CompositorManager", "go through CompositorManager"),
    "process": (re.compile(r"(?<![\w.])Process\s*\{"), "daemon", "CommandManager",
                "go through CommandManager, FileManager, StateManager or IpcTarget, or a daemon method"),
    "file-view": (re.compile(r"(?<![\w.])FileView\s*\{"), "daemon", "FileManager",
                  "go through CommandManager, FileManager, StateManager or IpcTarget, or a daemon method"),
    "socket": (re.compile(r"(?<![\w.])(?:Socket|SplitParser)\s*\{"), "toolkit", "BackendManager",
               "add the file to scripts/quickshell-exceptions.json with what it is the platform's home for"),
    "exec-detached": (re.compile(r"\bQuickshell\.execDetached\("), "daemon", "CommandManager",
                      "go through CommandManager, FileManager, StateManager or IpcTarget, or a daemon method"),
    "pipewire": (re.compile(r"^import Quickshell\.Services\.Pipewire\b", re.M), "daemon", "AudioManager", None),
    "mpris": (re.compile(r"^import Quickshell\.Services\.Mpris\b", re.M), "daemon", "MediaManager", None),
    "upower": (re.compile(r"^import Quickshell\.Services\.UPower\b", re.M), "daemon", "BatteryManager", None),
    "notifications": (re.compile(r"^import Quickshell\.Services\.Notifications\b", re.M), "daemon", "NotificationManager", None),
    "system-tray": (re.compile(r"^import Quickshell\.Services\.SystemTray\b", re.M), "daemon", "the bar's SystemTray widget", None),
    "polkit": (re.compile(r"^import Quickshell\.Services\.Polkit\b", re.M), "daemon", "PolkitManager", None),
    "pam": (re.compile(r"^import Quickshell\.Services\.Pam\b", re.M), "daemon", "AuthManager", None),
    "greetd": (re.compile(r"^import Quickshell\.Services\.Greetd\b", re.M), "daemon", "GreetdManager", None),
    "networking": (re.compile(r"^import Quickshell\.Networking\b", re.M), "daemon", "NetworkingManager", None),
}

# The chrome-drawing constructs the one chrome path replaced, frozen to the
# files that use them now (path -> the kinds it may use)
CHROME_ALLOWLIST = ROOT / "scripts" / "chrome-drawing-allowlist.json"
CHROME_KINDS = {
    "HoledCopy": re.compile(r"\bHoledCopy\s*\{"),
    "OutsideShadow": re.compile(r"\bOutsideShadow\s*\{"),
    "translucent": re.compile(r"\bAppearance\.translucent\b"),
}
# Deleted outright: not even a word of it, comments included
CHROME_GONE = re.compile(r"\b(?:HoledItem|shadowHoles)\b")

# Bar widgets allowed to break a rule of the bar widget template, each with
# its reason; an entry no longer needed is an error
WIDGET_EXCEPTIONS = ROOT / "scripts" / "bar-widget-exceptions.json"
LOCAL_EXCEPTIONS = ROOT / "scripts" / "ui-local-exceptions.json"
# Hand-built versions of what a shared piece does, in the config UI and the
# onboarding (rule name -> pattern on a line without comments)
LOCAL_PIECE_RULES = {
    "StateLayer": (re.compile(r"\bStateLayer\s*\{"), "a hand-built hover tint: use Pressable (or a piece that has one)"),
    "Keys.onSpacePressed": (re.compile(r"\bKeys\.onSpacePressed\b"), "hand-built keys: use Pressable"),
    "tone-sunken": (re.compile(r"\btone:[^\n]*\"sunken\""), "a sunken box: use ItemBox, InspectorCard or a card piece"),
    "onRowClicked": (re.compile(r"\bonRowClicked\s*:"), "a hand-set row click: give the row `activates`"),
    "first-literal": (re.compile(r"^\s*first\s*:\s*(?:true|false)\b"), "a `first:` literal: the row's column decides"),
}
LOCAL_RULES = set(LOCAL_PIECE_RULES) | {"SegmentButton", "restore-text"}
LOCAL_PIECE_SCOPES = ("qml/components/views/", "qml/components/surfaces/onboarding/")
SEGMENT_ROW_SCOPES = ("qml/components/views/", "qml/components/content/", "qml/components/surfaces/")
SEGMENT_HOSTS = ("SegmentRow", "SegmentTabs", "StyledToggle")
WIDGETS_DIR = "qml/components/bar/widgets"
WIDGET_RULES = {
    "widget-root": "a root other than BarWidget or AudioLevelWidget",
    "resolved-color": "a resolved colour: name a colour field, the base resolves it",
    "opacity-fade": "a fade by opacity or a dim by a dim: a dim is a colour the base draws",
    "color-field": "a colour field nothing uses, or a *Color named that isn't one of the widget's colour fields",
    "base-output": "a set or write of what the base computes (WIDGET_OUTPUTS)",
    "folder-files": "a file in the widget's folder besides <Type>.qml and schema.yaml",
    "box-read": "a .box read (or a bare box in <Type>.qml): read shownItems",
    "state-color-name": "stateColorName named: a state names its colour field (accentField)",
}
WIDGET_ROOTS = {"BarWidget", "AudioLevelWidget"}
# What the base computes: a widget declares data, never these (base-output)
WIDGET_OUTPUTS = ("colors drawnColors paint shownItems backgroundLevel backgroundLevelColor splits splitAt "
                  "splitPart innerSplits contentAcross leadLength minimumSize pulse box hitArea autoColors "
                  "barOffset barLength runPlace segmented pinStart fillsOnHover").split()
WIDGET_COLOR_CALLS = qml_modules.WIDGET_COLOR_CALLS

BARS_CONFIG = "qml/config/BarsConfig.qml"
# The windows with no layer service running (no LayerSlot), each with its
# reason: the greeter runs in its own shell, the notice shows where no
# parent shell does
LAYER_SLOT_EXCEPTIONS = {
    "qml/components/surfaces/greeter/GreeterWindow.qml": "the greeter's own shell runs no layer service",
    "qml/shell/NoParentNotice.qml": "shown where no shell runs, so no layer service",
}
LAYER_SERVICE = "qml/services/compositor/LayerManager.qml"
# The backends that declare the layer facts (supports.layerOrder, layerRestack)
LAYER_FACT_BACKENDS = ("qml/services/compositor/HyprlandManager.qml", "qml/services/compositor/SwayManager.qml",
                       "qml/services/compositor/NiriManager.qml")
# WlrLayer is read by the layer service, the window hosts and the excluded windows
WLR_LAYER_SCOPES = (LAYER_SERVICE, "qml/components/hosts/window/", *LAYER_SLOT_EXCEPTIONS)

errors, warnings = [], []


def rel(path):
    return path.relative_to(ROOT).as_posix()


def module_of(directory):
    """The `qs.` module a directory under QML_ROOT is (qml/a/b → qs.a.b)."""
    return ".".join(("qs",) + Path(directory).relative_to("qml").parts)


def module_dir(module):
    """The directory a `qs.` module names (qs.a.b → QML_ROOT/a/b)."""
    return QML_ROOT.joinpath(*module.split(".")[1:])


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


def qml_blocks(text, type_name):
    """Each `<type_name> { … }` in a QML file: (where its body starts, its body)."""
    blocks = []
    for m in re.finditer(rf"\b{type_name}\s*\{{", text):
        depth, i = 1, m.end()
        while i < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        blocks.append((m.end(), text[m.end():i]))
    return blocks


def bar_widget_template(schema, sources, errors):
    """Every bar widget is data on BarWidget (docs/dev/bar/widget-style.md ›
    The widget template): the WIDGET_RULES, but for the listed exceptions."""
    root = ROOT / WIDGETS_DIR
    exceptions, shape = qml_modules.load_exceptions(WIDGET_EXCEPTIONS, WIDGET_RULES, section="types")
    errors.extend(shape)
    found = {}  # type -> [(rule, message)]
    colour_fields = {}
    for t in schema_types(schema, "BarWidget"):
        props = schema["definitions"].get(f"{t}Widget", {}).get("properties", {}).get("properties", {}).get("properties", {})
        colour_fields[t] = {k for k, v in props.items() if v.get("x-options") == "colors"}

    def lines_of(code, pattern):
        for m in re.finditer(pattern, code):
            yield code.count("\n", 0, m.start()) + 1, m

    for folder in sorted(p for p in root.iterdir() if p.is_dir() and p.name != "base"):
        t = folder.name
        out = found.setdefault(t, [])

        def add(rule, message):
            out.append((rule, f"{message}"))
        files = sorted(folder.rglob("*.qml"))
        raw = {f: f.read_text() for f in files}
        code = {f: re.sub(r"//[^\n]*", "", text) for f, text in raw.items()}
        plain = {f: qml_modules.blank_strings(c) for f, c in code.items()}
        main_file = folder / f"{t}.qml"

        if main_file in raw:
            lines = raw[main_file].split("\n")
            start = next((i for i, line in enumerate(lines) if re.match(r"[A-Z][\w.]*\s*\{", line)), None)
            name = re.match(r"[A-Z][\w.]*", lines[start]).group(0) if start is not None else None
            if name not in WIDGET_ROOTS:
                add("widget-root", f"{rel(folder)}/{t}.qml: widget-root its root is {name}, not BarWidget or AudioLevelWidget")

        for f in files:
            path = rel(f)
            short = f"{t}/{f.relative_to(folder).as_posix()}"
            for n, m in lines_of(code[f], WIDGET_COLOR_CALLS):
                add("resolved-color", f"{short}:{n}: resolved-color resolves a colour ({m.group(0).strip()}): name a colour field, the base resolves it")
            # opacity: only an Image fades; else a switch of 0 or 1
            stack = []
            for n, line in enumerate(plain[f].split("\n"), 1):
                events = [(m.start(), "push", m.group(1).split(".")[-1] if m.group(1) else None)
                          for m in re.finditer(r"(?:([A-Z][\w.]*)\s*)?\{", line)]
                events += [(m.start(), "pop", None) for m in re.finditer(r"\}", line)]
                events += [(m.start(), "opacity", m.end()) for m in re.finditer(r"\bopacity\s*:", line)]
                for at, kind, arg in sorted(events, key=lambda e: (e[0], {"push": 0, "opacity": 1, "pop": 2}[e[1]])):
                    if kind == "push":
                        stack.append(arg)
                    elif kind == "pop":
                        if stack:
                            stack.pop()
                    else:
                        owner = next((x for x in reversed(stack) if x), None)
                        if owner in ("Image", "IconImage"):
                            continue
                        offset = sum(len(x) + 1 for x in plain[f].split("\n")[:n - 1]) + arg
                        expr = binding(plain[f], offset)
                        if any(float(x) not in (0, 1) for x in re.findall(r"(?<![\w.])(?:\d+(?:\.\d*)?|\.\d+)", expr)):
                            add("opacity-fade", f"{short}:{n}: opacity-fade fades by opacity ({expr.strip()}): an opacity is 0 or 1, a dim is a colour")
            for n, _ in lines_of(plain[f], r"\bdim\b"):
                add("opacity-fade", f"{short}:{n}: opacity-fade dims by a `dim`: a dim is a colour the base draws")
            for n, _ in lines_of(plain[f], r"\.box\b"):
                add("box-read", f"{short}:{n}: box-read reads .box: read shownItems")
            if f == main_file:
                for n, _ in lines_of(plain[f], r"(?<![\w.$])(?<!let )(?<!const )(?<!var )(?<!id: )(?<!id:)box\b(?!\s*:)"):
                    add("box-read", f"{short}:{n}: box-read reads box: read shownItems")
            for n, _ in lines_of(plain[f], r"\bstateColorName\b"):
                add("state-color-name", f"{short}:{n}: state-color-name names stateColorName: a state names its colour field (accentField)")

        if main_file in raw:
            body = plain[main_file]
            depth = 0
            names = "|".join(WIDGET_OUTPUTS)
            binding_re = re.compile(r"^\s*(?:(?:readonly\s+|required\s+|default\s+)*property\s+[\w<>.]+\s+)?(" + names + r")\s*:")
            for n, line in enumerate(body.split("\n"), 1):
                if depth == 1 and binding_re.match(line):
                    add("base-output", f"{t}/{t}.qml:{n}: base-output sets {binding_re.match(line).group(1)}: it is the base's output")
                depth += line.count("{") - line.count("}")
            for n, m in lines_of(body, r"(?<![\w.])(?<!let )(?<!var )(?<!const )(?:root\.)?(" + names + r")\s*=(?!=)"):
                add("base-output", f"{t}/{t}.qml:{n}: base-output writes {m.group(1)}: it is the base's output")

        for f in sorted(folder.iterdir()):
            if f.name not in (f"{t}.qml", "schema.yaml"):
                add("folder-files", f"{rel(folder)}/: folder-files holds {f.name}: only {t}.qml and schema.yaml")

    # color-field: a colour field nothing uses, a colour named that isn't one
    unused_without = {}
    for t, fields in colour_fields.items():
        folder = root / t
        if not folder.is_dir():
            continue
        out = found.setdefault(t, [])
        texts = {f: re.sub(r"//[^\n]*", "", f.read_text()) for f in folder.glob("*.qml")}
        allcode = "\n".join(texts.values())
        used = set(re.findall(r'"([^"\\\n]*)"', allcode))
        used |= set(re.findall(r"\bautoColors\.(\w+)", allcode))
        used |= set(re.findall(r"\bproperties\??\.(\w+)", allcode))
        used.add("foregroundColor")
        main_code = texts.get(folder / f"{t}.qml", "")
        if not re.search(r"\baccentField\s*:", main_code):
            used.add("backgroundColor")
        unused_without[t] = fields - used
        extra = set()
        for path in exceptions.get(t, {}).get("fieldsReadIn", []):
            extra |= set(re.findall(r"\bproperties\??\.(\w+)", sources.get(path, "")))
        for field in sorted(fields - used - extra):
            out.append(("color-field", f"{t}/: color-field {field} is a colour field of {t} that nothing uses"))
        for f, c in texts.items():
            asks = [(m.end(), binding(c, m.end())) for m in re.finditer(r"\b(?:accentField|iconField)\s*:", c)]
            asks += [(m.end(), binding(c, m.end())) for m in re.finditer(r'(?<![\w.])"?field"?\s*:', c)]
            asks += [(m.end(), binding(c, m.end()).split(",")[0]) for m in re.finditer(r"\bpaint\.(?:field|line)\(", c)]
            for at, expr in asks:
                for name in re.findall(r'"(color|\w+Color)"', expr):
                    if name not in fields:
                        n = c.count("\n", 0, at) + 1
                        out.append(("color-field", f"{t}/{f.name}:{n}: color-field names {name}, not a colour field of {t}"))

    name = rel(WIDGET_EXCEPTIONS)
    for t, entry in exceptions.items():
        if not (root / t).is_dir():
            errors.append(f"{name}: {t} has no folder under {WIDGETS_DIR}")
            continue
        for rule in entry["rules"]:
            if rule in WIDGET_RULES and not any(r == rule for r, _ in found.get(t, [])):
                errors.append(f"{name}: {t} lists {rule}, which it no longer breaks")
        read_in = entry.get("fieldsReadIn", [])
        if read_in:
            supplied = set()
            for path in read_in:
                if path not in sources:
                    errors.append(f"{name}: {t} reads fields in {path}, which doesn't exist")
                supplied |= set(re.findall(r"\bproperties\??\.(\w+)", sources.get(path, "")))
            if not (unused_without.get(t, set()) & supplied):
                errors.append(f"{name}: {t} lists fieldsReadIn, which supplies none of its otherwise-unused colour fields")

    for t, items in found.items():
        skip = set(exceptions.get(t, {}).get("rules", []))
        for rule, message in items:
            if rule not in skip:
                errors.append(message)


def layer_service(sources, errors):
    """The layer service's structure (docs/dev/compositor/layer-arrangement.md):
    layer-namespace-row: every "axiom-<x>" a window is given has one
    LayerStack.layers row with a layer; layer-slot-binding: windows bind
    the slot's layer and their own namespace, and the layer facts and
    WlrLayer stay the service's."""
    rows = gen_docs.json_property(gen_docs.LAYERS_PATH, "layers", default=[])
    stack_path = rel(gen_docs.LAYERS_PATH)
    names = [r["namespace"] for r in rows]
    for name in sorted({n for n in names if names.count(n) > 1}):
        errors.append(f"{stack_path}: layer-namespace-row: namespace {name} has two rows")
    for r in rows:
        if "layer" not in r:
            errors.append(f"{stack_path}: layer-namespace-row: row {r['namespace']} names no layer")
    given = {}  # namespace -> where
    for path, text in sources.items():
        if path.startswith("tests/"):
            continue
        code = re.sub(r"//[^\n]*", "", text)
        for n, line in enumerate(code.split("\n"), 1):
            m = re.search(r"\b(?:layerNamespace|WlrLayershell\.namespace)\s*:(.*)", line)
            if m:
                for lit in re.findall(r'"axiom-([\w-]+)"', m.group(1)):
                    given.setdefault(lit, f"{path}:{n}")
    bars = re.search(r"function layerNamespace\(.*?\n  \}", sources.get(BARS_CONFIG, ""), re.S)
    for lit in re.findall(r'"axiom-([\w-]+)"', bars.group(0) if bars else ""):
        given.setdefault(lit, BARS_CONFIG)
        given.setdefault(lit + "-long", BARS_CONFIG)
    for name, where in sorted(given.items()):
        if name not in names:
            errors.append(f"{where}: layer-namespace-row: axiom-{name} has no LayerStack.layers row ({stack_path})")

    for path, text in sorted(sources.items()):
        if path.startswith("tests/"):
            continue
        code = re.sub(r"//[^\n]*", "", text)
        for n, line in enumerate(code.split("\n"), 1):
            if path not in LAYER_SLOT_EXCEPTIONS:
                layer = re.search(r"\bWlrLayershell\.layer\s*:\s*(.*)", line)
                if layer:
                    slots = [re.search(r"\bid\s*:\s*(\w+)", body).group(1) for _, body in qml_blocks(code, "LayerSlot")
                             if re.search(r"\bid\s*:\s*(\w+)", body)]
                    if layer.group(1).strip() not in [f"{s}.layer" for s in slots]:
                        errors.append(f"{path}:{n}: layer-slot-binding: WlrLayershell.layer binds `{layer.group(1).strip()}`: bind <id>.layer of the window's LayerSlot")
                name = re.search(r"\bWlrLayershell\.namespace\s*:\s*(.*)", line)
                if name and not re.fullmatch(r"\w+\.layerNamespace", name.group(1).strip()):
                    errors.append(f"{path}:{n}: layer-slot-binding: WlrLayershell.namespace binds `{name.group(1).strip()}`: bind <id>.layerNamespace")
            if path != LAYER_SERVICE and not path.startswith(LAYER_FACT_BACKENDS) and re.search(r"\blayer(?:Order|Restack)\b", line):
                errors.append(f"{path}:{n}: layer-slot-binding: reads a layer fact (layerOrder, layerRestack): only {LAYER_SERVICE} does")
            if "WlrLayer." in line and not path.startswith(WLR_LAYER_SCOPES):
                errors.append(f"{path}:{n}: layer-slot-binding: reads WlrLayer: only the layer service, components/hosts/window/ and the windows with no layer service do")
            if re.search(r"\bbacksOn\([^,()]+,\s*(?:true|false)\s*\)", line):
                errors.append(f"{path}:{n}: layer-slot-binding: backsOn takes a literal layer: pass the slot's onOverlayLayer")


def popout_modules(schema, sources, errors):
    """A bar widget's x-popoutModule.type is the literal popoutName of its
    folder's QML or of the base file its root type is (AudioLevelWidget for
    Volume and Microphone), a widget whose popoutName is an overlay module
    type declares x-popoutModule, and a module popout is handed widget
    values by `fromWidget: ({…})` on its anchor: the keys the widget's
    x-popoutModule.fromWidget lists, never `extraData` (a widget without
    x-popoutModule has no `fromWidget`)."""
    modules = set(schema_types(schema, "OverlayModule"))
    for t in schema_types(schema, "BarWidget"):
        folder = f"{WIDGETS_DIR}/{t}/"
        files = [path for path in sources if path.startswith(folder)]
        main_text = sources.get(f"{folder}{t}.qml", "")
        root_type = re.search(r"^([A-Z][\w.]*)\s*\{", main_text, re.M)
        if root_type and f"{WIDGETS_DIR}/base/{root_type.group(1)}.qml" in sources:
            files.append(f"{WIDGETS_DIR}/base/{root_type.group(1)}.qml")
        names = {m for path in files for m in re.findall(r'popoutName:\s*"([^"]+)"', sources[path])}
        module = schema["definitions"].get(f"{t}Widget", {}).get("x-popoutModule")
        declared = (module or {}).get("type")
        if declared and declared not in names:
            errors.append(f"{WIDGETS_DIR}/{t}: x-popoutModule.type {declared} is not a popoutName it opens ({', '.join(sorted(names)) or 'none'})")
        if not declared and names & modules:
            errors.append(f"{WIDGETS_DIR}/{t}: its popoutName {', '.join(sorted(names & modules))} is an overlay module: declare popoutModule in its schema.yaml")
        for path in files:
            for _, anchor in qml_blocks(sources[path], "PopoutAnchor"):
                given = re.search(r"\bfromWidget:\s*\(\{(.*?)\}\)", anchor, re.S)
                if module and re.search(r"\bextraData:", anchor):
                    errors.append(f"{path}: a PopoutAnchor in a widget with popoutModule hands its values by fromWidget, not extraData")
                if given and not module:
                    errors.append(f"{path}: a PopoutAnchor has fromWidget, but {WIDGETS_DIR}/{t} declares no popoutModule")
                elif module:
                    keys = set(re.findall(r'[{,]\s*"(\w+)"\s*:', "{" + given.group(1))) if given else set()
                    if keys != set(module.get("fromWidget", [])):
                        errors.append(f"{path}: a PopoutAnchor's fromWidget keys ({', '.join(sorted(keys)) or 'none'}) differ from {t}'s popoutModule.fromWidget ({', '.join(sorted(module.get('fromWidget', []))) or 'none'})")


def words(name):
    """The camel-case words of a name (`OSDSystems` → OSD, Systems)."""
    return re.findall(r"[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+", name)


def is_plugin_main(path):
    """Whether `path` is a plug-in's main file: <root>/<Type>/<prefix><Type>.qml of one of LOADERS' roots."""
    p = Path(path)
    return any(p.parent.parent.as_posix() == directory and p.stem == prefix + p.parent.name
               for _, directory, prefix in LOADERS)


def harness_files():
    """The test harnesses' QML (not the layout stubs), {repo-relative path: text}."""
    return {rel(f): f.read_text() for d in TEST_DIRS for f in sorted((ROOT / d).rglob("*.qml"))
            if not f.is_relative_to(qml_modules.LAYOUT_STUBS)}


def near_stem(name, stems):
    """Whether the test name `name` is a near-stem of one of `stems`: a truncation of a stem of 2+ words, a
    name ending in a STEM_SUFFIXES word after another word, or 2+ words close to a longer stem's same-length
    prefix."""
    parts = words(name)
    if len(parts) < 2:
        return False
    if parts[-1] in STEM_SUFFIXES:
        return True
    return any(len(stem) > len(name) and (stem.startswith(name) and len(words(stem)) >= 2
                                          or difflib.SequenceMatcher(None, name, stem[:len(name)]).ratio() >= 0.85)
               for stem in stems)


def naming_hits(sources, tests):
    """({file: {rule: [symbol]}} past the exceptions, errors): the hits of RULES but quickshell-use over the shell's `sources`
    and the `tests` harnesses ({path: text} each)."""
    hits = qml_modules.Hits()
    stems = {}
    for path in (*sources, *tests):
        stems.setdefault(Path(path).stem, []).append(path)
    plugin_stems = {Path(path).stem for path in sources if is_plugin_main(path)}
    window_pieces = {Path(p).stem for p in sources if re.fullmatch(r"\w+Window", Path(p).stem)}
    for path, text in {**sources, **tests}.items():
        stem = Path(path).stem
        src = qml_modules.Source(path, text)
        code = src.code
        plugin = is_plugin_main(path)
        if not plugin and (any(p != path and not is_plugin_main(p) for p in stems[stem])
                           or qml_modules.SINGLETON.search(code) and stem in plugin_stems):
            hits.add(path, "stem-unique", f"stem:{stem}")
        if path in tests:
            for m in re.finditer(r"\bfunction\s+(test_\w+)", code):
                if not re.fullmatch(r"test_[a-z0-9_]+", m.group(1)):
                    hits.add(path, "test-names", m.group(1), m.start())
            if stem.startswith("tst_") and stem[4:] not in stems and near_stem(stem[4:], stems):
                hits.add(path, "test-names", f"file:{stem}")
            continue
        declared = {name for name, _ in src.declared()}
        keys = set(re.findall(r"[{,]\s*[\"']?(_\w+)[\"']?\s*:", src.stripped))
        found = []
        for m in re.finditer(r"(?<![\w.])(\w+)\??\._(\w+)", code):
            if m.group(1) != "root" and f"_{m.group(2)}" not in declared | keys:
                found.append((src.at(m.start()), f"{m.group(1)}._{m.group(2)}"))
        found += [(at, f"id {name}") for name, at in src.ids if name.startswith("_")]
        hits.add_at(path, "private-reach", text, found)
        root = gen_docs.ROOT_OBJECT.search(code)
        root_type = root.group(1) if root else None
        body = code[root.end():] if root else ""
        if (m := re.search(r"^  id\s*:\s*(\w+)", body, re.M)) and m.group(1) != "root":
            hits.add(path, "root-id", f"{stem}:{m.group(1)}")
        if plugin or path in tests:
            continue
        if (m := re.fullmatch(r"\w+(Manager|Editor)", stem)) and not path.startswith("qml/services/"):
            hits.add(path, "suffix-rules", f"{stem}:{m.group(1)}")
        window_root = root_type is not None and (root_type in ("PanelWindow", "FloatingWindow") or root_type in window_pieces)
        if stem.endswith("Window") and not WINDOW_TYPE.search(code) or window_root and not stem.endswith("Window"):
            hits.add(path, "suffix-rules", f"{stem}:Window")
        if re.fullmatch(r"\w+Panel", stem) and root_type != "Panel":
            hits.add(path, "suffix-rules", f"{stem}:Panel")
        if re.fullmatch(r"\w+Layer", stem) and stem not in LAYER_MODEL:
            hits.add(path, "suffix-rules", f"{stem}:Layer")
        if qml_modules.SINGLETON.search(code):
            for m in re.finditer(r"^  ([A-Z][\w.]*)\s*\{", code, re.M):
                if m.group(1) != "PersistentProperties":
                    hits.add(path, "singleton-children", m.group(1), m.start())
    for folder in sorted(p for p in QML_ROOT.rglob("*") if p.is_dir()):
        name, path = folder.name, rel(folder)
        if re.fullmatch(r"[a-z]\w*[A-Z]\w*", name) or rel(folder.parent) in GROUPING_PARENTS and re.fullmatch(r"[a-z]\w*s", name):
            hits.add(path, "folder-case", f"folder:{name}")
    found = hits.found()
    exceptions, errors = qml_modules.load_exceptions(EXCEPTIONS, set(RULES) - {"quickshell-use"})
    return found, errors + qml_modules.waive(found, exceptions, "scripts/structure-exceptions.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--base", default=None)
    parser.add_argument("--update-baseline", action="store_true")
    args = parser.parse_args()
    base = args.base or qml_modules.default_base()
    schema = json.loads(SCHEMA.read_text())
    sources = {rel(f): f.read_text() for f in qml_files()}
    named, hit_errors = naming_hits(sources, harness_files())
    # quickshell-use: a Quickshell API only in the files scripts/quickshell-exceptions.json lists (its `files`
    # grants Wayland- and toolkit-set uses, `anywhere` the four anywhere types, `never` bans a module); every other
    # use is a found entry the ratchet holds to structure-baseline.json (daemon-set uses can't be granted). Its
    # found joins `named` after the waive: structure-exceptions.json never grants it
    anywhere, anywhere_errors = qml_modules.load_exceptions(QUICKSHELL_EXCEPTIONS, set(QUICKSHELL_USES), section="anywhere")
    never, never_errors = qml_modules.load_exceptions(QUICKSHELL_EXCEPTIONS, set(QUICKSHELL_USES), section="never")
    granted, granted_errors = qml_modules.load_exceptions(QUICKSHELL_EXCEPTIONS, set(QUICKSHELL_USES), section="files")
    quick_file = rel(QUICKSHELL_EXCEPTIONS)
    quick_errors = anywhere_errors + never_errors + granted_errors
    quick, said, used = qml_modules.Hits(), {}, {}
    for path, text in sources.items():
        src = qml_modules.Source(path, text)
        for n, (use, (pattern, kind, home, advice)) in enumerate(QUICKSHELL_USES.items()):
            m = pattern.search(src.code)
            if not m:
                continue
            used.setdefault(path, set()).add(use)
            if kind != "daemon" and (use in anywhere or use in granted.get(path, {}).get("rules", [])):
                continue
            quick.add(path, "quickshell-use", use, n)
            what = f"{path}: quickshell-use {use} ({m.group(0).rstrip(" \t\n({.")}):"
            if kind != "daemon":
                said[path, use] = f"{what} only the files {quick_file} lists may ({home} is {use}'s home): {advice}"
            elif advice:
                said[path, use] = f"{what} {advice}"
            elif not home.endswith("Manager"):
                said[path, use] = f"{what} move it into {home}"
            elif path.startswith(("qml/components/", "qml/shell/")):
                said[path, use] = f"{what} read it through that service ({home} is {use}'s home)"
            else:
                said[path, use] = f"{what} system data comes from the daemon, not a Quickshell module: extend {home} over BackendManager"
        imports = text
        for module, entry in never.items():
            gone = re.compile(rf"^import {re.escape(module)}\b.*$", re.M)
            if gone.search(text):
                quick_errors.append(f"{path}: quickshell-use {module}: {entry['reason']}")
                imports = gone.sub("", imports)
        if qml_modules.QUICKSHELL_IMPORT.search(imports) and path not in used:
            quick_errors.append(f"{path}: quickshell-use import: imports Quickshell but uses nothing QUICKSHELL_USES knows: drop the import, or add the type to QUICKSHELL_USES with a use id and a reason")
        unknown = set()
        for line in src.code.split("\n"):
            if not line.lstrip().startswith("import "):
                unknown |= {m.group(1) for m in re.finditer(r"(?<![\w$.])Quickshell\.([a-z]\w*)", line)
                            if not any(pattern.match(line, m.start()) for pattern, *_ in QUICKSHELL_USES.values())}
        quick_errors += [f"{path}: quickshell-use Quickshell.{member}: a Quickshell member QUICKSHELL_USES doesn't know: add it to QUICKSHELL_USES with a use id and a reason"
                         for member in sorted(unknown)]
    for key, entry in sorted({**anywhere, **granted}.items()):
        if key in granted and not (ROOT / key).exists():
            quick_errors.append(f"{quick_file}: {key} doesn't exist")
            continue
        for use in entry["rules"]:
            if use not in QUICKSHELL_USES:
                continue
            if QUICKSHELL_USES[use][1] == "daemon":
                quick_errors.append(f"{quick_file}: {key} lists {use}, a daemon-set use: it can't be granted (its remaining uses are structure-baseline.json entries)")
            elif key in granted and use not in used.get(key, set()):
                quick_errors.append(f"{quick_file}: {key} no longer uses {use}: remove it: the list only shrinks")
    for path, rules in quick.found().items():
        named.setdefault(path, {}).update(rules)
    hit_errors += quick_errors
    if args.update_baseline:
        try:
            if not hit_errors:
                print(f"{qml_modules.add_to_baseline(named, BASELINE, qml_modules.new_rules(base, SELF, RULES), base=base)} entries in {BASELINE}")
                return 0
        except ValueError as e:
            hit_errors = [str(e)]
        print("\n".join(hit_errors))
        return 1
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
    scanned, todo = set(), imports_of(sources["qml/shell.qml"])
    while todo:
        module = todo.pop()
        if module in scanned:
            continue
        scanned.add(module)
        for f in module_dir(module).glob("*.qml"):
            todo |= imports_of(sources.get(rel(f), "")) - scanned
    unreached = {}
    for _, directory, _ in LOADERS:
        osd = directory == OSD_SYSTEMS
        for f in sorted((ROOT / directory).rglob("*.qml")):
            own = module_of(rel(f.parent))
            needed = imports_of(sources[rel(f)])
            # A system's files never name each other (checked below)
            if len(list(f.parent.glob("*.qml"))) > 1 and not osd:
                needed.add(own)
            for module in sorted(needed - scanned):
                unreached.setdefault(module, rel(f))
    for module, path in sorted(unreached.items()):
        errors.append(f"{path} needs {module}, which no file reached from shell.qml imports: qs won't scan it (import it in the host that loads it)")

    # An OSD system: its definition, its watcher and its schema.yaml; the
    # definition pure, services read only by the watcher (and design/),
    # and no file naming another of its folder (each loads by URL)
    for d in sorted(p for p in (ROOT / OSD_SYSTEMS).iterdir() if p.is_dir()):
        for need in (f"{d.name}.qml", f"{d.name}Watch.qml", "schema.yaml"):
            if not (d / need).exists():
                errors.append(f"{rel(d)}/: an OSD system without {need}")
        definition = d / f"{d.name}.qml"
        if definition.exists():
            bad = sorted(set(re.findall(r"^import ([\w.]+)", sources.get(rel(definition), ""), re.M)) - OSD_DEFINITION_IMPORTS)
            if bad:
                errors.append(f"{rel(definition)}: an OSD system's definition imports {', '.join(bad)}: it imports only "
                              f"{', '.join(sorted(OSD_DEFINITION_IMPORTS))} (services are its watcher's)")
        for f in sorted(d.glob("*.qml")):
            if f == definition or f.stem.endswith("Watch"):
                continue
            if re.search(r"^import (qs\.services|qs\.config|Quickshell)\b", sources.get(rel(f), ""), re.M):
                errors.append(f"{rel(f)}: reads services: only an OSD system's <Type>Watch.qml (and design/) may")
        files = list(d.rglob("*.qml"))
        for f in files:
            text = re.sub(r"//[^\n]*", "", sources.get(rel(f), ""))
            for other in files:
                if other != f and re.search(r"\b" + re.escape(other.stem) + r"\s*\{", text):
                    errors.append(f"{rel(f)}: uses {other.stem} of its own OSD system's folder: load it by URL (Paths.osdSystemUrl)")

    # The chrome-drawing constructs the one chrome path replaced stay
    # deleted (HoledItem, shadowHoles) or stay in the files
    # chrome-drawing-allowlist.json lists (HoledCopy, OutsideShadow,
    # Appearance.translucent; an entry no longer used is an error), and a
    # BlurShape blurs only while its host is `backed`
    chrome_allowed = json.loads(CHROME_ALLOWLIST.read_text())["files"]
    chrome_used = {}
    for path, text in sources.items():
        if path.startswith("tests/"):
            continue
        for n, line in enumerate(text.split("\n"), 1):
            if CHROME_GONE.search(line):
                errors.append(f"{path}:{n}: HoledItem or shadowHoles: deleted, the one chrome path draws the shape: see docs/dev/theming/blur-window-openings.md")
        code = re.sub(r"//[^\n]*", "", text)
        for kind, pattern in CHROME_KINDS.items():
            if pattern.search(code):
                chrome_used.setdefault(path, []).append(kind)
        for start, body in qml_blocks(code, "BlurShape"):
            if not re.search(r"\bshown:[^\n]*\bbacked\b", body):
                errors.append(f"{path}:{code.count(chr(10), 0, start) + 1}: a BlurShape whose `shown:` doesn't read `backed`")
    for path, kinds in sorted(chrome_used.items()):
        for kind in kinds:
            if kind not in chrome_allowed.get(path, []):
                errors.append(f"{path}: uses {kind} (only the files in {rel(CHROME_ALLOWLIST)} may)")
    for path, kinds in sorted(chrome_allowed.items()):
        for kind in kinds:
            if kind not in chrome_used.get(path, []):
                errors.append(f"{rel(CHROME_ALLOWLIST)}: {path} no longer uses {kind}: remove it from the list")

    # The config UI and the onboarding build no hover tint, key handler,
    # sunken box, hand-set row click or `first:` literal, no loose
    # SegmentButton and no pushed `text` that keeps its value: each is a
    # shared piece's job (docs/dev/core/shared-ui-pieces.md > When a page may
    # own a local piece). A file is listed in scripts/ui-local-exceptions.json
    # per rule with a reason (special drawing); an entry whose rule no
    # longer hits is an error
    local, local_errors = qml_modules.load_exceptions(LOCAL_EXCEPTIONS, LOCAL_RULES, section="files")
    errors.extend(local_errors)
    local_hits = {}
    for path, text in sorted(sources.items()):
        in_ui = path.startswith(LOCAL_PIECE_SCOPES)
        in_segments = path.startswith(SEGMENT_ROW_SCOPES)
        if not (in_ui or in_segments):
            continue
        lines = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S).split("\n")
        code = [line.split("//", 1)[0] for line in lines]
        for n, line in enumerate(code, 1):
            if in_ui:
                for name, (pattern, advice) in LOCAL_PIECE_RULES.items():
                    if pattern.search(line):
                        local_hits.setdefault((path, name), (n, advice))
                if "restoreMode: Binding.RestoreNone" in line and any('property: "text"' in c for c in code[max(0, n - 7):n]):
                    local_hits.setdefault((path, "restore-text"), (n, "a pushed `text` kept past its Binding: use CommitEntry"))
            if re.match(r"\s*(?:\w+:\s*)?SegmentButton\s*\{", line):
                indent = len(line) - len(line.lstrip())
                host = None
                for back in range(n - 2, -1, -1):
                    m = re.match(r"(\s*)(?:[\w.]+:\s*)?([A-Z]\w*)\s*\{", code[back])
                    if m and len(m.group(1)) < indent:
                        indent = len(m.group(1))
                        if m.group(2) in SEGMENT_HOSTS:
                            host = m.group(2)
                            break
                if host is None:
                    local_hits.setdefault((path, "SegmentButton"), (n, "a SegmentButton outside a SegmentRow or SegmentTabs: a toggle is a ToggleChip, a choice a SegmentRow"))
    for (path, name), (n, advice) in sorted(local_hits.items()):
        if name not in local.get(path, {}).get("rules", []):
            errors.append(f"{path}:{n}: {name}: {advice} (special drawing only: list the file in {rel(LOCAL_EXCEPTIONS)} with a reason)")
    for path, entry in sorted(local.items()):
        for name in entry.get("rules", []):
            if (path, name) not in local_hits:
                errors.append(f"{rel(LOCAL_EXCEPTIONS)}: {path} no longer breaks {name}: remove it from the list (it only shrinks)")

    # Services live in their group's folder (.claude/rules/services.md › Folders):
    # one directly in services/ would escape the singleton checks below,
    # check_docs and the API pages, which all read services/*/
    for path in sources:
        if re.fullmatch(r"qml/services/[^/]+\.qml", path):
            errors.append(f"{path}: directly in services/ (put it in its group's folder: .claude/rules/services.md)")

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

    # JS the QML engine lacks (qml-pitfalls.md › The JS engine) throws only
    # when the line runs, so no load or test catches it
    missing_js = re.compile(r"\bObject\.fromEntries\b|\.flatMap\s*\(|\.flat\s*\(\s*(Infinity)?\s*\)")
    for path, text in sources.items():
        for n, line in enumerate(text.split("\n"), 1):
            if missing_js.search(line.split("//", 1)[0]):
                errors.append(f"{path}:{n}: Object.fromEntries, flat or flatMap, which Qt's JS engine lacks: use reduce or [].concat(...arr.map(...)) (docs/dev/core/qml-pitfalls.md)")

    # Every library type joins one of the root's `x-libraryGroups` (the
    # editors' libraries group by them); required modules aren't offered
    library_groups = schema.get("x-libraryGroups", [])
    for definition in ("BarWidget", "OverlayModule", "OSDSystem"):
        for option in schema["definitions"][definition]["oneOf"]:
            name = option.get("$ref", "").split("/")[-1]
            target = schema["definitions"].get(name, option)
            if target.get("x-required"):
                continue
            group = target.get("x-libraryGroup")
            if group not in library_groups:
                errors.append(f"{definition} {name}: x-libraryGroup {group!r} isn't one of the schema's x-libraryGroups")

    # A module with a text field (in its file or a content part it uses) must
    # say whether the desktop hands it the keyboard: `x-keyboard`
    part_files = {f.stem: f for f in (ROOT / POPOUT_DIR / "parts").rglob("*.qml")}
    part_files.update({f.stem: f for f in (ROOT / POPOUT_DIR).glob("*/*.qml") if f.stem != f.parent.name})
    content_parts = {stem: f.read_text() for stem, f in part_files.items()}
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
        hosts = target.get("x-hosts", ["overlay", "menu", "desktop"])
        source = ROOT / POPOUT_DIR / const / f"{const}.qml"
        if "desktop" in hosts and "x-keyboard" not in target and source.exists() and typing.search(with_parts(source.read_text(), set())):
            errors.append(f"OverlayModule {const}: has a text field but no x-keyboard (true so the desktop hands it the keyboard, false to keep it read-only there)")

    # What a lock screen module may do (docs/dev/features/lockscreen.md ›
    # Which modules may go here): every `XManager.method(` call in a type
    # hosted there, or in a part it uses, is a read, one of the methods
    # its `x-lockActions` cover, or marked `// lock-inert: <reason>` on its
    # line or the one above (a call that gates itself off there)
    lock_actions = {
        "session": {"SessionManager.sessionAction"},
        "media": {f"MediaManager.{m}" for m in ("togglePlayPause", "next", "previous", "setPositionByRatio", "selectPlayer")},
        "volume": {f"AudioManager.{m}" for m in ("toggleMute", "toggleSourceMute", "stepNodeVolume")} | {"ShellManager.onScreen"},
        "layout": {"InputSourceManager.next", "InputSourceManager.prev"},
        "unlock": {"AuthManager.authenticate", "AuthManager.clearMessage", "SurfaceManager.reportRequiredField"},
    }
    lock_reads = {"acquire", "release", "wants", "formatTime", "timeText", "dayLabel", "getBatteryIcon", "offsetOf", "dotsFor", "eventsOn",
                  "ensureMonth", "avatarOf", "currentFor", "iconFor", "nameFor", "labelFor", "sourcesFor", "conditionFor", "sessionActionInfo", "refreshIp",
                  "quoteFor", "stateLabel", "history", "stateFor", "conditionOf", "detailsOf"}
    service_call = re.compile(r"\b([A-Z]\w*Manager)\.(\w+)\s*\(")

    def lock_files(path, seen):
        files = [path]
        text = path.read_text()
        # Parts loaded by URL (CustomElement's elements/<Kind>/…) count too
        by_url = {f for d in re.findall(r'Qt\.resolvedUrl\("(\w+)/', text) for f in (path.parent / d).rglob("*.qml")}
        for part, f in part_files.items():
            if part not in seen and (f in by_url or re.search(rf"\b{part}\s*\{{", text)):
                seen.add(part)
                files += lock_files(f, seen)
        return files
    for option in schema["definitions"]["OverlayModule"]["oneOf"]:
        target = schema["definitions"].get(option.get("$ref", "").split("/")[-1], option)
        const = target["properties"]["type"]["const"]
        source = ROOT / POPOUT_DIR / const / f"{const}.qml"
        if "lockscreen" not in target.get("x-hosts", []) or not source.exists():
            continue
        covered = set()
        for action in target.get("x-lockActions", []):
            if action not in lock_actions:
                errors.append(f"OverlayModule {const}: x-lockActions {action!r} isn't one of {', '.join(lock_actions)}")
            covered |= lock_actions.get(action, set())
        for f in lock_files(source, set()):
            lines = f.read_text().split("\n")
            for n, line in enumerate(lines, 1):
                if "// lock-inert:" in line or (n > 1 and "// lock-inert:" in lines[n - 2]):
                    continue
                for call in service_call.finditer(line.split("//", 1)[0]):
                    name = f"{call.group(1)}.{call.group(2)}"
                    if call.group(2) not in lock_reads and name not in covered:
                        errors.append(f"{f.relative_to(ROOT)}:{n}: {name} on the lock screen (OverlayModule {const}): not a read nor covered by its x-lockActions (or mark a call that gates itself `// lock-inert: <reason>`)")

    # Hand-built settings parts: x-card's `file` loads
    # views/Settings/<file>Card.qml, x-intro and x-row views/Settings/
    # <Name>.qml (by URL, so a typo only shows in the log); x-intro is a name
    # or { file, setup }
    def annotated(node, found):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "x-card" and isinstance(value, dict) and value.get("file"):
                    found.append((key, value["file"]))
                elif key == "x-intro" and isinstance(value, dict):
                    # { file, setup: [keys] }: every key is a property of the object
                    if not value.get("file"):
                        errors.append("schema x-intro object needs `file`")
                    else:
                        found.append((key, value["file"]))
                    for setup in value.get("setup", []):
                        if setup not in node.get("properties", {}):
                            errors.append(f"schema x-intro {value.get('file')!r}: setup key {setup!r} isn't a property of its object")
                elif key in ("x-intro", "x-row"):
                    found.append((key, value))
                annotated(value, found)
        elif isinstance(node, list):
            for value in node:
                annotated(value, found)
        return found
    for key, name in annotated(schema, []):
        target = f"qml/components/views/Settings/{name}{'Card' if key == 'x-card' else ''}.qml"
        if not (ROOT / target).exists():
            errors.append(f"schema {key} {name!r} has no {target}")

    # Every capability the schema gates on (`/$supports.<key>`, x-needs) is
    # a key of the compositor contract's Capabilities table: one no backend
    # declares greys its setting out everywhere
    contract = (ROOT / "docs/dev/compositor/contract.md").read_text()
    table = contract[contract.find("### Capabilities"):]
    listed = {key for cell in re.findall(r"^\| ([^|]+) \|", table, re.M) for key in re.findall(r"`(\w+)`", cell)}
    built = json.dumps(schema)
    gated = set(re.findall(r'"/\$supports\.(\w+)"', built)) | set(re.findall(r'"x-needs": "(\w+)"', built))
    for key in sorted(gated - listed):
        errors.append(f"schema gates on supports.{key}, which docs/dev/compositor/contract.md › Capabilities doesn't list")

    # Tool pages (x-tool) are always in config: the Overlay.items default
    # carries every one (and a migration adds a new one to existing configs)
    default_views = {v.get("type") for v in schema["properties"]["Overlay"]["properties"]["items"]["default"]}
    for option in schema["definitions"]["OverlayView"]["oneOf"]:
        target = schema["definitions"].get(option.get("$ref", "").split("/")[-1], option)
        if target.get("x-tool"):
            const = target["properties"]["type"]["const"]
            if const not in default_views:
                errors.append(f"tool page {const} isn't in the Overlay.items default")

    # An IpcTarget's arguments arrive as the command line's text, which a
    # typed parameter converts without refusing anything (`int` makes a word
    # 0, `bool` makes "false" true): they're strings, read through _int
    for path, text in sources.items():
        for start, body in qml_blocks(text, "IpcTarget"):
            for fn in re.finditer(r"function\s+(\w+)\s*\(([^)]*)\)", body):
                typed = re.findall(r"(\w+)\s*:\s*(\w+)", fn.group(2))
                for name, kind in typed:
                    if kind != "string":
                        line = text.count("\n", 0, start + fn.start()) + 1
                        errors.append(f"{path}:{line}: IPC function {fn.group(1)}'s {name} is {kind}: take a string "
                                      "(arguments arrive as text; a number through _int, services/core/IpcTarget.qml)")

    # Every file says what it's for above its root object (docs/dev/generated/files.md)
    for path, text in sources.items():
        lines = text.split("\n")
        start = next((i for i, line in enumerate(lines) if re.match(r"[A-Z][\w.]*\s*\{", line)), None)
        if start is None:
            continue
        j = start - 1
        while j >= 0 and not lines[j].strip():
            j -= 1
        if j >= 0 and lines[j].rstrip().endswith("*/"):
            errors.append(f"{path}: a /* */ purpose comment: write it as // lines")
        elif j < 0 or not lines[j].startswith("//"):
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

    # qs.* imports resolve
    for path, text in sources.items():
        for m in re.finditer(r"^import (qs(?:\.\w+)+)", text, re.M):
            target = module_dir(m.group(1))
            if not target.is_dir():
                errors.append(f"{path}: import {m.group(1)} — no such directory")

    # Likewise only a backend's own services talk to its compositor: run its
    # CLI, use its socket or its services directly
    # (docs/dev/compositor/README.md): (prefix, the compositor, what talks to it)
    backends = [
        ("Sway", "sway", r"\bSwayManager\.|\bSwayIpcManager\.|\"swaymsg\""),
        ("Niri", "niri", r"\bNiriManager\.|\"NIRI_SOCKET\"|\[\"niri\","),  # its CLI: ["niri", "msg", …]
    ]
    for prefix, name, talks in backends:
        for path, text in sources.items():
            # (CompositorKind names the variables that say which one runs)
            if re.fullmatch(rf"qml/services/compositor/{prefix}\w*\.qml", path) or path in ("qml/services/compositor/CompositorManager.qml", "qml/components/methods/CompositorKind.qml"):
                continue
            code = "\n".join(line.split("//", 1)[0] for line in text.splitlines())
            if re.search(talks, code):
                errors.append(f"{path}: talks to {name} directly (only the {prefix}* services may; use CompositorManager)")

    # The rest of the shell reaches the compositor through CompositorManager
    # (docs/dev/compositor/README.md). HyprlandManager is its Hyprland
    # backend: besides the Hyprland* services, only CompositorManager uses it.
    facade = "qml/services/compositor/CompositorManager.qml"
    for path, text in sources.items():
        code = "\n".join(line.split("//", 1)[0] for line in text.splitlines())
        if re.search(r"\bHyprlandManager\.", code) and not re.fullmatch(r"qml/services/compositor/Hyprland\w*\.qml", path) and path != facade:
            errors.append(f"{path}: uses HyprlandManager (only the Hyprland* services and CompositorManager may; use CompositorManager)")

    # A backend's state helpers are its own (HyprState, SwayState,
    # NiriState): outside its services and helpers, the rest of the shell
    # goes through CompositorManager and CompositorConfigManager
    # (docs/dev/compositor/config-modes.md)
    for path, text in sources.items():
        code = "\n".join(line.split("//", 1)[0] for line in re.sub(r"/\*.*?\*/", "", text, flags=re.S).splitlines())
        if not path.startswith(("qml/services/", "qml/components/", "qml/shell/", "qml/config/")):
            continue
        if not re.fullmatch(r"qml/(services/compositor|components/methods(/\w+)?)/Hypr\w*\.qml", path) and re.search(r"\bHyprState\.", code):
            errors.append(f"{path}: uses a Hyprland helper (only the Hyprland* services and helpers may; go through CompositorManager / CompositorConfigManager)")
        for prefix, name, _ in backends:
            if not re.fullmatch(rf"qml/(services/compositor|components/methods(/\w+)?)/{prefix}\w*\.qml", path) and re.search(rf"\b{prefix}State\.", code):
                errors.append(f"{path}: uses a {name} helper (only the {prefix}* services and helpers may; go through CompositorManager / CompositorConfigManager)")

    # Singleton references: FooManager. must be a service, and a near-miss
    # of any project singleton (AudioManger.) is a typo
    external = {"ToplevelManager"}  # Quickshell's own
    singletons = {f.stem for d in ("services/*", "config", "components/methods/**") for f in QML_ROOT.glob(f"{d}/*.qml")}
    services = {f.stem for f in QML_ROOT.glob("services/*/*.qml")} | external
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
    # (CLAUDE.md › UI): a model re-evaluated per sample once
    # pushed qs past 25 GB. Live means a member of a polled service (one
    # polling through an OwnerRegistry or DeadlineTicker, not
    # BackendManager's or NotesManager's acquire()), read in the expression
    # or through one property of the same file; a model's live set also
    # holds the arrays a push service (one calling BackendManager.listen)
    # assigns per push (any `var` or `list` member it assigns: an
    # approximation). A model may count one
    # (`.length`, `.count`: an int notifies only when it changes); a request
    # may not read one at all
    polled = set()
    pushed = {}
    for f in QML_ROOT.glob("services/*/*.qml"):
        text = f.read_text()
        if re.search(r"\b(?:OwnerRegistry|DeadlineTicker)\s*\{", text):
            polled.add(f.stem)
        code = re.sub(r"//[^\n]*", "", text)
        if "BackendManager.listen(" in code:
            pushed[f.stem] = {m for m in re.findall(r"\bproperty\s+(?:var|list<[^>]*>)\s+(\w+)", code)
                              if re.search(rf"(?<![\w.])(?<!let )(?<!const )(?<!var )(?:root\.)?{m}\s*=(?![=>])", code)}
    chain = re.compile(r"(?<![\w.])(?:root\.)?([A-Za-z_]\w*)((?:\??\.\w+)*)")

    def live_reads(expr, props, counts, depth=0):
        found = []
        for m in chain.finditer(expr):
            name, members = m.group(1), re.findall(r"\w+", m.group(2))
            if (expr[m.end():m.end() + 1] == "(" and len(members) < 2) or (counts and members[-1:] in (["length"], ["count"])):
                continue
            if name in polled and members and members[0] not in ("acquire", "release"):
                found.append(f"{name}.{members[0]}")
            elif counts and members[:1] and members[0] in pushed.get(name, ()):
                found.append(f"{name}.{members[0]}")
            elif name in props and not depth:
                found += [f"{name} → {r}" for r in live_reads(props[name], props, counts, 1)]
        return found
    for path, text in sources.items():
        if not path.startswith(("qml/components/", "qml/shell/")):
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

    # Dates the user reads follow the language: I18n.formatDate(date,
    # I18n.dateFormat(name)), never Qt.formatDateTime (CLAUDE.md › Theme, animation, text).
    # A use that must stay says why on its line
    for path, text in sources.items():
        if path.startswith("tests/"):
            continue
        for n, line in enumerate(text.split("\n"), 1):
            code = line.split("//")[0]
            if "// allowed:" in line:
                continue
            if re.search(r"\bQt\.format(?:DateTime|Date|Time)\(", code):
                errors.append(f"{path}:{n}: Qt.formatDateTime: format dates through I18n.formatDate(date, I18n.dateFormat(name)) (or mark a use that must stay `// allowed: <reason>`)")

    # A property named on<X> next to a property, signal or function <x> (in
    # its file, or inherited from the Qt types the shell builds on) never
    # takes its value: it reads the type's default (qml-pitfalls.md)
    windows = {"PanelWindow", "Window", "FloatingWindow", "PopupWindow", "WlrLayershell"}
    inherited = {"width", "height", "visible", "color", "enabled", "focus", "opacity", "scale", "rotation", "clip", "parent", "state", "text", "x", "y", "z"}
    for path, text in sources.items():
        if path.startswith("tests/"):
            continue
        for m in re.finditer(r"^\s*(?:readonly\s+|required\s+)?property\s+[\w.<>]+\s+on([A-Z]\w*)", text, re.M):
            low = m.group(1)[0].lower() + m.group(1)[1:]
            own = re.search(r"(?:\bproperty\s+[\w.<>]+\s+|\bsignal\s+|\bfunction\s+)" + low + r"\b", text)
            root_type = re.search(r"^([A-Z]\w*)\s*\{", text, re.M)
            if own or low in inherited or (low == "screen" and root_type and root_type.group(1) in windows):
                errors.append(f"{path}:{text.count(chr(10), 0, m.start()) + 1}: property on{m.group(1)} beside `{low}`: a QML on<X> property next to <x> never takes its value; name it otherwise")

    # One way to run an action: the UI runs a catalogue action through
    # ActionsManager.run (docs/dev/core/actions.md), never its service's
    # toggle, so a tile, a command, an OSD icon and a key run the same code
    action_toggles = r"\b(?:NetworkingManager\.(?:toggleWifi|setWifiEnabled|setAirplane)|BluetoothManager\.(?:toggleEnabled|setEnabled)|IdleManager\.(?:toggle|setCaffeine)|NotificationManager\.(?:toggleDnd|setDnd)|NightLightManager\.(?:toggle|setActive)|ThemeManager\.(?:toggleDarkMode|setLightMode)|AudioManager\.(?:toggleMute|toggleSourceMute)|VpnManager\.toggleLast|ScreenshotManager\.(?:toggleRecording|stopRecording)|BatteryManager\.setPowerSaver|SessionManager\.sessionAction|NotificationManager\.clearAll|MonitorManager\.identify|ScreenshotManager\.take|PomodoroManager\.(?:toggle|skip|stop)|StopwatchManager\.(?:toggleStopwatch|lap|resetStopwatch|toggleTimer|resetTimer)|MediaManager\.(?:togglePlayPause|next|previous|stop)|InputSourceManager\.(?:next|prev)|ShellManager\.runAction)\("
    for path, text in sources.items():
        if not path.startswith(("qml/components/", "qml/shell/")):
            continue
        for n, line in enumerate(text.split("\n"), 1):
            m = re.search(action_toggles, line.split("//")[0])
            if m and "// allowed:" not in line:
                errors.append(f"{path}:{n}: {m.group(0)[:-1]}: run the action through ActionsManager.run(id, {{fromScreen: true}}) (or mark a use that must stay `// allowed: <reason>`)")

    # What a bar widget style is lives in BarLook's trait table alone
    # (.claude/rules/bar.md, docs/dev/bar/widget-style.md): nothing
    # else reads the style's name, the saved `widgetStyle` or the resolved
    # look's `style`, to compare it; it reads the look's traits. (Comparing
    # a name like "outline" can't be told from other uses of the word, so
    # the check is on where the name comes from.) Tests build looks from
    # BarStyle keys.
    for path, text in sources.items():
        if path.startswith("tests/") or path == "qml/components/methods/BarLook.qml":
            continue
        for n, line in enumerate(text.split("\n"), 1):
            m = re.search(r"\bwidgetStyle\b|\blook\.style\b", line.split("//")[0])
            if m and "// allowed:" not in line:
                errors.append(f"{path}:{n}: reads `{m.group(0)}`: a style is BarLook's alone; read the look's traits (or mark a use that must stay `// allowed: <reason>`)")

    bar_widget_template(schema, sources, errors)
    popout_modules(schema, sources, errors)
    layer_service(sources, errors)

    # Readers: the schema fills every default, so `_c.key ?? x` is dead
    for path, text in sources.items():
        if not path.startswith("qml/config/"):
            continue
        for n, line in enumerate(re.sub(r"//[^\n]*", "", text).splitlines(), 1):
            m = re.search(r"\b_c(?:\.\w+)+\s*\?\?", line)
            if m:
                errors.append(f"{path}:{n}: `{m.group(0)}`: readers use no ?? fallback (the schema default is filled at load)")

    # A type instantiated from two directories a file can see would depend
    # on import order (bar widgets and content share some names by design)
    dir_types = {}
    for f in qml_files():
        if rel(f).startswith(("qml/components/", "qml/shell/")):
            dir_types.setdefault(module_of(rel(f.parent)), set()).add(f.stem)
    for path, text in sources.items():
        own = module_of(Path(path).parent)
        visible = [d for d in set(re.findall(r"^import (qs(?:\.\w+)+)", text, re.M)) | {own} if d in dir_types]
        code = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', re.sub(r"//[^\n]*", "", text))
        for name in sorted(set(re.findall(r"(?<![\w.])([A-Z]\w+)\s*\{", code)) - {Path(path).stem}):
            sources_of = [d for d in visible if name in dir_types[d]]
            if len(sources_of) > 1:
                errors.append(f"{path}: {name} is defined in {' and '.join(sorted(sources_of))}; import only one")

    try:
        errors.extend(hit_errors + qml_modules.ratchet(named, BASELINE, base, qml_modules.new_rules(base, SELF, RULES),
                                                                        unlisted=lambda f, r, s: said.get((f, s)) if r == "quickshell-use" else None))
    except ValueError as e:
        errors.append(str(e))
    for e in errors:
        print(f"error    {e}")
    for line in qml_modules.rule_statements(errors, RULES):
        print(f"error    {line}")
    for w in warnings:
        print(f"warning  {w}")
    if not errors and not warnings:
        print("structure ok")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
