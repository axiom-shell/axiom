#!/usr/bin/env python3
"""Smoke tests for the scripts in scripts/, each run in a scratch $HOME.

  - every shipped theme is complete (qml/config/themes/theme.schema.json's
    required keys, hex colors, semantic names that resolve, pairs that exist)
  - the Neovim module Apply copies compiles and maps the shipped themes
  - check_sizes.py finds sizes written as numbers, skipping hairlines
  - check_style.py: every style rule on a fixture file, its waivers, scope, every-hit-fails and role check
  - check_icons.py finds icon names the bundled font doesn't have
  - only PAM's success unlocks the built-in lock screen
  - the Daily habits script (data/custom-widgets/habits.sh): add, check,
    streaks, undo, remove, bad ids, JSON, overlapping changes
  - new_names.py lists a branch's added names: also defined, moved, components, schema keys,
    similar strings, .js names under tests/, generated paths skipped
  - the ratchet (qml_modules.ratchet and its helpers, in a scratch git repo) and the engine manifest reader
    (manifests.py), on small inputs
  - check_engines.py: each of its thirteen rules on the fixture engine `demo` (demo_engine), the base it reads
  - gen_docs.py's engine pages: the fixture engines' manifest, API and rules pages, and an empty manifest's one page
  - each check fails on what it catches: a copy of the tree (fixture_root)
    with one breaking file or edit per rule, and the message it must print

  python3 tests/scripts/test_scripts.py [-v] [TestCase[.test_name]]
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPTS = ROOT / "scripts"
THEMES = ROOT / "qml" / "config" / "themes"
BASES = [f"base0{c}" for c in "0123456789ABCDEF"]
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def scratch_env(tmp):
    """Environment with $HOME and XDG dirs under `tmp`."""
    tmp = Path(tmp)
    env = dict(os.environ)
    env.update({
        "HOME": str(tmp / "home"),
        "XDG_CONFIG_HOME": str(tmp / "home" / ".config"),
        "XDG_STATE_HOME": str(tmp / "home" / ".local" / "state"),
        "XDG_DATA_HOME": str(tmp / "home" / ".local" / "share"),
        "XDG_RUNTIME_DIR": str(tmp / "run"),
        "GIT_CONFIG_GLOBAL": str(tmp / "gitconfig"),
        "GIT_CONFIG_NOSYSTEM": "1",
    })
    for key in ("HOME", "XDG_RUNTIME_DIR"):
        Path(env[key]).mkdir(parents=True, exist_ok=True)
    return env


def git(repo, tmp, *args):
    """Run git in `repo` under a scratch environment; its stdout, stripped."""
    done = subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args], cwd=repo,
                          env=scratch_env(tmp), check=True, capture_output=True, text=True)
    return done.stdout.strip()


def write(root, path, text):
    """Write `text` to `path` under `root`, making its folders."""
    f = Path(root) / path
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(text)


def fixture_root(tmp, *paths):
    """A copy of scripts/ and these repo paths under tmp. A check run from
    the copy checks the copy (each script finds the root from its own path),
    so a test breaks the copy and asserts the check says so."""
    tmp = Path(tmp)
    for p in ("scripts",) + paths:
        src, dst = ROOT / p, tmp / p
        dst.parent.mkdir(parents=True, exist_ok=True)
        if src.is_dir():
            shutil.copytree(src, dst, ignore=shutil.ignore_patterns("__pycache__"))
        else:
            shutil.copy2(src, dst)
    return tmp


def run_check(root, script, *args, files=()):
    """Write `files` ((path, text) pairs) into root, run scripts/<script>
    there; its exit code and output."""
    for path, text in files:
        write(root, path, text)
    done = subprocess.run([sys.executable, str(root / "scripts" / script), *args],
                          cwd=root, capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def edit_json(path, change):
    data = json.loads(path.read_text())
    change(data)
    path.write_text(json.dumps(data, indent=2))


def qml(body="", imports="", head="pragma ComponentBehavior: Bound", purpose="// A fixture."):
    return f"{head}\nimport QtQuick\n{imports}\n{purpose}\nItem {{\n    {body}\n}}\n"


def widget(body):
    return f"pragma ComponentBehavior: Bound\nimport QtQuick\nimport qs.components.bar.widgets.base\n// A fixture.\nBarWidget {{\n  {body}\n}}\n"


def planted(path, line):
    """The real file's text with `line` after its root's opening line, and
    the number that line gets."""
    text = (ROOT / path).read_text()
    marker = "BarWidget {\n"
    at = text.index(marker) + len(marker)
    return text[:at] + line + text[at:], text.count("\n", 0, at) + 1


def missed(out, fragments):
    """The fragments no line of a check's output contains."""
    return [f for f in fragments if not any(f in line for line in out.splitlines())]


def theme_problems(theme, names):
    problems = []
    for key in ("name", "variant", "colors", "semantic"):
        if key not in theme:
            problems.append(f"missing {key}")
    if theme.get("variant") not in ("dark", "light"):
        problems.append(f"variant {theme.get('variant')!r}")
    colors = theme.get("colors", {})
    for base in BASES:
        if not HEX.match(colors.get(base, "")):
            problems.append(f"colors.{base} = {colors.get(base)!r}")
    for key, value in theme.get("semantic", {}).items():
        if value not in BASES and not HEX.match(value):
            problems.append(f"semantic.{key} = {value!r}")
    if theme.get("paired") and theme["paired"] not in names:
        problems.append(f"paired theme {theme['paired']!r} doesn't exist")
    return problems


