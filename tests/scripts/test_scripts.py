#!/usr/bin/env python3
"""Smoke tests for the scripts in scripts/, each run in a scratch $HOME.

  - every shipped theme is complete (config/themes/theme.schema.json's
    required keys, hex colors, semantic names that resolve, pairs that exist)
  - the Neovim module Apply copies compiles and maps the shipped themes
  - check_sizes.py finds sizes written as numbers, skipping hairlines and
    lines marked `// fixed px:`
  - only PAM's success unlocks the built-in lock screen

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

ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPTS = ROOT / "scripts"
THEMES = ROOT / "config" / "themes"
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
        defaults = json.loads((ROOT / "config" / "json" / "theme-defaults.json").read_text())
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


class NvimModule(unittest.TestCase):
    """The axiom_theme Lua module Apply copies into a Neovim config"""
    def test_nvim_module_compiles(self):
        luac = shutil.which("luac")
        if not luac:
            self.skipTest("no luac")
        module = SCRIPTS / "templates" / "nvim" / "axiom_theme.lua"
        result = subprocess.run([luac, "-p", str(module)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_nvim_module_maps_shipped_themes(self):
        text = (SCRIPTS / "templates" / "nvim" / "axiom_theme.lua").read_text()
        mapped = set(re.findall(r'^\s*\["([\w-]+)"\] = scheme\(', text, re.M))
        shipped = {p.stem for p in THEMES.glob("*.json")} - {"theme.schema"}
        self.assertEqual(mapped - shipped, set(), "map entries without a theme")
        self.assertEqual(shipped - mapped - {"submarine-sonar", "submarine-sonar-light", "nord-light", "alucard"},
                         set(), "themes without a map entry")


class KnownIssues(unittest.TestCase):
    """scripts/dev/known_issues.py marks log lines an issues.md entry covers."""

    def test_marks(self):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp)
        issues = tmp / "issues.md"
        issues.write_text("""# Known issues

```
### <Short title>
- **Where:** `path/File.qml`
- **What:** quote its category too, `quickshell.I3.ipc`
```

### A file's warning
- **Where:** `services/Thing.qml`
- **What:** logs `Cannot read property` at its binding, and warns `the connection closed`
- **Size:** trivial
- **Found:** 2026-10-16, while testing