class Themes(unittest.TestCase):
    def test_shipped_themes_are_complete(self):
        files = sorted(THEMES.glob("*.json")) + sorted((THEMES / "generated").glob("*.json"))
        files = [f for f in files if f.name != "theme.schema.json"]
        names = {json.loads(f.read_text()).get("name") for f in files} | {f.stem for f in files}
        schema = json.loads((THEMES / "theme.schema.json").read_text())
        required = schema["properties"]["semantic"]["required"]
        self.assertGreater(len(files), 2)
        for f in files:
            with self.subTest(theme=f.name):
                theme = json.loads(f.read_text())
                self.assertEqual(theme_problems(theme, names), [])
                missing = [k for k in required if k not in theme["semantic"]]
                self.assertEqual(missing, [], "semantic keys missing")

    def test_theme_defaults_are_complete(self):
        defaults = json.loads((ROOT / "qml" / "config" / "json" / "theme-defaults.json").read_text())
        for base in BASES:
            self.assertRegex(defaults["colors"][base], HEX)
        for variant in ("dark", "light"):
            for key, value in defaults["semantic"][variant].items():
                self.assertIn(value, BASES, f"{variant}.{key}")

    def test_template_is_current_and_complete(self):
        result = subprocess.run([sys.executable, str(SCRIPTS / "gen_theme_template.py"), "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        template = json.loads((THEMES / "template" / "theme.json").read_text())
        schema = json.loads((THEMES / "theme.schema.json").read_text())
        self.assertEqual([k for k in schema["required"] if k not in template], [])
        self.assertEqual([k for k in schema["properties"]["semantic"]["required"] if k not in template["semantic"]], [])
        for base in BASES:
            self.assertRegex(template["colors"][base], HEX)

    def test_style_fixture_lists_every_theme(self):
        # tests/fixtures/style/themes.json is what tst_StyleTokens sweeps
        # (a QML test can't list a folder)
        listed = json.loads((ROOT / "tests" / "fixtures" / "style" / "themes.json").read_text())
        stems = sorted(f.stem for f in THEMES.glob("*.json") if f.name != "theme.schema.json")
        self.assertEqual(sorted(listed), stems)


class StyleLayer(unittest.TestCase):
    """qml/config/Style.qml is built on the lock screen and in the greeter, so
    it reads nothing beyond the Style import list (docs/dev/core/style.md)"""
    ALLOWED = {"ThemeManager", "Theme", "Appearance", "Widget", "StyleTokens", "Tone", "StyleInk",
               "StyleTextRole", "Style", "QtObject", "Qt", "Font", "Math", "console", "Date"}

    def test_style_imports(self):
        text = (ROOT / "qml" / "config" / "Style.qml").read_text()
        text = re.sub(r"//[^\n]*", "", text)
        text = re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)
        used = set(re.findall(r"\b([A-Z][A-Za-z0-9]*|console)\b(?=\s*[.{])", text))
        self.assertEqual(sorted(used - self.ALLOWED), [])
        # every *Manager but ThemeManager, the bar's config and the compositor layer stay out
        self.assertNotRegex(text, r"\b(BarStyle|BarsConfig|CompositorManager|(?!ThemeManager\b)\w+Manager)\b")


class NvimModule(unittest.TestCase):
    """The axiom_theme Lua module Apply copies into a Neovim config"""
    def test_nvim_module_compiles(self):
        luac = shutil.which("luac")
        if not luac:
            self.skipTest("no luac")
        module = ROOT / "data" / "templates" / "nvim" / "axiom_theme.lua"
        result = subprocess.run([luac, "-p", str(module)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_nvim_module_maps_shipped_themes(self):
        text = (ROOT / "data" / "templates" / "nvim" / "axiom_theme.lua").read_text()
        mapped = set(re.findall(r'^\s*\["([\w-]+)"\] = scheme\(', text, re.M))
        shipped = {p.stem for p in THEMES.glob("*.json")} - {"theme.schema"}
        self.assertEqual(mapped - shipped, set(), "map entries without a theme")
        self.assertEqual(shipped - mapped - {"submarine-sonar", "submarine-sonar-light", "nord-light", "alucard"},
                         set(), "themes without a map entry")


class RpcShapes(unittest.TestCase):
    """scripts/gen_docs.py checks the keys of object-literal params against
    the daemon's shapes (rpc-shapes.json)."""

    SHAPE = {"kind": "object", "fields": [
        {"name": "zones", "shape": {"kind": "array", "elem": {"kind": "string"}}},
        {"name": "opts", "omitempty": True, "shape": {"kind": "object", "type": "x.Opts", "fields": [
            {"name": "on", "shape": {"kind": "bool"}}]}},
        {"name": "extra", "shape": {"kind": "map", "elem": {"kind": "number"}}}]}

    def test_call_sites(self):
        sys.path.insert(0, str(SCRIPTS))
        from gen_docs import qml_call_sites
        qml = "\n".join([
            "function f() {",
            '  BackendManager.call("tz.offsets", {',
            "    zones: list, // a comment, with a comma",
            '    "opts": {on: `${a}, b`}',
            "  }, (e, r) => g(r));",
            "  BackendManager.call(method, params);",
            '  root._send(JsonRpc.request(id, "daemon.hello", {pid: 1}));',
            "}",
        ])
        self.assertEqual([(line, method, src.split("\n")[0]) for line, method, src in qml_call_sites(qml)],
                         [(2, "tz.offsets", "{"), (6, None, "params"), (7, "daemon.hello", "{pid: 1}")])

    def test_helper_sites(self):
        sys.path.insert(0, str(SCRIPTS))
        from gen_docs import qml_helper_sites
        qml = "\n".join([
            '  function copy() { root._send("1", "x.a", {id: 1}); _send("2", "x.b"); _send(n, other, {}) }',
            "  // rpc: x.a, x.b",
            "  // sends one",
            "  function _send(name, method, params) {",
            "  }",
            "  // rpc: x.c",
            "  property var notAFunction: 1",
        ])
        self.assertEqual(qml_helper_sites(qml), [(1, "x.a", "{id: 1}"), (1, "x.b", ""), (6, "(through a helper) x.c", "")])

    def test_helper_lines(self):
        sys.path.insert(0, str(SCRIPTS))
        from gen_docs import qml_helper_lines
        qml = "\n".join([
            "  // rpc: x.a",
            "  function _send(method, params) {",
            "    BackendManager.call(method, params);",
            "  }",
            "  BackendManager.call(method, params);",
            "  // rpc: unchecked (not a helper note)",
            "  function other(method) {",
            "  }",
        ])
        self.assertEqual(qml_helper_lines(qml), {2, 3, 4})

    def test_unreadable_calls_need_a_mark(self):
        sys.path.insert(0, str(SCRIPTS))
        from gen_docs import qml_marked_calls
        qml = "\n".join([
            '  BackendManager.call("a.b", built); // rpc: unchecked (built elsewhere)',
            "  // rpc: unchecked (named at runtime)",
            "  BackendManager.call(method, {});",
            '  BackendManager.call("a.c", other);',
            "  // rpc: unchecked (stale)",
            '  BackendManager.call("a.d", {id: 1});',
            "  const x = 1;",
            '  BackendManager.call("a.e", more); // rpc: unchecked ()',
        ])
        unreadable = [(1, "a.b", "built"), (3, None, "{}"), (4, "a.c", "other"), (8, "a.e", "more")]
        marked, problems = qml_marked_calls(qml, unreadable)
        self.assertEqual(marked, [(1, "a.b", "built", "built elsewhere"), (3, None, "{}", "named at runtime")])
        self.assertEqual([line for line, _ in problems], [4, 8, 5])
        self.assertIn("can't read a.c's params (other)", problems[0][1])
        self.assertIn("marks no call", problems[2][1])

    def test_a_mark_is_no_helper_note(self):
        sys.path.insert(0, str(SCRIPTS))
        from gen_docs import QML_RPC_NOTE
        self.assertIsNone(QML_RPC_NOTE.search("// rpc: unchecked (a reason, with a comma)"))
        self.assertEqual(QML_RPC_NOTE.search("// rpc: a.b, c.d").group(1), "a.b, c.d")

    def test_callback_reads(self):
        sys.path.insert(0, str(SCRIPTS))
        from gen_docs import qml_callback_reads
        qml = "\n".join([
            '  BackendManager.call("a.b", {}, (error, result) => f(result.name, result?.path, other.result.x));',
            '  BackendManager.call("a.c", {}, error => g(error.message));',
            '  BackendManager.call("a.d", {}, done);',
            '  BackendManager.listen("a.state", state => { root.x = state.repo; });',
        ])
        self.assertEqual(qml_callback_reads(qml), [(1, "call", "a.b", "result", ["name", "path"]),
                                                   (4, "listen", "a.state", "state", ["repo"])])

    def test_unknown_keys_fail(self):
        sys.path.insert(0, str(SCRIPTS))
        from gen_docs import shape_key_problems
        self.assertEqual(shape_key_problems("{zones, opts: {on: true}, extra: {any: 1}}", self.SHAPE, "m"), [])
        self.assertEqual(shape_key_problems("{zone: [], opts: {off: 1}}", self.SHAPE, "m"),
                         ["m has no key 'zone' (it takes: extra, opts, zones)",
                          "m.opts has no key 'off' (it takes: on)"])
        # A spread or a computed key can't be checked
        self.assertEqual(shape_key_problems("{...base, nope: 1}", self.SHAPE, "m"), [])
        self.assertEqual(shape_key_problems("{[k]: 1}", self.SHAPE, "m"), [])

    def test_render(self):
        sys.path.insert(0, str(SCRIPTS))
        from gen_docs import render_shape
        types = {}
        self.assertEqual(render_shape(self.SHAPE, types), "{zones: [string], opts?: x.Opts, extra: {[key]: number}}")
        self.assertEqual(list(types), ["x.Opts"])


class ConfigUsage(unittest.TestCase):
    """scripts/gen_docs.py maps each setting to the reader members and files
    reading it, and fails on one nobody reads."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(SCRIPTS))
        from gen_docs import load_readers, Usage, ConfigReference
        cls.readers = load_readers()
        cls.ref = ConfigReference({}, cls.readers, Usage())

    def test_reader_member_found(self):
        self.assertEqual(self.ref.members_for("WorkspaceOverlay.showHint"),
                         [("WorkspaceOverlayConfig", "showHint", "exact")])
        self.assertTrue(self.ref.member_users[("WorkspaceOverlayConfig", "showHint")])

    def test_bar_style_is_read_through_the_look(self):
        # A BarStyle key reaches widgets in each bar's look (BarLook.resolve
        # reads it from the merged values); the shadow stays flat on barConfig
        def read(path):
            return "\n".join(self.ref.leaf_line(path, {"type": "string"}, "leaf"))
        for path in ("Bars.style.widgetStyle", "Bars.items[].style.tintOpacity"):
            self.assertIn("`barConfig.look`", read(path), path)
            self.assertIn("qml/components/methods/BarLook.qml", read(path), path)
        self.assertIn("`barConfig.shadowColor`", read("Bars.style.shadow.color"))
        self.assertIn("`barConfig.thickness`", read("Bars.items[].thickness"))

    def test_alias_of_a_section(self):
        # `_c: ConfigManager.live.Appearance` stands for that section
        self.assertIn("Appearance.surface.blur.throughWindows",
                      self.readers["Appearance"]["members"]["blurThroughWindows"]["paths"])

    def test_used_inside_the_reader(self):
        # The `.x` of its own `_c.x` binding is the key, not a use
        from gen_docs import used_inside
        self.assertFalse(used_inside("R", "x", "property bool x: _c.x"))
        self.assertTrue(used_inside("R", "x", "property bool x: _c.x\nproperty bool y: x && _c.y"))
        self.assertTrue(used_inside("R", "x", "property bool x: _c.x\nfunction f() { return root.x }"))
        self.assertTrue(used_inside("R", "x", "property bool x: _c.x\nfunction f() { return R.x }"))

    def test_spread_reads_a_member(self):
        from gen_docs import Usage
        usage = Usage()
        usage.files = {"a.qml": "[].concat(...R.x.map(f))", "b.qml": "foo.R.y"}
        self.assertEqual(usage.member("R", "x", ""), ["a.qml"])
        self.assertEqual(usage.member("R", "y", ""), [])

    def test_missing_member_fails(self):
        # A read the reader lacks fails; a config path in a string or a
        # block comment isn't a read
        from gen_docs import Usage
        usage = Usage()
        usage.files = {"a.qml": 'f(R.x, R.gone)\n/* R.prose */\nset("R.path", `R.tpl ${R.inTpl}`)'}
        self.assertEqual(usage.missing({"R": {"members": {"x": {}}}}), ["a.qml: R.gone", "a.qml: R.inTpl"])


DEV_MODE, DEV_MODE_AT = planted("qml/components/bar/widgets/DevMode/DevMode.qml", "  property color planted: Theme.error\n")
LOCK_KEYS, LOCK_KEYS_AT = planted("qml/components/bar/widgets/LockKeys/LockKeys.qml", "  opacity: .4\n")


class CheckStructure(unittest.TestCase):
    """scripts/check_structure.py fails on each rule's breaking file, in a
    copy of the shell: (file written, what the check must say)."""

    FILES = [
        ("qml/components/views/Stray.qml", qml(), "qml/components/views/Stray.qml: a root holds only type folders"),
        ("qml/components/views/Empty/Other.qml", qml(), "qml/components/views/Empty/: a type folder without Empty.qml"),
        ("qml/components/lonely/Lonely.qml", qml(), None),
        ("qml/components/views/Reach/Reach.qml", qml(imports="import qs.components.lonely"),
         "Reach.qml needs qs.components.lonely, which no file reached from shell.qml imports"),
        # (Reach is also no OverlayView type and nothing uses it: the warning below)
        ("qml/services/core/Spawner.qml", qml("Process {}"), "qml/services/core/Spawner.qml: uses Process directly"),
        ("qml/services/Direct.qml", qml(), "qml/services/Direct.qml: directly in services/"),
        ("qml/shell/Handler.qml", qml("IpcHandler {}"), "qml/shell/Handler.qml: an IpcHandler"),
        ("qml/shell/OptCall.qml", qml("function f(x, k) { return x[k]?.() }"), "an optional call on a computed member"),
        ("qml/shell/FromEntries.qml", qml("function f(x) { return Object.fromEntries(x) }"), "Object.fromEntries or flatMap"),
        ("qml/shell/FlatMap.qml", qml("function f(x) { return x.flatMap(y => y) }"), "Object.fromEntries or flatMap"),
        ("qml/shell/IntArg.qml", qml('IpcTarget {\n    target: "brightness"\n    function set(percent: int): void {}\n  }'),
         "qml/shell/IntArg.qml:8: IPC function set's percent is int: take a string"),
        ("qml/shell/OnClash.qml", qml("property bool battery: false\n    readonly property bool onBattery: true"),
         "qml/shell/OnClash.qml:7: property onBattery beside `battery`"),
        ("qml/shell/OnInherited.qml", qml("readonly property bool onWidth: true"), "qml/shell/OnInherited.qml:6: property onWidth beside `width`"),
        ("qml/shell/NoPurpose.qml", qml(purpose=""), "qml/shell/NoPurpose.qml: no purpose comment"),
        ("qml/shell/Popout.qml", qml('PopoutAnchor { popoutName: "Ghost" }'), 'popoutName "Ghost" has no qml/components/content/Ghost/Ghost.qml'),
        ("qml/components/content/Unused/Unused.qml", qml(), "qml/components/content/Unused/: not an overlay module"),
        ("qml/components/widgets/Old.qml", qml(), "qml/components/widgets/Old.qml: lives under retired"),
        ("qml/shell/NoPragma.qml", qml(head=""), "qml/shell/NoPragma.qml: doesn't start with pragma"),
        ("qml/shell/BadImport.qml", qml(imports="import qs.nowhere"), "import qs.nowhere — no such directory"),
        ("qml/shell/Hypr.qml", qml(imports="import Quickshell.Hyprland"), "qml/shell/Hypr.qml: imports Quickshell.Hyprland"),
        ("qml/shell/I3.qml", qml(imports="import Quickshell.I3"), "qml/shell/I3.qml: imports Quickshell.I3"),
        ("qml/shell/Blue.qml", qml(imports="import Quickshell.Bluetooth"), "qml/shell/Blue.qml: imports Quickshell.Bluetooth"),
        ("qml/shell/Swaymsg.qml", qml('property var c: ["swaymsg"]'), "qml/shell/Swaymsg.qml: talks to sway directly"),
        ("qml/shell/NiriCli.qml", qml('property var c: ["niri", "msg"]'), "qml/shell/NiriCli.qml: talks to niri directly"),
        ("qml/shell/Hyprm.qml", qml("property var w: HyprlandManager.windows"), "qml/shell/Hyprm.qml: uses HyprlandManager"),
        ("qml/shell/HState.qml", qml("property var s: HyprState.parse"), "qml/shell/HState.qml: uses a Hyprland helper"),
        ("qml/shell/SState.qml", qml("property var s: SwayState.parse"), "qml/shell/SState.qml: uses a sway helper"),
        ("qml/shell/NState.qml", qml("property var s: NiriState.parse"), "qml/shell/NState.qml: uses a niri helper"),
        ("qml/shell/NotService.qml", qml("property var s: GhostManager.x"), "GhostManager is not a service"),
        ("qml/shell/Typo.qml", qml("property var s: AudioManger.x"), "AudioManger — did you mean AudioManager?"),
        ("qml/config/GhostConfig.qml", qml("readonly property int k: _c.key ?? 1", head="pragma Singleton"),
         "`_c.key ??`: readers use no ?? fallback"),
        ("qml/shell/LiveModel.qml", qml("Repeater { model: SystemManager.processes }"),
         "qml/shell/LiveModel.qml:6: a Repeater model from live values (SystemManager.processes)"),
        ("qml/shell/LiveRequest.qml", qml("readonly property var req: ({ top: SystemManager.cpu })\n    onReqChanged: SystemManager.acquire(this, req)"),
         "an acquire() request from live values (req → SystemManager.cpu)"),
        ("qml/shell/Stamp.qml", qml('property string s: Qt.formatDateTime(new Date(), "ddd")'), "qml/shell/Stamp.qml:6: Qt.formatDateTime"),
        ("qml/shell/Screens.qml", qml("property var s: Quickshell.screens"), "qml/shell/Screens.qml:6: Quickshell.screens"),
        ("qml/shell/Toggle.qml", qml("function f() { NotificationManager.toggleDnd() }"),
         "qml/shell/Toggle.qml:6: NotificationManager.toggleDnd: run the action through ActionsManager.run"),
        ("qml/shell/Corner.qml", qml('function f() { ShellManager.runAction("lock", "", "toggle") }'),
         "qml/shell/Corner.qml:6: ShellManager.runAction: run the action through ActionsManager.run"),
        ("qml/shell/StyleName.qml", qml('property bool boxed: barConfig.look.style === "filled"'),
         "qml/shell/StyleName.qml:6: reads `look.style`: a style is BarLook's alone"),
        ("qml/shell/SavedStyle.qml", qml('property bool boxed: BarStyle.values.widgetStyle !== "plain"'),
         "qml/shell/SavedStyle.qml:6: reads `widgetStyle`: a style is BarLook's alone"),
        ("qml/components/content/ColorSwatch/ColorSwatch.qml", qml('Component.onCompleted: CommandManager.run(["true"])'),
         "qml/components/content/ColorSwatch/ColorSwatch.qml:6: CommandManager.run on the lock screen"),
        ("qml/components/dupa/Dup.qml", qml(), None),
        ("qml/components/dupb/Dup.qml", qml(), None),
        ("qml/shell/Both.qml", qml("Dup {}", imports="import qs.components.dupa\nimport qs.components.dupb"),
         "qml/shell/Both.qml: Dup is defined in qs.components.dupa and qs.components.dupb"),
        ("qml/components/surfaces/osd/systems/Ghost/Ghost.qml", qml(imports="import qs.services.ui"),
         "qml/components/surfaces/osd/systems/Ghost/Ghost.qml: an OSD system's definition imports qs.services.ui"),
        ("qml/components/surfaces/osd/systems/Spook/Spook.qml", qml(), None),
        ("qml/components/surfaces/osd/systems/Spook/SpookWatch.qml", qml("Spook {}"),
         "SpookWatch.qml: uses Spook of its own OSD system's folder"),
        ("qml/components/surfaces/osd/systems/Spook/schema.yaml", "label: Spook\n", None),
        ("qml/components/surfaces/osd/systems/Spook/Helper.qml", qml(imports="import qs.services.ui"),
         "systems/Spook/Helper.qml: reads services: only an OSD system's <Type>Watch.qml"),
        # The config UI's local pieces (scripts/ui-local-pieces.json)
        ("qml/components/views/Local/Tint.qml", qml("StateLayer {}"), "views/Local/Tint.qml:6: StateLayer"),
        ("qml/components/views/Local/Space.qml", qml("Keys.onSpacePressed: x()"), "views/Local/Space.qml:6: Keys.onSpacePressed"),
        ("qml/components/views/Local/Well.qml", qml('Surface { tone: "sunken" }'), "views/Local/Well.qml:6: tone-sunken"),
        ("qml/components/views/Local/Cond.qml", qml('Surface { tone: x ? "sunken" : "raised" }'), "views/Local/Cond.qml:6: tone-sunken"),
        ("qml/components/views/Local/Click.qml", qml("onRowClicked: x()"), "views/Local/Click.qml:6: onRowClicked"),
        ("qml/components/views/Local/First.qml", qml("FormRow {\n      first: true\n    }"), "views/Local/First.qml:7: first-literal"),
        ("qml/components/surfaces/onboarding/Tint.qml", qml("StateLayer {}"), "onboarding/Tint.qml:6: StateLayer"),
        ("qml/components/views/Local/Pushed.qml", qml('Binding {\n      property: "text"\n      restoreMode: Binding.RestoreNone\n    }'),
         "views/Local/Pushed.qml:8: restore-text"),
        ("qml/components/content/Local/Loose.qml", qml("RowLayout {\n      SegmentButton {}\n    }"), "content/Local/Loose.qml:7: SegmentButton"),
        ("qml/components/content/Local/InRow.qml", qml("SegmentRow {\n      SegmentButton {}\n    }"), None),
        # The bar widget template (check_structure.bar_widget_template): T2 and T3 are
        # planted in copies of real widgets
        ("qml/components/bar/widgets/Tone/Tone.qml", qml(), "Tone/Tone.qml: T1"),
        ("qml/components/bar/widgets/DevMode/DevMode.qml", DEV_MODE, f"DevMode/DevMode.qml:{DEV_MODE_AT}: T2"),
        ("qml/components/bar/widgets/LockKeys/LockKeys.qml", LOCK_KEYS, f"LockKeys/LockKeys.qml:{LOCK_KEYS_AT}: T3"),
        ("qml/components/bar/widgets/Tfive/Tfive.qml", widget("colors: ({})"), "Tfive/Tfive.qml:6: T5"),
        ("qml/components/bar/widgets/Button/Helper.qml", qml(), "Button/: T6"),
        ("qml/components/bar/widgets/Tseven/Tseven.qml", widget("id: root\n  text: root.box"), "Tseven/Tseven.qml:7: T7"),
        ("qml/components/bar/widgets/Ttwoa/Ttwoa.qml", widget("property var c: '#fff'"), "Ttwoa/Ttwoa.qml:6: T2"),
        ("qml/components/bar/widgets/Ttwob/Ttwob.qml", widget('property var c: "red"'), "Ttwob/Ttwob.qml:6: T2"),
        ("qml/components/bar/widgets/Ttwoc/Ttwoc.qml", widget("property var c: Qt.rgba (1, 0, 0, 1)"), "Ttwoc/Ttwoc.qml:6: T2"),
        ("qml/components/bar/widgets/Tfiveb/Tfiveb.qml", widget("onClicked: pulse = 1"), "Tfiveb/Tfiveb.qml:6: T5"),
        ("qml/components/bar/widgets/Tsevenb/Tsevenb.qml", widget("text: box"), "Tsevenb/Tsevenb.qml:6: T7"),
        ("qml/components/bar/widgets/Teight/Teight.qml", widget('stateColorName: "error"'), "Teight/Teight.qml:6: T8"),
    ]
    # What the check must say about the schema and the allowlist edits below (and Reach)
    EDITS = [
        "qml/components/views/Reach/: not a OverlayView type and not used anywhere",
        "BarWidget type 'Ghost' has no qml/components/bar/widgets/Ghost/Ghost.qml",
        "x-libraryGroup 'Nope' isn't one of the schema's x-libraryGroups",
        "OverlayModule Calculator: has a text field but no x-keyboard",
        "OverlayModule Power: x-lockActions 'ghost' isn't one of",
        "schema x-card 'Ghost' has no qml/components/views/Settings/GhostCard.qml",
        "schema x-intro 'GhostIntro' has no qml/components/views/Settings/GhostIntro.qml",
        "tool page Keybinds isn't in the Overlay.items default",
        "schema gates on supports.ghostCapability, which docs/dev/compositor/contract.md › Capabilities doesn't list",
        "qml/services/core/Gone.qml no longer uses Socket",
        "ui-local-pieces.json: qml/components/views/Gone.qml no longer breaks StateLayer",
        "ui-local-pieces.json: qml/components/views/NoReason.qml has no reason",
        "qml/components/surfaces/osd/systems/Ghost/: an OSD system without GhostWatch.qml",
        "qml/components/surfaces/osd/systems/Ghost/: an OSD system without schema.yaml",
        "DevMode/: T4 ghostColor is a colour field of DevMode that nothing uses",
        "Updates/Updates.qml:",
        "T4 names failedColor, not a colour field of Updates",
        "Button lists T8, which it no longer breaks",
        "Spacer has no reason",
        "Time names T9, not a rule",
        "Weather lists fieldsReadIn, which supplies none of its otherwise-unused colour fields",
        # x-popoutModule: (a) names a popoutName the widget opens (Volume's is in its base file), (b) declared when the popout is a module
        "bar/widgets/Volume: x-popoutModule.type Caffeine is not a popoutName it opens (AudioMixer)",
        "bar/widgets/Todo: its popoutName Todo is an overlay module: declare popoutModule in its schema.yaml",
        # (c) an anchor's fromWidget keys are the widget's, a module widget's anchor has no extraData, a widget without popoutModule has no fromWidget
        "SystemStats/SystemStats.qml: a PopoutAnchor's fromWidget keys (memoryFormat, metrics, units) differ from SystemStats's popoutModule.fromWidget (memoryFormat, metrics)",
        "Weather/Weather.qml: a PopoutAnchor in a widget with popoutModule hands its values by fromWidget, not extraData",
        "base/AudioLevelWidget.qml: a PopoutAnchor has fromWidget, but qml/components/bar/widgets/Microphone declares no popoutModule",
    ]

    def test_each_rule_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fixture_root(tmp, "qml", "docs/dev/compositor/contract.md")

            def schema(s):
                defs = s["definitions"]
                defs["BarWidget"]["oneOf"].append({"properties": {"type": {"const": "Ghost"}}, "x-libraryGroup": "Nope"})
                del defs["CalculatorOverlayModule"]["x-keyboard"]
                defs["PowerOverlayModule"]["x-lockActions"] = ["ghost"]
                s["x-card"], s["x-intro"] = {"file": "Ghost"}, "GhostIntro"
                s["x-showIf"] = {"/$supports.ghostCapability": True}
                items = s["properties"]["Overlay"]["properties"]["items"]
                items["default"] = [v for v in items["default"] if v.get("type") != "Keybinds"]
                fields = defs["DevModeWidget"]["properties"]["properties"]["properties"]
                fields["ghostColor"] = {"x-options": "colors"}
                del defs["UpdatesWidget"]["properties"]["properties"]["properties"]["failedColor"]
                defs["VolumeWidget"]["x-popoutModule"]["type"] = "Caffeine"
                del defs["TodoWidget"]["x-popoutModule"]
                defs["SystemStatsWidget"]["x-popoutModule"]["fromWidget"].remove("units")
                defs["WeatherWidget"]["x-popoutModule"] = {"type": "WeatherForecast"}
                del defs["MicrophoneWidget"]["x-popoutModule"]
            edit_json(root / "qml/config/json/config.schema.json", schema)
            edit_json(root / "scripts/quickshell-io-allowlist.json", lambda a: a["files"].update({"qml/services/core/Gone.qml": ["Socket"]}))
            edit_json(root / "scripts/ui-local-pieces.json", lambda a: a["files"].update({
                "qml/components/views/Gone.qml": {"rules": ["StateLayer"], "reason": "planted"},
                "qml/components/views/NoReason.qml": {"rules": [], "reason": ""}}))
            edit_json(root / "scripts/bar-widget-exceptions.json", lambda a: a["types"].update({
                "Button": {"reason": "planted", "rules": ["T8"]},
                "Spacer": {"reason": "", "rules": ["T5"]},
                "Time": {"reason": "planted", "rules": ["T9"]},
                "Weather": {"reason": "planted", "rules": [], "fieldsReadIn": ["qml/config/BarsConfig.qml"]}}))
            code, out = run_check(root, "check_structure.py", files=[(p, text) for p, text, _ in self.FILES])
        self.assertEqual(code, 1)
        self.assertEqual(missed(out, [m for _, _, m in self.FILES if m] + self.EDITS), [], out)

    def test_live_tree_passes(self):
        # The real widgets break no template rule, so each plant above is what fails
        with tempfile.TemporaryDirectory() as tmp:
            root = fixture_root(tmp, "qml", "docs/dev/compositor/contract.md")
            _, out = run_check(root, "check_structure.py")
        self.assertEqual([line for line in out.splitlines() if ": T" in line or "bar-widget-exceptions" in line], [], out)


class CheckI18n(unittest.TestCase):
    """scripts/check_i18n.py fails on a key a language lacks, an unused one,
    a file out of format and a stale template, never on an empty entry;
    --untranslated finds bare UI text and undeclared runtime keys."""

    FILES = [
        ("qml/config/I18n.qml", 'readonly property var _formats: ({\n  "longDate": "dddd"\n})\n'),
        ("qml/config/json/config.schema.json", json.dumps({"properties": {"A": {"title": "Alpha"}}, "definitions": {}})),
        ("qml/components/A.qml", qml('text: I18n.tr("Shown")\n    label: I18n.tr(on ? "Yes" : "No")\n'
                                 '    title: "Bare words"\n    description: I18n.tr(name)')),
        ("qml/config/i18n/xx.json", json.dumps({"_meta": {}, "strings": {"Alpha": "a", "Shown": "", "Yes": "y", "Gone": "g"}}, indent=4)),
    ]

    def test_each_rule_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fixture_root(tmp)
            code, out = run_check(root, "check_i18n.py", files=self.FILES)
            self.assertEqual(code, 1)
            self.assertEqual(missed(out, ["missing  qml/components/A.qml:6: 'Shown'", "absent   qml/components/A.qml:7: 'No'",
                                          "unused   'Gone'", "format   not in the canonical format",
                                          "qml/config/i18n/template/language.json: stale"]), [], out)
            code, out = run_check(root, "check_i18n.py", "--untranslated")
            self.assertEqual(code, 1)
            self.assertEqual(missed(out, ["qml/components/A.qml:8: title: 'Bare words'",
                                          "qml/components/A.qml:9: dynamic tr() without declared keys"]), [], out)
            run_check(root, "check_i18n.py", "--fill", "--prune")
            code, out = run_check(root, "check_i18n.py")
            self.assertEqual(code, 0, out)

    def test_array_labels_cover_string_enum_items(self):
        schema = {"properties": {"A": {"type": "array", "items": {"type": "string", "enum": ["builtin"]},
                                      "x-enumLabels": {"builtin": "Built-in"}}}}
        sys.path.insert(0, str(SCRIPTS))
        from check_i18n import schema_strings
        out = set()
        schema_strings(schema, out)
        self.assertIn("Built-in", out)
        self.assertNotIn("Builtin", out)


class CheckQmllint(unittest.TestCase):
    """scripts/check_qmllint.py's baseline: a warning past its count fails,
    and so does a baselined one that's gone."""

    def test_against_the_baseline(self):
        sys.path.insert(0, str(SCRIPTS))
        from check_qmllint import against
        found = {"a.qml": {"k: m": 2, "j: n": 1}, "c.qml": {"z: w": 1}}
        lines = {("a.qml", "k: m"): [3, 9], ("a.qml", "j: n"): [4], ("c.qml", "z: w"): [5]}
        baseline = {"a.qml": {"k: m": 1, "j: n": 1}, "b.qml": {"x: y": 1}}
        self.assertEqual(against(found, lines, baseline), (["a.qml:3,9: k: m (1 new)", "c.qml:5: z: w"], ["b.qml: x: y (1 gone)"]))
        self.assertEqual(against(found, lines, found), ([], []))

    def test_umbrella_qmltypes_gets_a_component(self):
        """A copied qmltypes left with no Component (an umbrella module's empty
        `Module {}`, or only opaque stubs) gets a placeholder; one with a real
        Component is kept."""
        sys.path.insert(0, str(SCRIPTS))
        import check_qmllint
        head = "import QtQuick.tooling 1.2\n\n"
        real = "Module {\n    Component {\n        name: \"A\"\n    }\n}\n"
        stub = "Module {\n    Component {\n        name: \"S\"\n        isTypeOpaque: true\n    }\n}\n"
        with tempfile.TemporaryDirectory() as tmp:
            qt = Path(tmp) / "qt"
            for name, body in (("Umbrella", "Module {}\n"), ("Real", real), ("Stub", stub)):
                write(qt / "Quickshell", f"{name}/x.qmltypes", head + body)
            with mock.patch.object(check_qmllint, "QT_QML", str(qt)):
                out = check_qmllint.qt_imports(Path(tmp) / "out")
            got = {n: (out / "Quickshell" / n / "x.qmltypes").read_text() for n in ("Umbrella", "Real", "Stub")}
        self.assertIn("AxiomQmllintPlaceholder", got["Umbrella"])
        self.assertIn("AxiomQmllintPlaceholder", got["Stub"])
        self.assertNotIn("isTypeOpaque", got["Stub"])
        self.assertEqual(got["Real"], head + real)


class Ratchet(unittest.TestCase):
    """qml_modules' baseline compare (`baseline_diff`) and shrink-only ratchet, on small inputs
    and a scratch git repo passed as `root`."""

    PATH = "scripts/engines-baseline.json"
    KNOWN = {"a.qml": {"purity": ["f:Date.now"]}}

    def setUp(self):
        sys.path.insert(0, str(SCRIPTS))
        import qml_modules
        self.qm = qml_modules
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "repo"
        self.root.mkdir()
        git(self.root, self.tmp.name, "init", "-q", "-b", "main")
        write(self.root, "README", "x\n")
        git(self.root, self.tmp.name, "add", "-A")
        git(self.root, self.tmp.name, "commit", "-q", "-m", "without a baseline")
        self.bare = git(self.root, self.tmp.name, "rev-parse", "HEAD")
        write(self.root, self.PATH, json.dumps(self.KNOWN))
        git(self.root, self.tmp.name, "add", "-A")
        git(self.root, self.tmp.name, "commit", "-q", "-m", "baseline")
        self.base = git(self.root, self.tmp.name, "rev-parse", "HEAD")

    def ratchet(self, found, base=None, new_rules=()):
        return self.qm.ratchet(found, self.PATH, base or self.base, set(new_rules), root=self.root)

    def test_baseline_diff(self):
        found = {"a.qml": {"k: m": 2, "j: n": 1}, "c.qml": {"z: w": 1}}
        known = {"a.qml": {"k: m": 1, "j: n": 1}, "b.qml": {"x: y": 1}}
        self.assertEqual(self.qm.baseline_diff(found, known), ([("a.qml", "k: m", 1), ("c.qml", "z: w", 1)], [("b.qml", "x: y", 1)]))
        self.assertEqual(self.qm.baseline_diff(found, found), ([], []))

    def test_numbered(self):
        self.assertEqual(self.qm.numbered(["f:Date.now", "f:Date.now", "g:console", "f:Date.now"]),
                         ["f:Date.now", "f:Date.now#2", "g:console", "f:Date.now#3"])

    def test_new_and_fixed(self):
        self.assertEqual(self.ratchet(self.KNOWN), [])
        out = self.ratchet({"a.qml": {"purity": ["f:Date.now", "f:Date.now#2"]}})
        self.assertEqual(out, ["a.qml: purity f:Date.now#2: not in the baseline (fix it, or add an exception with its reason to engines-exceptions.json)"])
        self.assertEqual(self.ratchet({}), ["a.qml: purity f:Date.now: fixed, still baselined (delete the entry)"])

    def test_malformed_baseline(self):
        write(self.root, self.PATH, json.dumps({"f:Date.now": "tag"}))
        self.assertEqual(self.ratchet({}), [f"{self.PATH}: not a {{file: {{rule: [symbol]}}}} baseline"])

    def test_added_since_the_base(self):
        grown = {"a.qml": {"purity": ["f:Date.now", "g:console"]}, "b.qml": {"dag": ["x:y"]}}
        write(self.root, self.PATH, json.dumps(grown))
        found = {"a.qml": {"purity": ["f:Date.now", "g:console"]}, "b.qml": {"dag": ["x:y"]}}
        added = [f"a.qml: purity g:console: added to the baseline since {self.base} (a baseline only shrinks)",
                 f"b.qml: dag x:y: added to the baseline since {self.base} (a baseline only shrinks)"]
        self.assertEqual(self.ratchet(found), added)
        self.assertEqual(self.ratchet(found, new_rules={"purity", "dag"}), [])
        self.assertEqual(self.ratchet(found, new_rules={"a.qml", "b.qml"}), [])
        self.assertEqual(self.ratchet(found, new_rules={"purity"}), added[1:])

    def test_baseline_absent_at_the_base(self):
        found = {"a.qml": {"purity": ["f:Date.now"]}}
        self.assertEqual(self.ratchet(found, base=self.bare),
                         [f"a.qml: purity f:Date.now: added to the baseline since {self.bare} (a baseline only shrinks)"])
        self.assertEqual(self.ratchet(found, base=self.bare, new_rules={"purity"}), [])

    def test_unreadable_base(self):
        found = {"a.qml": {"purity": ["f:Date.now"]}}
        for base in ("nosuchref", ""):
            out = self.ratchet(found, base=base) if base else self.qm.ratchet(found, self.PATH, base, set(), root=self.root)
            self.assertEqual(len(out), 1, out)
            self.assertTrue(out[0].startswith(f"{self.PATH}: can't read the base {base}:"), out)
        write(self.root, self.PATH, "{}")
        self.assertIn("can't read the base nosuchref", self.ratchet({}, base="nosuchref")[0])

    def test_file_at(self):
        self.assertEqual(json.loads(self.qm.file_at(self.base, self.PATH, root=self.root)), self.KNOWN)
        self.assertIsNone(self.qm.file_at(self.bare, self.PATH, root=self.root))
        for base in ("nosuchref", ""):
            with self.assertRaises(ValueError):
                self.qm.file_at(base, self.PATH, root=self.root)

    def test_add_to_baseline(self):
        found = {"a.qml": {"purity": ["f:Date.now"], "dag": ["new:one"]}, "b.qml": {"apply": ["m:Qt.callLater"]}}
        count = self.qm.add_to_baseline(found, self.PATH, set(), root=self.root)
        self.assertEqual(count, 1)
        self.assertEqual(json.loads((self.root / self.PATH).read_text()), self.KNOWN)
        count = self.qm.add_to_baseline(found, self.PATH, {"apply", "a.qml"}, root=self.root)
        text = (self.root / self.PATH).read_text()
        self.assertEqual(count, 3)
        self.assertEqual(json.loads(text), {"a.qml": {"dag": ["new:one"], "purity": ["f:Date.now"]}, "b.qml": {"apply": ["m:Qt.callLater"]}})
        self.assertTrue(text.endswith("}\n"))
        self.qm.add_to_baseline({}, self.PATH, set(), root=self.root)
        self.assertEqual(json.loads((self.root / self.PATH).read_text()), {})

    def test_default_base(self):
        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true"}):
            self.assertEqual(self.qm.default_base(root=self.root), "HEAD^1")
        env = {k: v for k, v in os.environ.items() if k != "GITHUB_ACTIONS"}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(self.qm.default_base(root=self.root), "origin/main")
            git(self.root, self.tmp.name, "update-ref", "refs/remotes/origin/main", self.bare)
            self.assertEqual(self.qm.default_base(root=self.root), self.bare)


def demo_entry(**more):
    """A filled manifest entry for the fixture engine `demo`."""
    entry = {"prefix": "DEMO", "facade": "DemoEngine", "folder": "qml/components/methods/demo",
             "files": ["qml/components/methods/DemoRoot.qml"], "helpers": ["DemoHelper"],
             "owners": ["qml/services/DemoOwner.qml"], "adapters": ["qml/components/DemoAdapter.qml"],
             "itemPaths": ["qml/components/DemoItem.qml"], "pluginPaths": ["qml/components/DemoPlugin.qml"],
             "tests": {"rows": "tests/demo/Rows.js", "golden": {"DemoGolden": "tests/demo/golden.json"},
                       "sweep": ["DemoSweep"], "pixel": ["tests-layout/tst_DemoPixels.qml"]},
             "doc": "docs/dev/core/demo-engine.md", "editPoints": {}}
    return {**entry, **more}


def manifest_text(entry=None, **top):
    """A manifest's JSON text: `$flat`, the `top` sections and `entry` as the engine `demo`."""
    return json.dumps({"$flat": {}, **top, **({"demo": entry} if entry else {})})


def demo_engine(root):
    """Write the fixture engines into a copy of the tree: `demo` (demo_entry) with a file at every
    path it holds, and `sink`, which takes the seam `demoFeed` from it, their manifest, the side doc
    both share and the seam's row after the separator of engines.md's `## Seam register` table. The
    unbroken fixture passes every rule of check_engines and its rows pass in the runner."""
    sys.path.insert(0, str(SCRIPTS))
    import manifests
    root = Path(root)
    methods = "qml/components/methods"
    rows = [
        {"id": "DEMO-01", "why": "a seed holds", "call": "solve", "input": {"request": {"seed": True}}, "expect": {"rule": "demoSeeded"}},
        {"id": "DEMO-02", "why": "a model lists its items", "call": "model", "input": {"config": {"name": "x"}}, "expect": {"items": ["x"]}},
        {"id": "DEMO-03", "why": "kind a is one wide", "call": "solve", "input": {"request": {"kind": "a"}},
         "expect": {"box": {"width": 1}, "rule": "kindA"}},
        {"id": "DEMO-04", "why": "kind b takes the tuned size", "call": "solve", "input": {"request": {"kind": "b"}},
         "expect": {"box": {"width": 2}, "rule": "kindB"}},
        {"id": "DEMO-05", "why": "a drawn box follows its result", "call": "drawn",
         "input": {"result": {"kind": "a"}, "motion": {"progress": 1}}, "expect": {"box": {"width": 1}, "rule": "kindA"}},
        {"id": "DEMO-06", "why": "a pick answers for its spot", "call": "pick", "input": {"spot": {"kind": "b"}}, "expect": {"rule": "kindB"}},
    ]
    docs = "\n".join(f"## {i} {h}\nThe demo's {h.lower()}." for i, h in enumerate(manifests.ENGINE_DOC_HEADINGS, 1))
    files = {
        f"{methods}/demo/DemoEngine.qml": 'pragma Singleton\nimport QtQuick\n\n// The demo facade.\nQtObject {\n  id: root\n\n  readonly property var api: ({\n'
            '    "model": {"in": ["config"], "out": {"items": "DemoRules.itemsOf"}},\n'
            '    "solve": {"in": ["request", "model", "tuning"], "out": {"box": "DemoRules.boxOf"}},\n'
            '    "drawn": {"in": ["result", "motion"], "out": {"": "DemoRules.boxOf"}},\n'
            '    "pick": {"in": ["spot"], "out": {"": "DemoRules.boxOf"}, "extra": true}\n  })\n\n'
            '  readonly property var tuning: ({"size": 2})\n\n'
            '  function model(input) {\n    const {config} = input;\n    return {"items": DemoRules.itemsOf({config}), "problems": []};\n  }\n\n'
            '  function solve(input) {\n    const {request, model, tuning = root.tuning} = input;\n    return DemoRules.boxOf({request, tuning});\n  }\n\n'
            '  function drawn(input) {\n    const {result, motion} = input;\n    return DemoRules.boxOf({"request": result, "tuning": root.tuning});\n  }\n\n'
            '  function pick(input) {\n    const {spot} = input;\n    return DemoRules.boxOf({"request": spot, "tuning": root.tuning});\n  }\n}\n',
        f"{methods}/demo/DemoRules.qml": 'pragma Singleton\nimport QtQuick\n\n// The demo rules: one cell table and the functions its rows name.\nQtObject {\n  id: root\n\n'
            '  readonly property var rows: [\n    {"id": "kindA", "when": {"kind": "a"}, "then": {"width": 1}, "why": "a is one wide"},\n'
            '    {"id": "kindB", "when": {"kind": "b"}, "then": "wideBox", "why": "b takes the tuned size"}\n  ]\n\n'
            '  readonly property var axes: ({"kind": ["a", "b"]})\n\n'
            '  function itemsOf(input) {\n    return [input.config.name];\n  }\n\n'
            '  function boxOf(input) {\n    const {request} = input;\n    if (request.seed) {\n      return demoSeeded(input);\n    }\n'
            '    const row = rows.find(r => r.when.kind === request.kind);\n'
            '    const box = typeof row.then === "string" ? root[row.then](input) : row.then;\n    return {"box": box, "rule": row.id};\n  }\n\n'
            '  function wideBox(input) {\n    const {tuning} = input;\n    return {"width": tuning.size};\n  }\n\n'
            '  function demoSeeded(input) {\n    return {"box": null, "rule": "demoSeeded"};\n  }\n}\n',
        f"{methods}/demo/DemoHelper.qml": qml("property var items: []"),
        f"{methods}/demo/DemoInternal.qml": qml("property var box: null"),
        f"{methods}/DemoRoot.qml": qml("property int n: 1"),
        f"{methods}/sink/SinkEngine.qml": 'pragma Singleton\nimport QtQuick\n\n// The sink facade.\nQtObject {\n  readonly property var api: ({\n'
            '    "model": {"in": ["state"], "out": {"": "SinkEngine.model"}},\n'
            '    "solve": {"in": ["request", "model"], "out": {"": "SinkEngine.solve"}}\n  })\n\n'
            '  function model(input) {\n    const {state} = input;\n    return {};\n  }\n\n'
            '  function solve(input) {\n    const {request, model} = input;\n    return {};\n  }\n}\n',
        "qml/services/DemoOwner.qml": "import QtQuick\n// A fixture.\nItem {\n  function run() { DemoEngine.model({}); DemoEngine.solve({}); }\n}\n",
        "qml/components/DemoAdapter.qml": "import QtQuick\n// A fixture.\nItem {\n  function run() { DemoEngine.solve({}); DemoEngine.drawn({}); }\n"
            "  function settled() { Qt.callLater(run); } // allowed: apply the demo's first turn\n}\n",
        "qml/components/DemoItem.qml": qml("property int n: 1"),
        "qml/components/DemoPlugin.qml": qml("property int n: 1"),
        "tests/demo/Rows.js": ".pragma library\n// The demo rows.\nvar rows = " + json.dumps(rows, indent=2) + ";\n",
        "tests/sink/Rows.js": ".pragma library\n// The sink rows.\nvar rows = " + json.dumps([
            {"id": "DEMOS-01", "why": "a sink models", "call": "model", "input": {"state": {}}, "expect": {}},
            {"id": "DEMOS-02", "why": "a sink solves", "call": "solve", "input": {"request": {}}, "expect": {}}]) + ";\n",
        "tests/tst_DemoEngine.qml": 'import QtQuick\nimport QtTest\nimport qs.components.methods.demo\nimport "demo/Rows.js" as Rows\n\n'
            '// The demo engine\'s contract rows (tests/demo/Rows.js)\nTestCase {\n  id: root\n  name: "DemoEngine"\n\n  EngineRows {\n'
            '    id: rows\n    testCase: root\n    facade: DemoEngine\n    rows: Rows.rows\n  }\n\n'
            '  function test_rows_data() {\n    return rows.data();\n  }\n  function test_rows(data) {\n    rows.run(data);\n  }\n}\n',
        "docs/dev/core/demo-engine.md": f"# Demo engine\n\n{docs}\n",
    }
    for path, text in files.items():
        write(root, path, text)
    sink = demo_entry(prefix="DEMOS", facade="SinkEngine", folder=f"{methods}/sink", files=[], helpers=[], owners=[],
                      adapters=[], itemPaths=[], pluginPaths=[], tests={"rows": "tests/sink/Rows.js"},
                      fedBy={"model": [{"from": "demo.solve", "seam": "demoFeed"}]})
    demo = demo_entry(intakes={"solve": [{"from": "demo.model", "rule": "demoSeeded", "at": "qml/components/DemoAdapter.qml"}]},
                      tables={"DemoRules.rows": {"kind": "cell"}},
                      editPoints={"case": "DemoRules.rows", "rule": ["DemoRules", "DemoRules.boxOf"], "input": "DemoOwner",
                                  "output": "DemoEngine.api", "consumer": "DemoAdapter", "tuning": "DemoEngine.tuning"},
                      alone=[{"regex": "\\bdemoKindOf\\b", "only": [f"{methods}/demo/DemoRules.qml"], "why": "the kind lookup lives in the rules file"}])
    text = json.loads(manifest_text(demo))
    text["sink"] = sink
    (root / "scripts" / "engines.json").write_text(json.dumps(text, indent=2) + "\n")
    for entry in manifests.engines(text=json.dumps(text))[0].values():
        for path in manifests.held_paths(entry):
            if path.endswith(".qml") and not (root / path).exists():
                write(root, path, qml())
    doc = root / "docs/dev/core/engines.md"
    lines = doc.read_text().split("\n")
    at = lines.index("## Seam register")
    separator = next(i for i in range(at, len(lines)) if lines[i].startswith("|") and set(lines[i]) <= set("|-: "))
    lines.insert(separator + 1, "| demoFeed | The demo's box | rect | rest | `demo.solve` | `sink.model` | DemoRules |")
    doc.write_text("\n".join(lines))


def demo_repo(tmp, *paths):
    """The fixture engines (demo_engine) in a git copy of the tree: `qml`, engines.md and `paths`,
    committed; (root, the commit)."""
    root = fixture_root(tmp, "qml", "docs/dev/core/engines.md", *paths)
    demo_engine(root)
    git(root, tmp, "init", "-q", "-b", "main")
    git(root, tmp, "add", "-A")
    git(root, tmp, "commit", "-q", "-m", "base")
    return root, git(root, tmp, "rev-parse", "HEAD")


class Manifests(unittest.TestCase):
    """scripts/manifests.py reads the engine manifest: `tests_for`, the keys it accepts and refuses,
    and its CLI, from fixture manifest text."""

    def setUp(self):
        sys.path.insert(0, str(SCRIPTS))
        import manifests
        self.m = manifests

    def test_tests_for(self):
        text = manifest_text(demo_entry())
        names = ["DemoEngine", "DemoGolden", "DemoPixels", "DemoSweep"]
        for path in ("qml/components/methods/demo/Inside.qml", "qml/components/methods/DemoRoot.qml",
                     "qml/services/DemoOwner.qml", "qml/components/DemoAdapter.qml", "qml/components/DemoItem.qml",
                     "qml/components/DemoPlugin.qml", "qml/components/methods/demo/DemoHelper.qml", "tests/demo/Rows.js",
                     "tests/demo/Fixtures.js"):
            self.assertEqual(self.m.tests_for([path], text=text), names, path)
        self.assertEqual(self.m.tests_for(["qml/components/methods/Other.qml", "qml/components/methods/demox/A.qml"], text=text), [])
        self.assertEqual(self.m.tests_for(["qml/components/methods/Other.qml"], text=manifest_text()), [])

    def test_golden_and_pixel(self):
        text = manifest_text(demo_entry())
        self.assertEqual(self.m.golden_file("DemoGolden", text=text), "tests/demo/golden.json")
        self.assertIsNone(self.m.golden_file("Nope", text=text))
        self.assertEqual(self.m.pixel_tests(text=text), ["tests-layout/tst_DemoPixels.qml"])
        self.assertEqual(self.m.pixel_tests(text=manifest_text()), [])

    def test_sections(self):
        text = manifest_text(demo_entry(), **{"$domains": {"geo": {"uses": [], "tables": []}}})
        self.assertEqual(list(self.m.engines(text=text)[0]), ["demo"])
        self.assertEqual(self.m.engines(text=text)[1], [])
        self.assertEqual(self.m.flat(text=text), {})
        self.assertEqual(list(self.m.domains(text=text)), ["geo"])
        self.assertEqual(self.m.engines(text=manifest_text())[0], {})
        short = manifest_text(demo_entry(), **{"$domains": {"geo": {"tables": []}}})
        self.assertEqual(self.m.domains(text=short)["geo"]["uses"], [])
        bare = demo_entry()
        del bare["doc"]
        self.assertEqual(self.m.engines(text=manifest_text(bare))[0]["demo"]["doc"], "")
        bad = self.m.engines(text=manifest_text(demo_entry(fedBy=[], intakes={"solve": ["x"], "model": [{"from": "demo.solve"}]})))[0]["demo"]
        self.assertEqual((bad["fedBy"], bad["intakes"]), ({}, {"model": [{"from": "demo.solve"}]}))

    def test_held_paths(self):
        entry = self.m.engines(text=manifest_text(demo_entry()))[0]["demo"]
        self.assertEqual(self.m.held_paths(entry), [
            "qml/components/methods/demo", "qml/components/methods/DemoRoot.qml", "qml/components/methods/demo/DemoHelper.qml",
            "qml/components/DemoItem.qml", "qml/components/DemoPlugin.qml", "qml/components/DemoAdapter.qml",
            "qml/services/DemoOwner.qml", "tests/demo"])

    def test_missing_headings(self):
        names = self.m.ENGINE_DOC_HEADINGS
        doc = [f"## {i} {n}" for i, n in enumerate(names, 1)]
        self.assertEqual(self.m.missing_headings("\n".join(doc), names), [])
        self.assertEqual(self.m.missing_headings("\n".join(doc[:3] + doc[4:]), names), ["Outputs"])
        self.assertEqual(self.m.missing_headings("\n".join(doc[:2] + [doc[3], doc[2]] + doc[4:]), names), ["Outputs"])
        self.assertEqual(self.m.missing_headings("\n".join(doc[:1] + ["## 3 Inputs"] + doc[2:]), names), ["Inputs"])
        self.assertEqual(self.m.missing_headings("\n".join(["see ## 1 Role"] + doc[1:]), names), ["Role"])

    def test_edit_point_rows(self):
        entry = {"editPoints": {"tuning": "E.tuning", "other": "Z", "case": "R.rows", "rule": ["A", "B"]}}
        self.assertEqual(self.m.edit_point_rows(entry), [("case", "R.rows"), ("rule", "A"), ("rule", "B"),
                                                         ("tuning", "E.tuning"), ("other", "Z")])
        self.assertEqual(self.m.edit_point_rows({"editPoints": {}}), [])
        self.assertEqual(self.m.edit_point_rows({"editPoints": []}), [])

    def test_refused_manifests(self):
        gone = demo_entry()
        del gone["facade"]
        cases = [
            (manifest_text(demo_entry(phase="x")), "demo: unknown key phase"),
            (manifest_text(demo_entry(owners=5)), "demo.owners is not a list of strings"),
            (manifest_text(demo_entry(adapters=[None])), "demo.adapters is not a list of strings"),
            (manifest_text(demo_entry(folder=5)), "demo.folder is not a string"),
            (manifest_text(demo_entry(prefix=["DEMO"])), "demo.prefix is not a string"),
            (manifest_text(demo_entry(tests={"rows": "r.js", "phase": 1})), "demo.tests: unknown key phase"),
            (manifest_text(gone), "demo: missing key facade"),
            (manifest_text(demo_entry(), **{"$flat": {"Helper": {"prefix": "DEMO", "tables": []}}}), "prefix DEMO is used by demo and $flat.Helper"),
            (manifest_text(demo_entry(), **{"$domains": {"geo": {"uses": [], "prefix": "DEMO"}}}), "prefix DEMO is used by demo and $domains.geo"),
            (manifest_text(demo_entry(), **{"$flat": []}), "$flat is not an object"),
            (manifest_text(demo_entry(), **{"$domains": {"geo": {"tables": []}}}), "$domains.geo: missing key uses"),
            (manifest_text(demo_entry(), **{"$flat": {"Helper": {"prefix": "FLAT"}}}), "$flat.Helper: missing key tables"),
            (manifest_text(demo_entry(), **{"$flat": {"Helper": {"tables": []}}}), "$flat.Helper: missing key prefix"),
            (manifest_text(demo_entry(fedBy=[])), "demo.fedBy is not an object"),
            (manifest_text(demo_entry(intakes="x")), "demo.intakes is not an object"),
            (manifest_text(demo_entry(fedBy={"model": "x"})), "demo.fedBy.model is not a list of objects with string from, seam and rule"),
            (manifest_text(demo_entry(intakes={"solve": ["x"]})), "demo.intakes.solve is not a list of objects"),
            (manifest_text(demo_entry(fedBy={"model": [{"from": 5}]})), "demo.fedBy.model is not a list of objects"),
            (manifest_text(demo_entry(fedBy={"model": [{"from": "a.b", "seam": []}]})), "demo.fedBy.model is not a list of objects"),
        ]
        for text, message in cases:
            errors = self.m.engines(text=text)[1]
            self.assertTrue(any(message in e for e in errors), (message, errors))

    def test_bad_json(self):
        self.assertTrue(self.m.engines(text="{")[1][0].startswith("scripts/engines.json: not JSON"))
        self.assertEqual(self.m.engines(text="{")[0], {})
        self.assertEqual(self.m.flat(text="{"), {})
        self.assertEqual(self.m.domains(text="{"), {})
        self.assertEqual(self.m.tests_for(["qml/x.qml"], text="{"), [])

    def test_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fixture_root(tmp)
            (root / "scripts" / "engines.json").write_text(manifest_text(demo_entry()))
            code, out = run_check(root, "manifests.py", "--tests-for", "tests/demo/Rows.js", "qml/x.qml")
            self.assertEqual((code, out.split()), (0, ["DemoEngine", "DemoGolden", "DemoPixels", "DemoSweep"]))
            code, out = run_check(root, "manifests.py", "--tests-for", "qml/x.qml")
            self.assertEqual((code, out), (0, ""))
            code, out = run_check(root, "manifests.py", "--other")
            self.assertEqual(code, 2)
            self.assertIn("--tests-for", out)


class CheckEngines(unittest.TestCase):
    """scripts/check_engines.py on a git copy of the tree holding the fixture engines: the unbroken
    demo passes, the base is read on every run, and each rule fails on its breaking edit."""

    def test_each_rule_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, base = demo_repo(tmp)
            self.assertEqual(run_check(root, "check_engines.py", "--base", base), (0, "engines ok\n"))
            code, out = run_check(root, "check_engines.py", "--base", "nosuchref")
            self.assertEqual(code, 1)
            self.assertIn("can't read the base nosuchref", out)
            self.assertNotIn("Traceback", out)

            methods = "qml/components/methods"
            edit_json(root / "scripts/engines.json", self.break_manifest)
            files = [
                (f"{methods}/x/X.qml", qml()),
                (f"{methods}/PurityConfig.qml", qml(imports="import qs.config")),
                (f"{methods}/PurityQuickshell.qml", qml(imports="import Quickshell")),
                (f"{methods}/PurityDemoImport.qml", qml(imports="import qs.components.methods.demo")),
                (f"{methods}/PurityTimer.qml", qml("\n  Timer {}")),
                (f"{methods}/PurityNow.qml", qml("\n  function g() { return Date.now(); }")),
                (f"{methods}/PurityDate.qml", qml("\n  function g() { return new Date(); }\n  function h() { return new Date(5); }")),
                (f"{methods}/PurityRandom.qml", qml("\n  function g() { return Math.random(); }")),
                (f"{methods}/PurityConsole.qml", qml("\n  function g() { console.log(1); }")),
                (f"{methods}/PurityLater.qml", qml("\n  function g() { Qt.callLater(f); }")),
                (f"{methods}/demo/DemoHelper.qml", qml("\n  property var a: DemoInternal.box")),
                (f"{methods}/demo/DemoInternal.qml", qml("\n  property var box: DemoHelper.items")),
                (f"{methods}/demo/DemoTraced.qml", qml("\n  function y() { EngineTrace.record(1); }")),
                ("qml/components/Tracer.qml", qml("\n  function x() { return EngineTrace._store; }")),
                ("qml/services/DemoOwner.qml", qml("\n  function run() { DemoEngine.model({}); DemoEngine.drawn({}); }")),
                ("qml/components/DemoAdapter.qml", "import QtQuick\n// A fixture.\nItem {\n  function run() { DemoEngine.solve({}); DemoEngine.drawn({}); }\n"
                 "  function settled() { Qt.callLater(run); } // allowed: apply the demo's first turn\n"
                 "  function late() { Qt.callLater(run); }\n  function other() { Qt.callLater(run); } // allowed: nothing\n}\n"),
                ("scripts/engines-exceptions.json", json.dumps({
                    "qml/components/methods/PurityRandom.qml": {"rules": ["purity", "dag"], "reason": "fixture"},
                    "qml/nowhere/*.qml": {"rules": ["purity"], "reason": "fixture"}})),
                (f"{methods}/SoloRoot.qml", qml()),
                ("qml/components/SoloEngine.qml", qml()),
                ("qml/components/DemoItem.qml", qml("\n  onPillsChanged: f()\n  function z() { setRequest(1); }")),
            ]
            code, out = run_check(root, "check_engines.py", "--base", base, files=files)
        self.assertEqual(code, 1)
        mine = "qml/components/methods"
        self.assertEqual(missed(out, [
            f"{mine}/x: placed x: not in the baseline",
            "scripts/engines.json: placed ghost.folder:qml/components/methods/ghost: not in the baseline",
            "scripts/engines.json: placed demo.files:qml/components/methods/Gone.qml: not in the baseline",
            "scripts/engines.json: placed demo.helpers:qml/components/methods/demo/Gone.qml: not in the baseline",
            f"{mine}/PurityConfig.qml: purity PurityConfig:qs.config: not in the baseline",
            f"{mine}/PurityQuickshell.qml: purity PurityQuickshell:Quickshell: not in the baseline",
            f"{mine}/PurityDemoImport.qml: purity PurityDemoImport:qs.components.methods.demo: not in the baseline",
            f"{mine}/PurityTimer.qml: purity PurityTimer:Timer: not in the baseline",
            f"{mine}/PurityNow.qml: purity g:Date.now: not in the baseline",
            f"{mine}/PurityDate.qml: purity g:new Date(): not in the baseline",
            "scripts/engines.json: placed ghost.facade:GhostEngine: not in the baseline",
            "scripts/engines.json: placed solo.facade:SoloEngine: not in the baseline",
            "scripts/engines-exceptions.json: qml/components/methods/PurityRandom.qml lists dag, which no file under it hits",
            "scripts/engines-exceptions.json: qml/nowhere/*.qml lists purity, which no file under it hits",
            f"{mine}/PurityConsole.qml: purity g:console: not in the baseline",
            f"{mine}/PurityLater.qml: purity g:Qt.callLater: not in the baseline",
            "scripts/engines.json: dag demo.model:demo.model→demo.solve→demo.model: not in the baseline",
            f"{mine}/demo/DemoHelper.qml: dag DemoHelper:DemoHelper→DemoInternal→DemoHelper: not in the baseline",
            "scripts/engines.json: dag demo.drawn:demo.drawn→sink.solve: not in the baseline",
            "scripts/engines.json: dag sink.model:noSuchSeam: not in the baseline",
            "docs/dev/core/engines.md: dag demoFeed:demo.solve→sink.model: not in the baseline",
            "tests/demo/Rows.js: dag demo.solve:noRowRule: not in the baseline",
            "qml/services/DemoOwner.qml: dag run:drawn+model: not in the baseline",
            f"{mine}/demo/DemoTraced.qml: trace y:EngineTrace.record: not in the baseline",
            "qml/components/Tracer.qml: trace x:EngineTrace._store: not in the baseline",
            "qml/components/DemoAdapter.qml: apply late:Qt.callLater: not in the baseline",
            "qml/components/DemoAdapter.qml: apply other:Qt.callLater: not in the baseline",
            "qml/components/DemoItem.qml: apply DemoItem:onPillsChanged: not in the baseline",
            "qml/components/DemoItem.qml: apply z:setRequest: not in the baseline",
        ]), [], out)
        lines = out.splitlines()
        self.assertEqual([l for l in lines if "PurityDemoImport" in l and "dag" in l], [], out)
        self.assertEqual(len([l for l in lines if "PurityDemoImport" in l]), 1, out)
        self.assertEqual([l for l in lines if "PurityRandom.qml: purity" in l], [], out)
        self.assertEqual([l for l in lines if "settled" in l], [], out)
        self.assertEqual([l for l in lines if "h:new Date" in l], [], out)

    @staticmethod
    def break_manifest(data):
        data["demo"]["files"].append("qml/components/methods/Gone.qml")
        data["demo"]["helpers"].append("Gone")
        data["demo"]["fedBy"] = {"model": [{"from": "demo.solve"}]}
        data["demo"]["intakes"]["solve"].append({"from": "demo.model", "rule": "noRowRule", "at": "qml/components/DemoAdapter.qml"})
        data["sink"]["fedBy"] = {"model": [{"from": "demo.model", "seam": "noSuchSeam"}],
                                 "solve": [{"from": "demo.drawn", "seam": "demoFeed"}]}
        data["solo"] = {**demo_entry(), "prefix": "SOLO", "facade": "SoloEngine", "folder": "", "files": ["qml/components/methods/SoloRoot.qml"],
                        "helpers": [], "owners": [], "adapters": [], "itemPaths": [], "pluginPaths": [], "tests": {"rows": "tests/solo/Rows.js"}}
        data["ghost"] = {**data["sink"], "prefix": "DEMOG", "facade": "GhostEngine", "folder": "qml/components/methods/ghost",
                         "fedBy": {}, "tests": {"rows": "tests/ghost/Rows.js"}}

    def test_each_shape_rule_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, base = demo_repo(tmp)
            edit_json(root / "scripts/engines.json", self.break_shapes)
            m = "qml/components/methods"
            padded = ('pragma Singleton\nimport QtQuick\n\n// A broken facade.\nQtObject {\n  id: root\n\n  readonly property var tuning: ({"size": 2})\n\n'
                      '  readonly property var api: ({\n'
                      '    "model": {"in": ["env"], "out": {"items": "DemoRules.itemsOf"}},\n'
                      '    "solve": {"in": ["request", "model", "tuning", "now"], "out": {"box": "DemoRules.boxOf"}},\n'
                      '    "drawn": {"in": ["result", "motion"], "out": {"": "DemoRules.nothing"}},\n'
                      '    "pick": {"in": ["spot", "more"], "out": {"": "DemoRules.boxOf"}, "extra": true},\n'
                      '    "other": {"in": ["spot"], "out": {"": "DemoRules.boxOf"}, "unfed": 5},\n'
                      '    "drawnX": {"in": [["x"]], "out": {"": "DemoRules.boxOf"}, "extra": true}\n  })\n\n'
                      '  function stray(input) {\n    return 1;\n  }\n\n'
                      '  function model(input) {\n    const {env} = input;\n    return {};\n  }\n\n'
                      '  function solve(input) {\n    const {request, model, tuning = root.tuning, now} = input;\n    return {};\n  }\n\n'
                      '  function drawn(input) {\n    return {};\n  }\n\n'
                      '  function pick(input) {\n    const {spot} = input;\n    return {};\n  }\n\n'
                      '  function other(input) {\n    const {spot} = input;\n    return {};\n  }\n\n'
                      '  function drawnX(input) {\n    const {spot} = input;\n    return {};\n  }\n')
            padded += "  // padding\n" * (200 - len(padded.splitlines())) + "}\n"
            body = lambda n: "".join(f"    const v{i} = {i};\n" for i in range(n))
            internal = ('import QtQuick\n\n// A broken internal file.\nQtObject {\n'
                        f'  function long() {{\n{body(59)}  }}\n\n  function atLimit() {{\n{body(58)}  }}\n\n'
                        '  function once() {\n    /* is it open? first? "rule": "oldRule" */\n    const s = "x ? y : z ? w /*";\n'
                        '    return a?.b ?? (c ? d : e);\n  }\n\n  function twice() {\n    return a ? b : c ? d : e;\n  }\n\n'
                        '  /* end */\n\n'
                        '  readonly property var cells: [{"when": {"kind": "a"}, "then": 1, "why": "a cell"}]\n\n'
                        '  readonly property var order: [\n    {"when": "isFirst", "then": 0, "why": "no id"},\n    {"id": "first", "when": "isFirst", "then": 1, "why": "a rule"},\n'
                        '    {"id": "first", "when": "isFirst", "then": 2, "why": "a rule again"},\n'
                        '    {"id": "noWhy", "when": "isFirst", "then": 3},\n'
                        '    {"id": "rest", "when": "isFirst", "then": 4, "why": "the rest"}\n  ]\n\n'
                        '  function isFirst(input) {\n    return true;\n  }\n\n'
                        '  readonly property var ranks: [{"name": "a", "rank": Math.max(1, 2), "why": "a rank"}]\n\n'
                        '  readonly property var idRanks: [{"name": "a", "rank": 1, "why": "a rank"}]\n\n'
                        '  function unnamed() {\n    return {"rule": "noSuchRule"};\n  }\n}\n')
            rules = (root / f"{m}/demo/DemoRules.qml").read_text().replace('["a", "b"]', '["a", "b", "c"]')
            sys.path.insert(0, str(SCRIPTS))
            import check_engines
            rows = check_engines._load_rows(root / "tests/demo/Rows.js")
            kept = [r for r in rows if r["call"] != "pick" and r["id"] != "DEMO-04" and r["call"] != "drawn"]
            kept += [{"id": "DEMO-20", "why": "a call that is no api key", "call": "nope", "input": {}, "expect": {"rule": "kindA"}},
                     {"id": "DEMO-21", "why": "a row with args", "call": "drawn", "args": [{}], "expect": {"rule": "kindA"}}]
            doc = (root / "docs/dev/core/demo-engine.md").read_text().split("\n")
            doc = [l for l in doc if not l.startswith("## 9 ")]
            at = doc.index("## 3 Stages")
            doc[at:at + 4] = doc[at + 2:at + 4] + doc[at:at + 2]
            files = [
                (f"{m}/demo/DemoEngine.qml", padded), (f"{m}/demo/DemoInternal.qml", internal), (f"{m}/demo/DemoRules.qml", rules),
                (f"{m}/demo/DemoKit.qml", qml('property int size: 1\n  property var axes: ({"kind": [["a"]]})\n  property var grid: []')),
                (f"{m}/DemoFlat.qml", qml('property var ranks: [{"name": "a", "rank": 1}]')),
                (f"{m}/lone/LoneEngine.qml", 'pragma Singleton\nimport QtQuick\n\n// A facade whose api is no literal.\nQtObject {\n  id: root\n'
                 '  readonly property var api: ({"model": root.x})\n}\n'),
                ("qml/components/DemoReader.qml", "import QtQuick\n// A fixture.\nItem {\n  function read() { DemoRules.rows; DemoEngine.model({}); }\n"
                 "  function draw() { return DemoKit.size; }\n}\n"),
                ("qml/services/DemoOwner.qml", "import QtQuick\n// A fixture.\nItem {\n  function run() { DemoEngine.model({}); DemoEngine.solve({}); }\n"
                 "  function draw() { DemoEngine.drawn({}); }\n}\n"),
                ("qml/components/DemoItem.qml", "import QtQuick\n// A fixture.\nItem {\n  function size() { return DemoKit.size; }\n"
                 "  function kindOf() { return demoKindOf; }\n}\n"),
                ("qml/components/DemoPlugin.qml", "import QtQuick\n// A fixture.\nItem {\n  function hook() { DemoEngine.pick({}); }\n}\n"),
                ("tests/demo/Rows.js", ".pragma library\n// The demo rows.\nvar rows = " + json.dumps(kept) + ";\n"),
                ("tests/sink/Rows.js", "var rows = [{"),
                ("docs/dev/core/demo-engine.md", "\n".join(doc)),
            ]
            code, out = run_check(root, "check_engines.py", "--base", base, files=files)
        self.assertEqual(code, 1)
        end = ": not in the baseline"
        self.assertEqual(missed(out, [line + end for line in [
            "qml/components/DemoReader.qml: facade-only read:DemoRules", "qml/components/DemoReader.qml: facade-only read:DemoEngine.model",
            "qml/components/DemoReader.qml: facade-only draw:DemoKit", "qml/components/DemoPlugin.qml: facade-only hook:DemoEngine.pick",
            "qml/services/DemoOwner.qml: facade-only draw:DemoEngine.drawn",
            f"{m}/demo/DemoEngine.qml: api api:not first", f"{m}/demo/DemoEngine.qml: api stray:no api entry",
            f"{m}/demo/DemoEngine.qml: api api.pick:in", f"{m}/demo/DemoEngine.qml: api api.other:unfed", f"{m}/demo/DemoEngine.qml: api api.drawn:DemoRules.nothing",
            f"{m}/demo/DemoEngine.qml: shape api.solve:now", f"{m}/demo/DemoEngine.qml: shape api.model:needs config|state",
            f"{m}/demo/DemoEngine.qml: shape api.other:not a stage", f"{m}/demo/DemoEngine.qml: shape drawn:form",
            f"{m}/demo/DemoEngine.qml: shape DemoEngine:lines", f"{m}/lone/LoneEngine.qml: api api:not literal",
            f"{m}/demo/DemoInternal.qml: shape long:lines", f"{m}/demo/DemoInternal.qml: shape twice:ternary",
            f"{m}/demo/DemoInternal.qml: tables cells:#1 bad row", f"{m}/demo/DemoInternal.qml: tables order:#1 bad row",
            f"{m}/demo/DemoInternal.qml: tables cells:no axes", f"{m}/demo/DemoInternal.qml: tables order:first duplicate",
            f"{m}/demo/DemoInternal.qml: tables order:noWhy no why", f"{m}/demo/DemoInternal.qml: tables order:no catch-all",
            f"{m}/demo/DemoInternal.qml: tables ranks:not literal", f"{m}/demo/DemoInternal.qml: tables unnamed:rule noSuchRule",
            f"{m}/demo/DemoRules.qml: tables rows:kind=c uncovered",
            "scripts/engines.json: tables demo.tables:DemoRules.gone", "scripts/engines.json: tables sink.tables:not an object",
            "scripts/engines.json: tables demo.tables:DemoInternal.idRanks", f"{m}/demo/DemoKit.qml: tables grid:axes not literal",
            f"{m}/demo/DemoEngine.qml: shape api.drawnX:['x']",
            f"{m}/DemoFlat.qml: tables ranks:a no why", "qml/components/DemoItem.qml: alone kindOf:demoKindOf",
            "tests/demo/Rows.js: contract api.pick:no row", "tests/demo/Rows.js: contract rule.kindB:no row",
            "tests/demo/Rows.js: contract DEMO-20:call nope", "tests/demo/Rows.js: contract DEMO-21:args",
            "tests/sink/Rows.js: contract sink.rows:unreadable",
            "scripts/engines.json: edit-points lone.editPoints:not an object", "scripts/engines.json: alone lone.alone:not a list",
            "scripts/engines.json: edit-points demo.editPoints.consumer:DemoGone",
            "scripts/engines.json: edit-points demo.editPoints.rule:DemoRules.nope",
            "docs/dev/core/demo-engine.md: doc demo:9 Checks", "docs/dev/core/demo-engine.md: doc demo:4 Outputs",
            "scripts/engines.json: doc lone.doc:docs/dev/core/gone.md"]]), [], out)
        lines = out.splitlines()
        for absent in ("once:", "oldRule", "atLimit:lines", "api api.solve:in", "api api.drawn:in", "dag api:", "api.drawn:no row",
                       "DemoItem.qml: facade-only", "#1 duplicate", "Traceback", "api api.drawnX"):
            self.assertEqual([l for l in lines if absent in l], [], out)
        self.assertEqual(len([l for l in lines if "DEMO-21" in l]), 1, out)
        self.assertEqual([l for l in lines if "lone" in l and "contract" in l], [], out)

    @staticmethod
    def break_shapes(data):
        data["demo"]["kits"] = ["DemoKit"]
        data["demo"]["tables"].update({"DemoRules.gone": {"kind": "cell"}, "DemoInternal.cells": {"kind": "cell"},
                                       "DemoInternal.order": {"kind": "ordered"}, "DemoInternal.ranks": {"kind": "rank"},
                                       "DemoInternal.idRanks": {"kind": "rank", "id": ["a"]}, "DemoKit.grid": {"kind": "cell"}})
        data["demo"]["editPoints"]["consumer"] = "DemoGone"
        data["demo"]["editPoints"]["rule"] = ["DemoRules", "DemoRules.nope"]
        data["$flat"] = {"DemoFlat": {"prefix": "DEMOF", "tables": {"DemoFlat.ranks": {"kind": "rank"}}}}
        data["lone"] = {**data["sink"], "prefix": "DEMOL", "facade": "LoneEngine", "folder": "qml/components/methods/lone", "fedBy": {},
                        "tests": {"rows": "tests/lone/Rows.js"}, "doc": "docs/dev/core/gone.md",
                        "editPoints": [], "alone": {}}
        data["sink"]["tables"] = []


class GenDocsEngines(unittest.TestCase):
    """scripts/gen_docs.py renders the engine pages from the manifest: the fixture engines' manifest, API and
    rules pages, and an empty manifest's one page."""

    def engine_pages(self, root):
        """gen_docs.engine_pages() run in a child Python on the fixture copy: its {path: text}."""
        code = "import json, sys; sys.path.insert(0, 'scripts'); import gen_docs; print(json.dumps(gen_docs.engine_pages()))"
        done = subprocess.run([sys.executable, "-c", code], cwd=root, capture_output=True, text=True, check=True)
        return json.loads(done.stdout)

    def test_no_engine(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fixture_root(tmp)
            write(root, "scripts/engines.json", manifest_text())
            pages = self.engine_pages(root)
            self.assertEqual(set(pages), {"docs/dev/generated/engine-manifest.md"})
            text = pages["docs/dev/generated/engine-manifest.md"]
            self.assertTrue(text.startswith("<!-- Generated by scripts/gen_docs.py"))
            self.assertIn("No engine is listed in `scripts/engines.json`.", text)
            self.assertNotIn("## Graph", text)

    def test_fixture_engines(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fixture_root(tmp, "docs/dev/core/engines.md")
            demo_engine(root)
            edit_json(root / "scripts/engines.json", lambda data: data["$flat"].update(
                {"DemoFlat": {"prefix": "DEMOF", "tables": {"DemoFlat.ranks": {"kind": "rank"}}}}))
            write(root, "qml/components/methods/DemoFlat.qml", qml('property var ranks: [{"name": "a", "rank": 1, "why": "a rank"}]'))
            pages = self.engine_pages(root)
            out = "docs/dev/generated"
            self.assertEqual(set(pages), {f"{out}/engine-manifest.md", f"{out}/engines/DemoEngine.md", f"{out}/engines/SinkEngine.md",
                                          f"{out}/rules/DemoRules.rows.md", f"{out}/rules/DemoFlat.ranks.md"})
            api = pages[f"{out}/engines/DemoEngine.md"]
            for part in ("### model", "### solve", "### drawn", "### pick", "- extra", "| `items` | `DemoRules.itemsOf` |"):
                self.assertIn(part, api)
            self.assertTrue(any(line.startswith("| `output` |") for line in api.splitlines()))
            rules = pages[f"{out}/rules/DemoRules.rows.md"]
            for part in ("kindA", "kindB", "a is one wide", "b takes the tuned size", "- `kind`: `a`, `b`"):
                self.assertIn(part, rules)
            self.assertIn("a rank", pages[f"{out}/rules/DemoFlat.ranks.md"])
            text = pages[f"{out}/engine-manifest.md"]
            for part in ("[`DemoEngine`](engines/DemoEngine.md)", "### demo", "where a case goes: `DemoRules.rows`",
                         "where a tuning value goes: `DemoEngine.tuning`", "- [`DemoRules.rows`](rules/DemoRules.rows.md): cell table of `demo`",
                         "- [`DemoFlat.ranks`](rules/DemoFlat.ranks.md): rank table of `$flat.DemoFlat`"):
                self.assertIn(part, text)
            self.assertTrue(any(line.startswith("| `demo` |") for line in text.splitlines()))
            self.assertIn("\n".join(["REST", "  demo.model ──> demo.solve", "  demo.solve ──> sink.model (demoFeed)",
                                     "  sink.model ──> sink.solve", "INTAKE", "  demo.model ⇢ demo.solve  demoSeeded",
                                     "DRAWN", "  demo.solve ──> demo.drawn"]), text)


class CheckPackages(unittest.TestCase):
    """scripts/check_packages.py fails when install.sh, Packages.qml and the
    PKGBUILDs drift: (file, text replaced, its replacement, the message)."""

    EDITS = [
        ("install.sh", '"grim|grim|grim"', '"grim|grim|grimm"', "grim on fedora is 'grimm', Packages.qml says 'grim'"),
        ("install.sh", '"git|git|git"', '"git|git|git"\n  "ghost|ghost|ghost"\n  "odd|odd"', "no key 'ghost' (install.sh installs it)"),
        ("install.sh", None, None, "PACKAGES row 'odd|odd' isn't key|arch|fedora"),
        ("install.sh", '"Package update checks|checkupdates|"', '"Package update checks|checkupdates|"\n  "Haunting|phantom|"', "feature 'Haunting' uses 'phantom', which isn't in PACKAGES"),
        ("install.sh", "REQUIRED=(git ", "REQUIRED=(specter git ", "'specter' isn't in PACKAGES"),
        ("install.sh", '  "pactl|libpulse|pulseaudio-utils"\n', "", "no PACKAGES row for 'pactl' (Packages.qml has it)"),
        ("packaging/aur/axiom-shell/PKGBUILD", "depends=('quickshell", "depends=('extra' 'quickshell",
         "axiom-shell/PKGBUILD: depends ['curl', 'extra', 'quickshell'] aren't"),
        ("packaging/aur/axiom-shell-git/PKGBUILD", "'wlsunset: night light (niri)'", "'phantom: boo'",
         "axiom-shell-git/PKGBUILD: optdepends phantom, which no install.sh feature or compositor installs"),
        ("packaging/aur/axiom-shell-git/PKGBUILD", None, None, "axiom-shell-git/PKGBUILD: no optdepends for wlsunset"),
    ]

    def test_each_rule_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fixture_root(tmp, "install.sh", "qml/components/methods/Packages.qml", "packaging/aur")
            for path, old, new, _ in self.EDITS:
                if old:
                    text = (root / path).read_text()
                    self.assertIn(old, text)
                    (root / path).write_text(text.replace(old, new, 1))
            code, out = run_check(root, "check_packages.py")
        self.assertEqual(code, 1)
        self.assertEqual(missed(out, [m for *_, m in self.EDITS]), [], out)


class CheckShaders(unittest.TestCase):
    """scripts/check_shaders.py fails when a wallpaper shader's .qsb is stale
    or missing, or a .qsb or stamp has no source."""

    SHADERS = "qml/components/surfaces/wallpaper/shaders"

    def test_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, out = run_check(fixture_root(tmp, self.SHADERS), "check_shaders.py")
        self.assertEqual(code, 0, out)

    def test_each_rule_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fixture_root(tmp, self.SHADERS)
            shaders = root / self.SHADERS
            (shaders / "fade.frag").write_text((shaders / "fade.frag").read_text() + "// edited\n")
            (shaders / "wipe.frag.qsb").unlink()
            (shaders / "ghost.frag.qsb").write_bytes(b"x")
            (shaders / "stamps.txt").write_text((shaders / "stamps.txt").read_text() + "00  gone.frag\n")
            code, out = run_check(root, "check_shaders.py")
        self.assertEqual(code, 1)
        for message in ("fade.frag: changed since its .qsb was built", "wipe.frag: no wipe.frag.qsb",
                        "ghost.frag.qsb: no source ghost.frag", "a stamp for gone.frag"):
            self.assertIn(message, out)


class CheckIcons(unittest.TestCase):
    """scripts/check_icons.py finds icon names the font doesn't have, where
    a literal can be shown, and leaves other strings alone."""

    def test_finds_unknown_names(self):
        sys.path.insert(0, str(SCRIPTS))
        import check_icons
        qml = "\n".join([
            "Item {",
            '  icon: "wifi"',
            '  connectedIcon: on ? "shield_lock" : "shieldd_lock"',
            '  icon: ["ticker", "stacked"].includes(style) ? "bogus_one" : ""',
            '  icon: mode === "not_shown" ? "wifi" : "\uf001"',
            '  glyph: "nope_glyph" // not an icon: a test',
            "  StyledIcon {",
            '    text: "bogus_text"',
            "    Item {",
            '      text: "plain_text"',
            "    }",
            "  }",
            '  readonly property var _actionIcons: ({',
            '      "lock": "lock",',
            '      "x": "bogus_map"',
            "    })",
            '  text: "not_an_icon_context"',
            "}",
        ])
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "qml/components").mkdir(parents=True)
            (Path(tmp) / "qml/components/A.qml").write_text(qml)
            old_root, check_icons.ROOT, check_icons.errors = check_icons.ROOT, Path(tmp), []
            try:
                check_icons.check_qml({"wifi", "shield_lock", "lock"})
            finally:
                check_icons.ROOT = old_root
        self.assertEqual(check_icons.errors, [
            "error    qml/components/A.qml:3: no icon named 'shieldd_lock'",
            "error    qml/components/A.qml:4: no icon named 'bogus_one'",
            "error    qml/components/A.qml:8: no icon named 'bogus_text'",
            "error    qml/components/A.qml:15: no icon named 'bogus_map'",
        ])

    def test_the_tree_passes(self):
        done = subprocess.run([sys.executable, str(SCRIPTS / "check_icons.py")], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout)


class CheckSizes(unittest.TestCase):
    """scripts/check_sizes.py finds sizes written as numbers outside the bars."""

    def test_finds_literal_sizes(self):
        sys.path.insert(0, str(SCRIPTS))
        from check_sizes import find_literals
        qml = "\n".join([
            "Item {",
            "  implicitWidth: 380",
            "  spacing: 2",
            "  border.width: 4",
            "  property int listMargin: 6",
            "  troughHeight: Widget.px(6)",
            "  height: Widget.height",
            "  Layout.preferredHeight: 24",
            "  opacity: 50",
            "  textSize: Appearance.fontSize - 2",
            "  iconSize: Appearance.fontSize * 2",
            "  pixelSize: Appearance.fontSizeBy(-2)",
            "  readonly property int pad: 18",
            "  readonly property real inset: 6",
            "  readonly property real endInset: Widget.px(6)",
            "}",
        ])
        self.assertEqual([(n, name) for n, name, _ in find_literals(qml)],
                         [(2, "implicitWidth"), (5, "listMargin"), (8, "Layout.preferredHeight"),
                          (10, "fontSize"), (13, "pad"), (14, "inset")])

    def test_finds_literals_in_expressions(self):
        sys.path.insert(0, str(SCRIPTS))
        from check_sizes import find_literals
        qml = "\n".join([
            "Item {",
            "  implicitHeight: Widget.height - 4",
            "  anchors.margins: -48",
            "  width: wide ? 8 : Widget.px(4)",
            "  radius: (root.height - 6) / 2",
            "  textSize: Appearance.fontSize * (stacked ? 4 : 3)",
            "  height: Math.max(1, root.width / Math.max(1, Math.min(count, 3)))",
            "  implicitHeight: root.grid.span(8) + Widget.px(12)",
            "  width: parent.width * 0.5 - 1",
            "  sourceSize: Qt.size(128, 128)",
            "  borderWidth: selected ? 3 : 2",
            "}",
        ])
        self.assertEqual([(n, value) for n, _, value in find_literals(qml)],
                         [(2, "4"), (3, "48"), (4, "8"), (5, "6")])


class CheckStyle(unittest.TestCase):
    """scripts/check_style.py: each rule R1 to R20 on a fixture file, the waivers, the scope, every hit failing and the role check."""
    HEAD = "pragma ComponentBehavior: Bound\nimport QtQuick\nimport qs.config\n// A fixture.\n"
    UI = "qml/components/reusable/X.qml"
    STYLED = {"qml/components/reusable/StyledText.qml": HEAD + "Text {\n}\n",
              "qml/components/reusable/StyledLabel.qml": HEAD + "StyledText {\n}\n"}

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "scripts").mkdir()
        for name in ("check_style.py", "qml_modules.py"):
            shutil.copy(SCRIPTS / name, self.root / "scripts" / name)

    def put(self, files):
        for path, text in files.items():
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_text(text)

    def hits(self, body, path=None, extra=None):
        """The rule of every hit `--files` prints for a fixture file whose root block holds `body`."""
        path = path or self.UI
        files = {path: self.HEAD + "Item {\n" + body + "\n}\n"}
        files.update(extra or {})
        self.put(files)
        code, out = run_check(self.root, "check_style.py", "--files", path)
        self.assertEqual(code, 1 if out.strip() else 0, out)
        return [line.split(": ")[1].split(" ")[0] for line in out.splitlines() if line.startswith(path + ":")]

    def rule(self, body, rule, **kw):
        return self.hits(body, **kw).count(rule)

    def test_r1_theme_reads(self):
        self.assertEqual(self.rule("  color: Theme.accent", "R1"), 1)
        self.assertEqual(self.rule("  property var x: [Theme.baseColorNames, Theme.roles, Theme.name]", "R1"), 0)
        self.assertEqual(self.rule("  property string x: CursorThemeManager.xcursorTheme.startsWith('a')", "R1"), 0)
        self.assertEqual(self.rule("  property var x: [Theme.a, Theme.b]", "R1"), 2)

    def test_r2_raw_colours(self):
        for text in ("Qt.alpha(Style.text, 0.5)", "Qt.rgba(0, 0, 0, 1)", "Qt.lighter(Style.text)", '"#ff0000"', '"black"'):
            self.assertEqual(self.rule(f"  property var x: {text}", "R2"), 1, text)
        self.assertEqual(self.rule('  property var x: "transparent"', "R2"), 0)

    def test_r3_opacity(self):
        self.assertEqual(self.rule("  opacity: 0.5", "R3"), 1)
        self.assertEqual(self.rule("  inkOpacity: x ? 0.6 : 1", "R3"), 1)
        self.assertEqual(self.rule("  property real fillOpacity: .45", "R3"), 1)
        self.assertEqual(self.rule("  opacity: x ? 0 : 1", "R3"), 0)
        self.assertEqual(self.rule('  NumberAnimation { property: "opacity"; to: 0.35 }', "R3"), 1)
        self.assertEqual(self.rule("  NumberAnimation on opacity { from: 0; to: 1 }", "R3"), 0)

    def test_r4_sizes(self):
        self.assertEqual(self.rule("  textSize: Appearance.fontSizeBy(2)", "R4"), 1)
        self.assertEqual(self.rule("  textSize: Appearance.fontSize", "R4"), 1)
        self.assertEqual(self.rule("  textSize: 14", "R4"), 1)
        self.assertEqual(self.rule("  textSize: Style.iconSm", "R4"), 0)
        self.assertEqual(self.rule("  font.pixelSize: Appearance.fontSizeLarge", "R4"), 1)
        self.assertEqual(self.rule("  fontSizeMode: Text.Fit", "R4"), 1)
        self.assertEqual(self.rule("  fontSizeMode: Text.Fit\n  minimumPixelSize: Style.typeMicro", "R4"), 0)
        self.assertEqual(self.rule("  textSize: Math.max(Style.typeMicro, box * 0.5) // fitted: the box", "R4"), 0)
        self.assertEqual(self.rule("  textSize: box * 0.5 // fitted: the box", "R4"), 1)
        self.assertEqual(self.rule("  textSize: Math.max(Style.typeMicro, Tone.x(box)) // fitted: the box", "R4"), 0)
        self.assertEqual(self.rule("  textSize: Math.max(Style.typeMicro, Tone.x(box)) // fitted: the box", "R6"), 1)

    def test_r5_weights(self):
        self.assertEqual(self.rule("  font.bold: true", "R5"), 1)
        self.assertEqual(self.rule("  font.weight: x ? Style.weightMedium : Style.weightNormal", "R5"), 0)
        self.assertEqual(self.rule("  font.weight: x ? Style.weightMedium : Font.Bold", "R5"), 1)
        self.assertEqual(self.rule("  font.weight: Style.roleLabel.weight", "R5"), 0)
        self.assertEqual(self.rule("  font.bold: true", "R5", path="qml/components/bar/widgets/base/X.qml"), 1)
        self.assertEqual(self.rule("  font.bold: true", "R5", path="qml/components/bar/widgets/Clock/X.qml"), 0)

    def test_r6_colour_functions(self):
        self.assertEqual(self.rule("  property var x: Tone.mix(a, b, 0.5)", "R6"), 1)
        self.assertEqual(self.rule("  property var x: Utils.contrast(a, b)", "R6"), 1)
        self.assertEqual(self.rule("  property var x: Style.inkOf('raised').text", "R6"), 0)
        service = "qml/services/core/X.qml"
        self.assertEqual(self.rule('  property var x: ({ "c": String(WindowLookConfig.activeBorder) })', "R6", path=service), 1)
        self.assertEqual(self.rule("  property var x: String(ThemeManager.wallpaper)", "R6", path=service), 0)

    def test_r7_colour_operands(self):
        self.assertEqual(self.rule("  color: x ? Style.accent : Style.textMuted", "R7"), 0)
        self.assertEqual(self.rule("  color: x ? Style.accent : Theme.foreground", "R7"), 1)
        self.assertEqual(self.rule("  color: c && Style.accent", "R7"), 0)
        self.assertEqual(self.rule("  color: Theme.a ?? Style.accent", "R7"), 1)
        self.assertEqual(self.rule("  color: Theme.a ? Style.accent : Style.text", "R7"), 0)
        self.assertEqual(self.rule("  color: chip.ink.text\n  Item { id: chip }", "R7"), 0)
        self.assertEqual(self.rule("  color: changedEntry.ink\n  Item { id: changedEntry }", "R7"), 0)
        self.assertEqual(self.rule("  color: other.ink", "R7"), 1)
        self.assertEqual(self.rule("  color: WorkspaceOverlayConfig.color", "R7"), 0)
        self.assertEqual(self.rule("  textColor: MenusConfig.colorsOf(root.menu).fill", "R7"), 0)
        self.assertEqual(self.rule('  border.color: "transparent"', "R7"), 0)
        self.assertEqual(self.rule("  iconColor: Style.edgeFill(Style.accent, true)", "R7"), 0)
        self.assertEqual(self.rule("  iconColor: Style.edgeFill(Theme.accent, true)", "R7"), 1)

    def test_r8_clipping_rectangle(self):
        self.assertEqual(self.rule("  ClippingRectangle {\n    radius: 4\n  }", "R8"), 1)
        self.assertEqual(self.rule('  ClippingRectangle {\n    color: "transparent"\n  }', "R8"), 0)

    def test_r9_palette_parts(self):
        self.assertEqual(self.rule("  ScrollIndicator {\n  }", "R9"), 1)
        self.assertEqual(self.rule("  ScrollIndicator {\n    contentItem: Item {}\n  }", "R9"), 0)
        self.assertEqual(self.rule("  TextField {\n  }", "R9"), 1)
        self.assertEqual(self.rule("  TextField {\n    selectionColor: Style.accent\n  }", "R9"), 0)
        self.assertEqual(self.rule("  Popup {\n  }", "R9"), 1)

    def test_r10_canvas(self):
        body = "  Canvas {\n    onPaint: { var c = Style.text; }\n  }"
        self.assertEqual(self.rule(body, "R10"), 1)
        self.assertEqual(self.rule(body + "\n  property int k: Style.revision", "R10"), 0)
        self.assertEqual(self.rule("  Canvas {\n    property color lineColor: 'red'\n    onLineColorChanged: requestPaint()\n"
                                   "    onPaint: { var c = root.lineColor; }\n  }", "R10"), 0)

    def test_r11_redeclared_property(self):
        extra = {"qml/components/reusable/Base.qml": self.HEAD + "Item {\n  property int count: 0\n  signal picked\n}\n",
                 "qml/components/reusable/Mid.qml": self.HEAD + "Base {\n}\n"}
        self.put(extra)
        self.put({self.UI: self.HEAD + "Mid {\n  property string count: ''\n  signal picked\n}\n"})
        code, out = run_check(self.root, "check_style.py", "--files", self.UI)
        self.assertEqual(out.count("R11"), 2, out)
        self.put({self.UI: self.HEAD + "Item {\n  component Inner: Mid {\n    property int count: 1\n  }\n}\n"})
        code, out = run_check(self.root, "check_style.py", "--files", self.UI)
        self.assertEqual(out.count("R11"), 1, out)
        # two blocks opened on one line, and a block named in a comment
        self.put({self.UI: self.HEAD + "Item {\n  Item { Base { property int count: 1 } }\n  /* Base { property int count: 1 } */\n}\n"})
        code, out = run_check(self.root, "check_style.py", "--files", self.UI)
        self.assertEqual(out.count("R11"), 1, out)

    def test_r12_inherited_ink(self):
        surface = {"qml/components/reusable/Surface.qml": self.HEAD + "Rectangle {\n  property string tone: 'surface'\n}\n"}
        self.assertEqual(self.rule('  Surface {\n    tone: "highest"\n    StyledText { textColor: Style.text }\n  }', "R12",
                                   extra={**surface, **self.STYLED}), 1)
        self.assertEqual(self.rule('  Surface {\n    tone: "accentContainer"\n    StyledText {\n      tone: "error"\n    }\n  }', "R12",
                                   extra={**surface, **self.STYLED}), 1)
        self.assertEqual(self.rule('  Surface {\n    tone: "accent"\n    Item { border.color: Style.focusRing }\n  }', "R12",
                                   extra={**surface, **self.STYLED}), 1)
        self.assertEqual(self.rule('  Surface {\n    tone: "highest"\n    StyledText { text: x }\n    StyledText {\n      tone: "muted"\n    }\n'
                                   '    Item { color: Style.accentContainer }\n    Item { color: Style.accentWash }\n  }', "R12",
                                   extra={**surface, **self.STYLED}), 0)
        self.assertEqual(self.rule('  Surface {\n    tone: "highest"\n    Surface {\n      tone: "surface"\n      Item { color: Style.text }\n    }\n  }',
                                   "R12", extra=surface), 0)

    def test_r13_bold_on_styled_text(self):
        self.assertEqual(self.rule("  StyledLabel { font.bold: true }", "R13", extra=self.STYLED), 1)
        self.assertEqual(self.rule("  component X: StyledText {\n    font.bold: true\n  }", "R13", extra=self.STYLED), 1)
        self.assertEqual(self.rule("  StyledText { font { bold: true } }", "R13", extra=self.STYLED), 1)
        self.assertEqual(self.rule("  Text { font.bold: true }", "R13", extra=self.STYLED), 0)
        self.assertEqual(self.rule("  FontMetrics { font.bold: true }", "R13", extra=self.STYLED), 0)
        self.assertEqual(self.rule("  StyledLabel { font.bold: true }", "R13", extra=self.STYLED, path="qml/components/bar/widgets/Clock/X.qml"), 1)

    def test_r14_raw_wrap_and_elide(self):
        self.assertEqual(self.rule("  StyledLabel { wrapMode: Text.WordWrap }", "R14", extra=self.STYLED), 1)
        self.assertEqual(self.rule("  StyledLabel { elide: Text.ElideRight; maximumLineCount: 2 }", "R14", extra=self.STYLED), 2)
        self.assertEqual(self.rule("  TextMetrics { elide: Text.ElideRight }", "R14", extra=self.STYLED), 0)
        self.assertEqual(self.rule("  StyledLabel { elide: Text.ElideMiddle } // style-exempt: middle", "R14", extra=self.STYLED), 0)
        self.assertEqual(self.rule('  StyledLabel { overflow: "wrap" }', "R14", extra=self.STYLED), 0)

    def test_r15_dead_elide(self):
        row = "  RowLayout {\n    StyledLabel { %s }\n  }"
        self.assertEqual(self.rule(row % "elide: Text.ElideRight", "R15", extra=self.STYLED), 1)
        self.assertEqual(self.rule(row % 'overflow: "line"', "R15", extra=self.STYLED), 1)
        self.assertEqual(self.rule(row % "elide: Text.ElideRight; Layout.fillWidth: true", "R15", extra=self.STYLED), 0)
        self.assertEqual(self.rule(row % "elide: Text.ElideRight; Layout.maximumWidth: 100", "R15", extra=self.STYLED), 0)
        self.assertEqual(self.rule("  ColumnLayout {\n    StyledLabel { elide: Text.ElideRight }\n  }", "R15", extra=self.STYLED), 0)

    def test_r16_render_type(self):
        line = "renderType: TextRender.typeFor(TextRender.zoomAt(parent), false, 0)"
        self.assertEqual(self.rule("  Text {\n  }", "R16"), 1)
        self.assertEqual(self.rule(f"  Text {{\n    {line}\n  }}", "R16"), 0)
        self.assertEqual(self.rule("  Text {\n    renderType: Text.NativeRendering\n  }", "R16"), 2)
        self.assertEqual(self.rule("  Text {\n  }", "R16", path="qml/components/bar/widgets/Clock/X.qml"), 1)
        # an inline definition counts once, its uses not at all
        self.assertEqual(self.rule("  component D: Text {\n  }\n  D {}\n  D {}", "R16"), 1)
        # StyledText's own root states it from its zoom walk
        self.put({"qml/components/reusable/StyledText.qml":
                  self.HEAD + "Text {\n  renderType: TextRender.typeFor(root._drawnZoom, false, 0)\n}\n"})
        code, out = run_check(self.root, "check_style.py", "--files", "qml/components/reusable/StyledText.qml")
        self.assertNotIn("R16", out)

    def test_r17_layers(self):
        self.assertEqual(self.rule("  layer.enabled: true", "R17"), 1)
        self.assertEqual(self.rule("  layer.enabled: false", "R17"), 0)
        self.assertEqual(self.rule("  layer.effect: MultiEffect {\n  }", "R17"), 1)
        self.assertEqual(self.rule("  layer.effect: MultiEffect { // style-exempt: no text\n  }", "R17"), 0)

    def test_r20_glide_to_transparent(self):
        glide = "  ColorGlide on color {}"
        self.assertEqual(self.rule('  color: root.on ? Style.accent : "transparent"\n' + glide, "R20"), 1)
        self.assertEqual(self.rule('  border.color: root.on ? Style.accent : "transparent"\n  ColorGlide on border.color {}', "R20"), 1)
        self.assertEqual(self.rule('  color: root.on ? Style.accent : "transparent"\n  Behavior on color {\n    ColorAnimation {\n    }\n  }', "R20"), 1)
        self.assertEqual(self.rule('  color: root.on ? Style.accent : "transparent"\n  ColorAnimation on color {\n  }', "R20"), 1)
        self.assertEqual(self.rule('  color: "transparent"\n' + glide, "R20"), 1)
        self.assertEqual(self.rule('  color: root.on ? Style.accent : Qt.alpha(Style.accent, 0) // style-exempt: rests on its hue\n' + glide, "R20"), 0)
        self.assertEqual(self.rule('  color: root.on ? Style.accent : "transparent"', "R20"), 0)
        self.assertEqual(self.rule('  color: root.on ? Style.accent : "transparent"\n  Glide on width {}', "R20"), 0)
        self.assertEqual(self.rule('  color: "transparent"\n  border.color: Style.accent\n  ColorGlide on border.color {}', "R20"), 0)
        self.assertEqual(self.rule('  color: root.on ? "transparent" : Style.accent\n' + glide, "R20"), 1)

    def test_r19_widget_radius(self):
        self.assertEqual(self.rule("  radius: Widget.radius", "R19"), 1)
        self.assertEqual(self.rule("  radius: Widget.radius / 2", "R19"), 1)
        self.assertEqual(self.rule("  radius: Style.radius", "R19"), 0)
        self.assertEqual(self.rule("  // Widget.radius in a comment", "R19"), 0)
        self.assertEqual(self.rule("  radius: Widget.radius", "R19", path="qml/config/X.qml"), 0)

    def test_r21_trough(self):
        self.assertEqual(self.rule("  color: Style.trough", "R21"), 1)
        self.assertEqual(self.rule("  color: Style.trough", "R21", path="qml/components/content/X/X.qml"), 1)
        for piece in ("StyledVolumeBar", "StyledSlider", "LevelMeter", "SegmentMeter", "PercentageCircle"):
            self.assertEqual(self.rule("  color: Style.trough", "R21", path=f"qml/components/reusable/{piece}.qml"), 0, piece)
        self.assertEqual(self.rule("  // Style.trough in a comment", "R21"), 0)
        self.assertEqual(self.rule("  color: Style.trough // style-exempt: a band, not a meter", "R21"), 0)
        self.assertEqual(self.rule("  color: Style.trough", "R21", path="qml/config/X.qml"), 0)

    def test_r18_scale(self):
        self.assertEqual(self.rule("  scale: 0.92", "R18"), 1)
        self.assertEqual(self.rule("  scale: 1", "R18"), 0)
        self.assertEqual(self.rule("  scale: root.zoom\n  readonly property real contentZoom: scale", "R18"), 0)
        self.assertEqual(self.rule("  readonly property real contentZoom: scale\n  scale: root.zoom", "R18"), 0)
        self.assertEqual(self.rule("  readonly property real contentZoom: scale\n  Item {\n    scale: 0.5\n  }", "R18"), 0)
        self.assertEqual(self.rule("  property var x: ({ a: 1, scale: 2, b: 3 })", "R18"), 0)
        self.assertEqual(self.rule("  scale: 0.5 // style-exempt: no text", "R18"), 0)
        self.assertEqual(self.rule("  transform: Scale { xScale: s }", "R18"), 1)
        self.assertEqual(self.rule("  property real contentZoom: 1\n  transform: Scale { xScale: s }", "R18"), 0)
        self.assertEqual(self.rule('  NumberAnimation { property: "scale" }', "R18"), 1)
        self.assertEqual(self.rule('  NumberAnimation { properties: "x,scale" }', "R18"), 1)
        self.assertEqual(self.rule('  NumberAnimation { property: "opacity" }', "R18"), 0)

    def test_waivers(self):
        self.assertEqual(self.rule('  property var x: "black" // style-exempt: mask', "R2"), 0)
        # a file's exception waives its rule
        self.put({"scripts/style-exceptions.json": json.dumps({self.UI: {"rules": ["R1"], "reason": "a fixture"}}),
                  self.UI: self.HEAD + "Item {\n  property var x: Theme.accent\n}\n"})
        self.assertEqual(run_check(self.root, "check_style.py")[0], 0)

    def test_a_file_level_r21_exception_is_accepted(self):
        self.put({"scripts/style-exceptions.json": json.dumps({self.UI: {"rules": ["R21"], "reason": "a fixture"}}),
                  self.UI: self.HEAD + "Item {\n  color: Style.trough\n}\n"})
        code, out = run_check(self.root, "check_style.py")
        self.assertEqual(code, 0, out)

    def test_a_malformed_exception_is_an_error_not_a_traceback(self):
        self.put({"scripts/style-exceptions.json": json.dumps({self.UI: "R1"}),
                  self.UI: self.HEAD + "Item {\n}\n"})
        code, out = run_check(self.root, "check_style.py")
        self.assertNotEqual(code, 0)
        self.assertIn("is not an object", out)
        self.assertNotIn("Traceback", out)

    def test_scope(self):
        for path in ("qml/config/Style.qml", "qml/components/methods/X.qml", "qml/components/reusable/Surface.qml",
                     "qml/components/bar/widgets/Clock/X.qml", "qml/components/bar/widgets/base/X.qml"):
            self.assertEqual(self.rule("  property var x: Theme.accent", "R1", path=path), 0, path)
        self.assertEqual(self.rule("  property var x: Theme.a", "R1", path="qml/services/core/Y.qml"), 1)
        self.assertEqual(self.rule("  font.bold: true", "R13", path="qml/config/Style.qml"), 0)
        # only R1, R2 and R6 reach a service
        self.assertEqual(self.rule("  color: Theme.accent", "R7", path="qml/services/core/Y.qml"), 0)

    def test_files(self):
        self.put({self.UI: self.HEAD + "Item {\n  property var x: Theme.accent\n}\n",
                  "qml/components/reusable/Y.qml": self.HEAD + "Item {\n  property var x: Theme.accent\n}\n"})
        code, out = run_check(self.root, "check_style.py", "--files", self.UI)
        self.assertEqual(code, 1)
        self.assertIn(f"{self.UI}:6: R1", out)
        self.assertNotIn("Y.qml", out)

    def check(self, *args):
        return run_check(self.root, "check_style.py", *args)

    def test_any_hit_fails(self):
        self.put({self.UI: self.HEAD + 'Item {\n  property var x: "#ff0000"\n}\n'})
        code, out = self.check()
        self.assertEqual(code, 1)
        self.assertIn(f"{self.UI}:6: R2", out)

    def test_counting_unit(self):
        text = self.HEAD + ("Item {\n  property var a: [Theme.a, Theme.b]\n  // property var b: Theme.c\n"
                            "  /* property var c: Theme.d */\n  property var d: Theme.e // style-exempt: a test\n"
                            "  property var e: \"// Theme.f\"\n}\n")
        self.put({self.UI: text})
        code, out = self.check()
        self.assertEqual(code, 1)
        # a comment's match and a waived line's count nothing; a match inside a string literal stays
        self.assertEqual(out.count(": R1 "), 3, out)

    def test_unused_role_fails(self):
        self.put({"qml/config/Style.qml": self.HEAD + "Item {\n  readonly property color unusedRole: \"red\"\n}\n"})
        code, out = self.check()
        self.assertEqual(code, 1)
        self.assertIn("Style.qml: unused role unusedRole", out)
        self.assertEqual(self.check("--roles")[0], 1)

    def test_role_read_by_piece_counts(self):
        self.put({"qml/config/Style.qml": self.HEAD + "Item {\n  readonly property color fillRole: \"red\"\n}\n",
                  "qml/components/reusable/Surface.qml": self.HEAD + "Item {\n  color: Style.fillRole\n}\n"})
        self.assertEqual(self.check("--roles"), (0, ""))

    def test_role_read_through_a_switch_counts(self):
        style = self.HEAD + ("Item {\n  readonly property color successText: root.x\n"
                             "  function toneColor(name) {\n    switch (name) {\n    case \"success\":\n"
                             "      return root.successText;\n    }\n  }\n}\n")
        self.put({"qml/config/Style.qml": style,
                  "qml/components/reusable/Y.qml": self.HEAD + "Item {\n  property var c: Style.toneColor(\"x\")\n}\n"})
        code, out = self.check("--roles")
        self.assertEqual(code, 0, out)

    def test_private_member_ignored(self):
        self.put({"qml/config/Style.qml": self.HEAD + "Item {\n  readonly property var _roles: ({})\n"
                                                      "  function _derive(a) { return a; }\n}\n"})
        self.assertEqual(self.check("--roles"), (0, ""))

    def test_stale_waivers(self):
        self.put({self.UI: self.HEAD + "Item {\n  width: 3 // style-exempt: nothing here\n}\n"})
        code, out = self.check()
        self.assertEqual(code, 1)
        self.assertIn("stale waiver", out)
        # an exception whose file is gone, or whose rule no file under it hits
        self.put({self.UI: self.HEAD + "Item {\n}\n", "scripts/style-exceptions.json": json.dumps(
            {self.UI: {"rules": ["R1"], "reason": "x"}, "qml/components/reusable/Gone.qml": {"rules": ["R1"], "reason": "x"}})})
        code, out = self.check()
        self.assertEqual(code, 1)
        self.assertIn("Gone.qml matches no file", out)
        self.assertIn("lists R1, which no file", out)

    def test_scope_covers_inventory(self):
        """The scanned UI files are the UI set, walked here independently of the script's walker: every .qml under
        qml/components but methods/, under qml/shell/, plus shell.qml and greeter.qml, less the style layer pieces
        and the bar widget type folders (those are check_structure's)."""
        sys.path.insert(0, str(SCRIPTS))
        import check_style
        qml_root = ROOT / "qml"
        expected = set()
        for path in sorted((qml_root / "components").rglob("*.qml")) + sorted((qml_root / "shell").rglob("*.qml")) \
                + [qml_root / "shell.qml", qml_root / "greeter.qml"]:
            rel = path.relative_to(ROOT).as_posix()
            if rel.startswith("qml/components/methods/"):
                continue
            if rel.startswith("qml/components/reusable/") and path.stem in check_style.STYLE_LAYER_PIECES:
                continue
            m = re.match(r"qml/components/bar/widgets/([^/]+)/", rel)
            if m and m.group(1) != "base":
                continue
            expected.add(rel)
        scanned = {rel for rel in (f.relative_to(ROOT).as_posix() for f in check_style.all_files())
                   if (rel.startswith(("qml/components/", "qml/shell/")) or rel in ("qml/shell.qml", "qml/greeter.qml"))
                   and check_style.scope_of(rel) - check_style.EVERYWHERE}
        self.assertEqual(sorted(expected - scanned), [])
        self.assertEqual(sorted(scanned - expected), [])


class CheckDocs(unittest.TestCase):
    """scripts/check_docs.py fails on each rule's breaking doc; a retired
    name that is also a schema definition only with a member that isn't a
    setting."""

    def test_retired_definition_name(self):
        sys.path.insert(0, str(SCRIPTS))
        from check_docs import retired_name
        configs = {"Bar.background", "Bars.items"}
        self.assertEqual(retired_name("PopoutConfig.openDelay", configs), "PopoutConfig")
        self.assertIsNone(retired_name("Bar", configs))
        self.assertIsNone(retired_name('Bar.background: "solid"', configs))
        self.assertEqual(retired_name("Bar.enrichBarConfig", configs), "Bar")
        self.assertEqual(retired_name("Bar.lookOf(bar)", configs), "Bar")
        self.assertIsNone(retired_name("BarsConfig.lookOf", configs))

    FILES = [
        ("docs/dev/ghost.md", "[a](nowhere.md)\n`services/core/GhostlyManager.qml`\n`AudioManager.noSuchMember`\n"
                              "`IconConfig.x`\n"),
        ("qml/components/reusable/GhostPiece.qml", qml()),
        (".claude/templates/ghost.md", "`.claude/templates/gone.md`\n"),
    ]

    def test_each_rule_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fixture_root(tmp, "docs", "qml", "CLAUDE.md", "AGENTS.md", "README.md", "CONTRIBUTING.md")
            edit_json(root / "qml/config/json/config.schema.json", lambda s: s.update({"x-ghost": True}))
            code, out = run_check(root, "check_docs.py", files=self.FILES)
        self.assertEqual(code, 1)
        self.assertEqual(missed(out, [
            "docs/dev/ghost.md:1: link to missing nowhere.md",
            "docs/dev/ghost.md:2: `services/core/GhostlyManager.qml` doesn't exist",
            "docs/dev/ghost.md:3: `AudioManager.noSuchMember`: AudioManager has no member noSuchMember",
            "docs/dev/ghost.md:4: `IconConfig.x`: IconConfig was renamed to IconsConfig",
            ".claude/templates/ghost.md:1: `.claude/templates/gone.md` doesn't exist",
            "qml/components/reusable/GhostPiece.qml: not in docs/dev/core/shared-ui-pieces.md",
            "`x-ghost` isn't in docs/dev/core/schema-annotations.md",
        ]), [], out)


def block_end(text, open_at):
    """The index of the brace closing the one at open_at."""
    depth = 0
    for i in range(open_at, len(text)):
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        if depth == 0:
            return i
    return len(text)


def handler_at(text, pos):
    """The function or on-handler whose body holds pos, and where it starts
    ("a binding", -1 for none): a function's braces, or a handler's own
    line and the braces opened on it."""
    found, start = "a binding", -1
    for m in re.finditer(r"function\s+(\w+)[^{]*\{|\b(on\w+)\s*:[^\n{]*(\{)?", text):
        body = m.end() - 1 if m.group(1) or m.group(3) else None
        stop = block_end(text, body) if body is not None else text.find("\n", m.end())
        if m.start() < pos <= stop and m.start() > start:
            found, start = m.group(1) or m.group(2), m.start()
    return found, start


def unlock_problems(files):
    """What lets the built-in lock screen unlock other than PAM's success,
    in `files` ({repo path: QML text}): a `locked = false` anywhere but
    qml/shell/Lockscreen.qml's onAuthenticationSucceeded (or its onSecureChanged
    once the compositor has ended the lock), a session lock not bound to
    its state, authenticationSucceeded emitted for anything but
    PamResult.Success, or the lockscreen IPC target taking more than lock."""
    problems = []
    for path, text in files.items():
        for m in re.finditer(r"\blocked\s*=\s*false", text):
            fn, start = handler_at(text, m.start())
            # The compositor's end: only as the statement of that one guard
            guarded = re.search(r"if \(!sessionLock\.locked && lockState\.locked\)\s*lockState\.$", text[start : m.start()])
            allowed = fn == "onAuthenticationSucceeded" or (fn == "onSecureChanged" and guarded)
            if path != "qml/shell/Lockscreen.qml" or not allowed:
                problems.append(f"{path}: unlocks in {fn}")
        for m in re.finditer(r"\bauthenticationSucceeded\(\)", text):
            case = re.findall(r"case\s+([\w.]+):", text[: m.start()])
            if path != "qml/services/session/AuthManager.qml" or not case or case[-1] != "PamResult.Success":
                problems.append(f"{path}: authenticationSucceeded after {case[-1] if case else 'no case'}")
        for m in re.finditer(r"IpcTarget\s*\{", text):
            block = text[m.end() : block_end(text, m.end() - 1)]
            if re.search(r'target:\s*"lockscreen"', block):
                functions = re.findall(r"function\s+(\w+)", block)
                if functions != ["lock"]:
                    problems.append(f"{path}: the lockscreen IPC target takes {functions}")
    lock = files.get("qml/shell/Lockscreen.qml", "")
    m = re.search(r"WlSessionLock\s*\{", lock)
    if not m or not re.search(r"^\s*locked:\s*lockState\.locked\s*$", lock[m.end() : block_end(lock, m.end() - 1)], re.M):
        problems.append("qml/shell/Lockscreen.qml: the session lock isn't bound to lockState.locked alone")
    return problems


class OnlyPamUnlocks(unittest.TestCase):
    """The built-in lock screen unlocks only on PAM's success, never by
    IPC (docs/dev/features/lockscreen.md). PAM itself can't run here, so
    the shell's QML is read: each way around it is tried on a copy and
    must be caught."""

    @classmethod
    def setUpClass(cls):
        tracked = subprocess.run(["git", "ls-files", "-z", "*.qml"], cwd=ROOT, capture_output=True, text=True, check=True)
        cls.files = {p: (ROOT / p).read_text() for p in tracked.stdout.split("\0") if p and not p.startswith("tests/")}

    def test_the_shell_unlocks_only_on_pam_success(self):
        self.assertEqual(unlock_problems(self.files), [])

    def broken(self, path, old, new):
        files = dict(self.files)
        self.assertIn(old, files.get(path, old))
        files[path] = files.get(path, old).replace(old, new, 1)
        return unlock_problems(files)

    def test_each_way_around_it_is_caught(self):
        lock, auth, ipc = "qml/shell/Lockscreen.qml", "qml/services/session/AuthManager.qml", "qml/services/session/LockManager.qml"
        for path, old, new in [
            # An IPC unlock
            (ipc, "function lock(): void {", "function unlock(): void {}\n    function lock(): void {"),
            # A failed attempt, a PAM error or a message that unlocks
            (auth, "case PamResult.Failed:", "case PamResult.Failed:\n        root.authenticationSucceeded();"),
            (auth, "onError: error => {", "onError: error => {\n      root.authenticationSucceeded();"),
            (lock, "function onLockRequested() {", "function onLockRequested() {\n      lockState.locked = false;"),
            # A handler of its own after PAM's, or the compositor's end unguarded
            (lock, "  WlSessionLock {", "  Timer {\n    onTriggered: lockState.locked = false\n  }\n\n  WlSessionLock {"),
            (lock, "if (!sessionLock.locked && lockState.locked)", "if (lockState.locked)"),
            (lock, "if (!sessionLock.locked && lockState.locked)", "if (!sessionLock.locked || true)"),
            (lock, "lockState.locked)\n        lockState.locked = false;", "lockState.locked) {}\n        lockState.locked = false;"),
            # Any other file unlocking, or the lock bound to something else
            ("qml/components/Unlock.qml", "", "Item { function go() { sessionLock.locked = false; } }"),
            (lock, "locked: lockState.locked\n", "locked: lockState.locked && !AuthManager.isAuthenticating\n"),
        ]:
            with self.subTest(path=path, new=new):
                self.assertNotEqual(self.broken(path, old, new), [])


class GreeterShim(unittest.TestCase):
    """greeter_install.sh, root's way into `axiom greeter-install` (its
    tests are Go's, backend/internal/greeterinstall): it hands its arguments
    on to the binary installed beside it, else /usr/bin/axiom, never one
    named by the environment."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.copy = self.tmp / "usr/share/axiom-greeter"
        (self.copy / "data/greeter").mkdir(parents=True)
        self.shim = self.copy / "data/greeter/greeter_install.sh"
        shutil.copy(ROOT / "data/greeter/greeter_install.sh", self.shim)
        self.env = scratch_env(self.tmp)
        # What the environment could name: never run
        planted = self.tmp / "planted"
        planted.write_text("#!/bin/sh\necho planted\n")
        planted.chmod(0o755)
        self.env.update({"AXIOM_BIN": str(planted), "PATH": f"{self.tmp}:{self.env['PATH']}"})
        # A real /usr/bin/axiom (a packaged one) acts only on a scratch root
        self.env["AXIOM_GREETER_ROOT"] = str(self.tmp / "root")
        (self.tmp / "axiom").symlink_to(planted)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_shim(self, *args):
        return subprocess.run(["sh", str(self.shim), *args], env=self.env, capture_output=True, text=True, timeout=30)

    def test_runs_the_binary_beside_it(self):
        binary = self.copy / "bin/axiom"
        binary.parent.mkdir()
        binary.write_text('#!/bin/sh\nfor a; do printf "[%s]" "$a"; done\n')
        binary.chmod(0o755)
        result = self.run_shim("update", "/r", "me", "", "local", "tags", "/b")
        self.assertEqual(result.stdout, "[greeter-install][update][/r][me][][local][tags][/b]")

    def test_falls_back_to_the_packaged_binary(self):
        result = self.run_shim("uninstall", "/r", "me")
        self.assertNotIn("planted", result.stdout)
        if not Path("/usr/bin/axiom").exists():
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("/usr/bin/axiom", result.stderr)

    def test_marks_a_helper_that_installs_the_binary(self):
        """The status's `binaries` reads this line (greeterinstall.binariesMarker)."""
        self.assertRegex(self.shim.read_text(), r"(?m)^# \(This helper installs the axiom binary too")


class GreeterSession(unittest.TestCase):
    """greeter-session.sh picking the greeter's compositor: sway, else
    Hyprland (also when sway can't start), else agreety. Run with a PATH of
    stand-ins only, so the real compositors are never found."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.calls = self.tmp / "calls"
        for tool in ["dirname", "readlink", "rm"]:
            (self.bin / tool).symlink_to(shutil.which(tool))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def fake(self, name, code=0):
        program = self.bin / name
        program.write_text(f'#!/bin/sh\necho "{name} $*" >>"{self.calls}"\nexit {code}\n')
        program.chmod(0o755)

    def run_session(self):
        env = {"PATH": str(self.bin), "XDG_RUNTIME_DIR": str(self.tmp)}
        subprocess.run(["/bin/sh", str(ROOT / "data/greeter/greeter-session.sh")], env=env,
                       capture_output=True, text=True, timeout=10)
        return [line.split()[0] for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def test_sway_first(self):
        self.fake("sway")
        self.fake("start-hyprland")
        self.fake("agreety")
        self.assertEqual(self.run_session(), ["sway"])
        self.assertIn("sway.conf", self.calls.read_text())

    def test_hyprland_when_sway_cant_start(self):
        self.fake("sway", 1)
        self.fake("start-hyprland")
        self.fake("agreety")
        self.assertEqual(self.run_session(), ["sway", "start-hyprland"])

    def test_hyprland_without_sway(self):
        self.fake("start-hyprland")
        self.fake("agreety")
        self.assertEqual(self.run_session(), ["start-hyprland"])

    def test_agreety_when_nothing_starts(self):
        self.fake("sway", 1)
        self.fake("agreety")
        self.assertEqual(self.run_session(), ["sway", "agreety"])

    def test_shell_runs_axiom_greeter_then_its_safe_mode(self):
        self.fake("axiom", 1)
        self.fake("hyprctl")
        env = {"PATH": str(self.bin), "XDG_RUNTIME_DIR": str(self.tmp)}
        subprocess.run(["/bin/sh", str(ROOT / "data/greeter/greeter-session.sh"), "shell"], env=env,
                       capture_output=True, text=True, timeout=10)
        calls = self.calls.read_text().splitlines()
        tree = str(ROOT)
        self.assertEqual(calls[:2], [f"axiom greeter --tree {tree}", f"axiom greeter --tree {tree} --safe"])
        self.assertTrue((self.tmp / "axiom-greeter-failed").exists())

    def test_agreety_when_the_greeter_failed_twice(self):
        # The greeter's `shell` leaves the marker, then sway exits cleanly
        marker = self.tmp / "axiom-greeter-failed"
        program = self.bin / "sway"
        program.write_text(f'#!/bin/sh\necho "sway $*" >>"{self.calls}"\n: >"{marker}"\nexit 0\n')
        program.chmod(0o755)
        self.fake("start-hyprland")
        self.fake("agreety")
        self.assertEqual(self.run_session(), ["sway", "agreety"])


class HabitsScript(unittest.TestCase):
    """data/custom-widgets/habits.sh, the Daily habits widget's script, run
    on a state folder of its own."""

    SCRIPT = ROOT / "data" / "custom-widgets" / "habits.sh"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.env = dict(os.environ, XDG_STATE_HOME=str(self.tmp))
        self.tsv = self.tmp / "axiom" / "habits.tsv"

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_script(self, *args):
        return subprocess.run(["bash", str(self.SCRIPT), *args], env=self.env,
                              capture_output=True, text=True, timeout=30)

    def show(self):
        result = self.run_script("show")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_starts_empty_with_only_add(self):
        out = self.show()
        self.assertEqual((out["state"], out["text"], out["items"]), ("empty", "0/0", []))
        self.assertEqual(out["actions"], {"add": {}})

    def test_add_check_and_the_screens(self):
        self.assertEqual(self.run_script("do", "add", "  Read\ta \"book\"  ").returncode, 0)
        self.run_script("do", "add", "Walk")
        out = self.show()
        self.assertEqual((out["state"], out["text"]), ("open", "0/2"))
        self.assertEqual([i["text"] for i in out["items"]], ['Read a "book"', "Walk"])
        self.assertEqual(out["actions"], {"add": {}, "check": {}, "remove": {}, "undo": {}})
        self.run_script("do", "check", "1")
        out = self.show()
        self.assertEqual((out["state"], out["text"]), ("open", "1/2"))
        self.assertEqual(out["items"][0]["state"], "done")
        self.assertEqual(out["items"][0]["subtext"], "1 day")
        self.run_script("do", "check", "2")
        self.run_script("do", "check", "2")
        self.assertEqual(self.show()["state"], "done")

    def test_a_streak_counts_days_in_a_row(self):
        self.run_script("do", "add", "Read")
        yesterday = subprocess.run(["date", "-d", "yesterday", "+%F"], capture_output=True, text=True).stdout.strip()
        self.tsv.write_text(f"1\tRead\t{yesterday}\t4\n")
        self.assertEqual(self.show()["items"][0]["subtext"], "4 days")
        self.run_script("do", "check", "1")
        self.assertEqual(self.show()["items"][0]["subtext"], "5 days")
        self.tsv.write_text("1\tRead\t2000-01-01\t9\n")
        self.assertEqual(self.show()["items"][0]["subtext"], "0 days")
        self.run_script("do", "check", "1")
        self.assertEqual(self.show()["items"][0]["subtext"], "1 day")

    def test_undo_and_remove(self):
        self.run_script("do", "add", "Read")
        self.run_script("do", "add", "Walk")
        self.run_script("do", "remove", "1")
        self.assertEqual([i["text"] for i in self.show()["items"]], ["Walk"])
        self.assertEqual(self.run_script("do", "undo").returncode, 0)
        self.assertEqual([i["text"] for i in self.show()["items"]], ["Read", "Walk"])
        self.assertNotIn("undo", self.show()["actions"])
        self.assertEqual(self.run_script("do", "undo").returncode, 2)

    def test_bad_input_exits_2_with_a_line_on_stderr(self):
        self.run_script("do", "add", "Read")
        for args in (("check", "9"), ("check", "x"), ("remove", "9"), ("add", "  "), ("fly", ""), ("add",)):
            result = self.run_script("do", *args)
            self.assertEqual(result.returncode, 2, args)
            self.assertTrue(result.stderr.strip().startswith("habits:"), args)
        self.assertEqual(len(self.show()["items"]), 1)

    def test_overlapping_adds_keep_every_habit(self):
        procs = [subprocess.Popen(["bash", str(self.SCRIPT), "do", "add", f"h{n}"], env=self.env) for n in range(8)]
        for proc in procs:
            self.assertEqual(proc.wait(timeout=30), 0)
        self.assertEqual(sorted(i["id"] for i in self.show()["items"]), [str(n) for n in range(1, 9)])
        self.assertFalse((self.tmp / "axiom" / "habits.tsv.lock").exists())

    def test_remove_is_listed_only_with_habits(self):
        self.assertNotIn("remove", self.show()["actions"])
        self.run_script("do", "add", "Read")
        self.assertIn("remove", self.show()["actions"])

    def test_last_line_without_newline(self):
        self.tsv.parent.mkdir(parents=True)
        self.tsv.write_text("1\tread\t-\t0\n2\tgym\t-\t0")
        self.assertEqual(len(self.show()["items"]), 2)
        self.assertEqual(self.run_script("do", "check", "1").returncode, 0)
        self.assertIn("2\tgym", self.tsv.read_text())
        self.assertEqual(self.run_script("do", "add", "c").returncode, 0)
        text = self.tsv.read_text()
        self.assertTrue(text.endswith("\n"))
        self.assertEqual([line.split("\t")[0] for line in text.splitlines()], ["1", "2", "3"])

    def test_state_dir_a_file_exits_2(self):
        (self.tmp / "axiom").write_text("")
        result = subprocess.run(["bash", str(self.SCRIPT), "do", "add", "a"], env=self.env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertTrue(result.stderr.startswith("habits:"))

    def test_read_only_state_dir_exits_2(self):
        if os.geteuid() == 0:
            self.skipTest("root ignores directory modes")
        state = self.tmp / "axiom"
        state.mkdir()
        state.chmod(0o555)
        self.addCleanup(lambda: state.exists() and state.chmod(0o755))
        result = subprocess.run(["bash", str(self.SCRIPT), "do", "add", "a"], env=self.env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 2)
        self.assertTrue(result.stderr.startswith("habits:"))


class DemoScript(unittest.TestCase):
    """data/custom-widgets/demo.sh, the templates' script, run on a state
    folder of its own."""

    SCRIPT = ROOT / "data" / "custom-widgets" / "demo.sh"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.env = dict(os.environ, XDG_STATE_HOME=str(self.tmp))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_script(self, *args):
        return subprocess.run(["bash", str(self.SCRIPT), *args], env=self.env,
                              capture_output=True, text=True, timeout=30)

    def show(self, template):
        result = self.run_script(template, "show")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.endswith("\n") and not result.stdout.endswith("\n\n"))
        return json.loads(result.stdout)

    def test_toggle_round_trip(self):
        self.assertEqual(self.show("toggle"), {"text": "Focus mode", "state": "off"})
        self.assertEqual(self.run_script("toggle", "on").returncode, 0)
        self.assertEqual(self.show("toggle")["state"], "on")
        self.run_script("toggle", "off")
        self.assertEqual(self.show("toggle")["state"], "off")

    def test_slider_set_truncates_clamps_and_rejects(self):
        self.assertEqual(self.show("slider")["value"], 50)
        for given, want in (("37.9", 37), ("150", 100), ("-5", 0), ("007", 7), (".5", 0), ("99999999999999", 100)):
            self.assertEqual(self.run_script("slider", "set", given).returncode, 0, given)
            self.assertEqual(self.show("slider")["value"], want, given)
        for bad in ("abc", "", "1e3", "5%"):
            result = self.run_script("slider", "set", bad)
            self.assertEqual(result.returncode, 2, bad)
            self.assertTrue(result.stderr.startswith("demo: "), bad)
        self.assertEqual(self.show("slider")["value"], 100, "a rejected value changes nothing")

    def test_list_prints_the_mounts(self):
        out = self.show("list")
        self.assertIsInstance(out["items"], list)
        self.assertEqual(out["text"].split()[0], str(len(out["items"])))
        for item in out["items"]:
            self.assertTrue(item["id"].startswith("/"))
            self.assertIn(item["state"], ("ok", "full"))
            self.assertEqual(item["unit"], "%", "the used share reads as a percentage")
            self.assertEqual(item["state"] == "full", item["value"] >= 90)

    def test_media_walks_the_tracks(self):
        first = self.show("media")
        self.assertEqual((first["state"], first["icon"]), ("playing", "pause"))
        self.run_script("media", "toggle")
        paused = self.show("media")
        self.assertEqual((paused["state"], paused["icon"], paused["text"]), ("paused", "play_arrow", first["text"]))
        self.run_script("media", "toggle")
        self.run_script("media", "next")
        self.assertNotEqual(self.show("media")["text"], first["text"])
        self.run_script("media", "next")
        stopped = self.show("media")
        self.assertEqual(stopped["state"], "stopped", "next past the last track stops")
        self.run_script("media", "toggle")
        self.assertEqual(self.show("media")["state"], "playing", "toggle from stopped plays")
        for _ in range(3):
            self.run_script("media", "next")
        self.assertEqual(self.show("media")["state"], "stopped")
        self.run_script("media", "prev")
        self.assertEqual(self.show("media")["state"], "playing", "prev from stopped plays the last track")

    def test_status_break_and_fix(self):
        ok = self.show("status")
        self.assertEqual((ok["state"], ok["text"]), ("ok", "All good"))
        self.run_script("status", "break")
        result = self.run_script("status", "show")
        self.assertEqual(result.returncode, 0, "a failing demo still exits 0")
        self.assertTrue(json.loads(result.stdout)["error"])
        self.run_script("status", "fix")
        self.assertEqual(self.show("status")["state"], "ok")

    def test_bad_input_exits_2_with_demo_on_stderr(self):
        for args in (("nope", "show"), ("toggle", "nope"), ("toggle",), ()):
            result = self.run_script(*args)
            self.assertEqual(result.returncode, 2, args)
            self.assertTrue(result.stderr.startswith("demo: "), args)
            self.assertEqual(result.stdout, "")

    def test_every_template_command_is_a_verb_the_script_takes(self):
        source = (ROOT / "qml" / "components" / "methods" / "CustomWidgetData.qml").read_text()
        calls = re.findall(r'_demo\("(\w+)", "(\w+)"\)(?: \+ " \{value\}")?', source)
        self.assertGreaterEqual(len(calls), 12)
        for template, verb in calls:
            args = [template, verb] + (["42"] if verb == "set" else [])
            result = self.run_script(*args)
            self.assertEqual(result.returncode, 0, "%s %s: %s" % (template, verb, result.stderr))


class NewNames(unittest.TestCase):
    """scripts/dev/new_names.py lists the names a branch adds, in a scratch git repo."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name)
        write(self.repo, "qml/A.qml", "Item {\n  property int oldName: 1\n  function shared() {}\n"
                                      "  Text { text: I18n.tr(\"Shrunk to {0}% on {1}\") }\n}\n")
        write(self.repo, "qml/config/schema/s.yaml", "A:\n  type: object\n")
        write(self.repo, "docs/dev/generated/g.py", "def keepme():\n")
        git(self.repo, self.tmp.name, "init", "-q", "-b", "main")
        git(self.repo, self.tmp.name, "add", "-A")
        git(self.repo, self.tmp.name, "commit", "-q", "-m", "base")

    def run_names(self):
        out = subprocess.run([sys.executable, str(SCRIPTS / "dev" / "new_names.py"), "--json"],
                             cwd=self.repo, capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def find(self, rows, kind, name):
        hits = [r for r in rows if r["kind"] == kind and r["name"] == name]
        self.assertEqual(len(hits), 1, (kind, name, rows))
        return hits[0]

    def test_rows(self):
        write(self.repo, "qml/A.qml", "Item {\n  property int newName: 1\n  function shared() {}\n"
                                      "  Text { text: I18n.tr(\"Shrunk to {0}% on {1}\") }\n}\n")
        write(self.repo, "qml/B.qml", "Item {\n  function shared() {}\n  Text { text: I18n.tr(\"shrunk to  {0} % on {1}\") }\n}\n")
        write(self.repo, "qml/config/schema/s.yaml", "A:\n  type: object\n  newKey:\n    type: string\n    default: x\n    x-scope: machine\n")
        write(self.repo, "docs/dev/generated/g.py", "def keepme():\n\ndef skipped():\n")
        rows = self.run_names()
        self.assertEqual(self.find(rows, "function", "shared")["also"], ["qml/A.qml:3"])
        self.assertTrue(self.find(rows, "property", "newName")["moved"] is False)
        self.assertEqual(self.find(rows, "component", "B")["file"], "qml/B.qml")
        self.assertTrue(any(r["also"] for r in rows if r["kind"] == "string" and r["file"] == "qml/B.qml"))
        self.assertEqual([r["name"] for r in rows if r["file"].endswith(".yaml")], ["newKey"])
        self.assertFalse([r for r in rows if r["file"].startswith("docs/dev/generated/")])

    def test_rename_is_moved(self):
        write(self.repo, "qml/A.qml", "Item {\n  property string oldName: \"\"\n}\n")
        self.assertTrue(self.find(self.run_names(), "property", "oldName")["moved"])

    def test_text_summary(self):
        write(self.repo, "qml/B.qml", "Item {}\n")
        out = subprocess.run([sys.executable, str(SCRIPTS / "dev" / "new_names.py")],
                             cwd=self.repo, capture_output=True, text=True).stdout
        self.assertIn("  component B  qml/B.qml:1", out)
        self.assertTrue(out.rstrip().endswith("1 names, 0 also defined elsewhere"))

    def test_js_under_tests(self):
        write(self.repo, "tests/x/Rows.js", "var rows = [];\nfunction builder() {\n  var inner = 1;\n  return inner;\n}\n")
        rows = self.run_names()
        self.find(rows, "var", "rows")
        self.find(rows, "function", "builder")
        self.assertFalse([r for r in rows if r["name"] == "inner"])

    def test_js_outside_tests_unscanned(self):
        write(self.repo, "qml/x/A.js", "var a = 1;\nfunction f() {}\n")
        write(self.repo, "data/x.js", "var a = 1;\nfunction f() {}\n")
        self.assertFalse([r for r in self.run_names() if r["file"].endswith(".js")])


if __name__ == "__main__":
    unittest.main()