### Qt's own warning
- **Where:** `services/compositor/SwayManager.qml`
- **What:** every reload logs `I3 event socket disconnected` (category `quickshell.I3.ipc`)
- **Size:** trivial
- **Found:** 2026-10-16, while testing
""")
        log = "\n".join([
            "  WARN qml: @services/Thing.qml[3:5]: TypeError: Cannot read property 'x' of null",
            "  WARN qml: @services/Other.qml[3:5]: TypeError: Cannot read property 'x' of null",
            "  WARN quickshell.I3.ipc: I3 event socket disconnected.",
            "  WARN quickshell.other: I3 event socket disconnected.",
            "  WARN quickshell.I3.ipc: a new failure",
            "  WARN qml: [Thing] Failed to fetch: the connection closed",
            "  WARN qml: [Other] Failed to fetch: the connection closed",
        ]) + "\n"
        done = subprocess.run([sys.executable, str(SCRIPTS / "dev" / "known_issues.py")], input=log, capture_output=True,
                              text=True, timeout=30, env={**os.environ, "AXIOM_ISSUES": str(issues)})
        lines = done.stdout.splitlines()
        self.assertTrue(lines[0].endswith("(known: issues.md › A file's warning)"))
        self.assertNotIn("known", lines[1])
        self.assertTrue(lines[2].endswith("(known: issues.md › Qt's own warning)"))
        self.assertNotIn("known", lines[3])
        self.assertNotIn("known", lines[4], "the category alone isn't the warning")
        self.assertTrue(lines[5].endswith("(known: issues.md › A file's warning)"), "a [Tag] names its file")
        self.assertNotIn("known", lines[6])


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
            '  BackendManager.notify("x.y");',
            "  BackendManager.call(method, params);",
            '  root._send(JsonRpc.request(id, "daemon.hello", {pid: 1}));',
            "}",
        ])
        self.assertEqual([(line, method, src.split("\n")[0]) for line, method, src in qml_call_sites(qml)],
                         [(2, "tz.offsets", "{"), (6, "x.y", ""), (7, None, "params"), (8, "daemon.hello", "{pid: 1}")])

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
            "  font.pixelSize: 100 // fixed px: a measuring font",
            "  Layout.preferredHeight: 24",
            "  opacity: 50",
            "  textSize: Appearance.fontSize - 2",
            "  iconSize: Appearance.fontSize * 2",
            "  pixelSize: Appearance.fontSizeBy(-2)",
            "}",
        ])
        self.assertEqual([(n, name) for n, name, _ in find_literals(qml)],
                         [(2, "implicitWidth"), (5, "listMargin"), (9, "Layout.preferredHeight"),
                          (11, "fontSize")])

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
            "  width: (screen?.width ?? 2000) * 0.3 // fixed px: a stand-in",
            "}",
        ])
        self.assertEqual([(n, value) for n, _, value in find_literals(qml)],
                         [(2, "4"), (3, "48"), (4, "8"), (5, "6")])


class CheckDocs(unittest.TestCase):
    """scripts/check_docs.py flags a retired name; one that is also a schema
    definition only with a member that isn't a setting."""

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
    shell/Lockscreen.qml's onAuthenticationSucceeded (or its onSecureChanged
    once the compositor has ended the lock), a session lock not bound to
    its state, authenticationSucceeded emitted for anything but
    PamResult.Success, or the lockscreen IPC target taking more than lock."""
    problems = []
    for path, text in files.items():
        for m in re.finditer(r"\blocked\s*=\s*false", text):
            fn, start = handler_at(text, m.start())
            allowed = fn == "onAuthenticationSucceeded" or (fn == "onSecureChanged" and "!sessionLock.locked" in text[start : m.start()])
            if path != "shell/Lockscreen.qml" or not allowed:
                problems.append(f"{path}: unlocks in {fn}")
        for m in re.finditer(r"\bauthenticationSucceeded\(\)", text):
            case = re.findall(r"case\s+([\w.]+):", text[: m.start()])
            if path != "services/session/AuthManager.qml" or not case or case[-1] != "PamResult.Success":
                problems.append(f"{path}: authenticationSucceeded after {case[-1] if case else 'no case'}")
        for m in re.finditer(r"IpcTarget\s*\{", text):
            block = text[m.end() : block_end(text, m.end() - 1)]
            if re.search(r'target:\s*"lockscreen"', block):
                functions = re.findall(r"function\s+(\w+)", block)
                if functions != ["lock"]:
                    problems.append(f"{path}: the lockscreen IPC target takes {functions}")
    lock = files.get("shell/Lockscreen.qml", "")
    m = re.search(r"WlSessionLock\s*\{", lock)
    if not m or not re.search(r"^\s*locked:\s*lockState\.locked\s*$", lock[m.end() : block_end(lock, m.end() - 1)], re.M):
        problems.append("shell/Lockscreen.qml: the session lock isn't bound to lockState.locked alone")
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
        lock, auth, ipc = "shell/Lockscreen.qml", "services/session/AuthManager.qml", "services/session/LockManager.qml"
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
            # Any other file unlocking, or the lock bound to something else
            ("components/Unlock.qml", "", "Item { function go() { sessionLock.locked = false; } }"),
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
        (self.copy / "scripts/greeter").mkdir(parents=True)
        self.shim = self.copy / "scripts/greeter/greeter_install.sh"
        shutil.copy(SCRIPTS / "greeter" / "greeter_install.sh", self.shim)
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
        subprocess.run(["/bin/sh", str(SCRIPTS / "greeter/greeter-session.sh")], env=env,
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
        subprocess.run(["/bin/sh", str(SCRIPTS / "greeter/greeter-session.sh"), "shell"], env=env,
                       capture_output=True, text=True, timeout=10)
        calls = self.calls.read_text().splitlines()
        tree = str(SCRIPTS.parent)
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


if __name__ == "__main__":
    unittest.main()
