#!/usr/bin/env python3
"""Smoke tests for the scripts in scripts/, each run in a scratch $HOME.

  - every shipped theme is complete (config/themes/theme.schema.json's
    required keys, hex colors, semantic names that resolve, pairs that exist)
  - the Neovim module Apply copies compiles and maps the shipped themes
  - check_sizes.py finds sizes written as numbers, skipping hairlines and
    lines marked `// fixed px:`
  - pick_path.py falls back to zenity/kdialog without a portal, asking for
    a folder or a filtered file, and exits 1 when cancelled, 2 with no picker

  python3 tests/scripts/test_scripts.py [-v] [TestCase[.test_name]]
"""
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import tomllib
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


class GreeterInstall(unittest.TestCase):
    """greeter_install.sh on a scratch root (AXIOM_GREETER_ROOT), as the
    current user standing in for both the user and greetd's user."""
    SESSION = "/usr/share/axiom-greeter/scripts/greeter/greeter-session.sh"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.env = scratch_env(self.tmp)
        self.env.update({"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
                         "GIT_COMMITTER_EMAIL": "t@t"})
        self.user = subprocess.run(["id", "-un"], capture_output=True, text=True, check=True).stdout.strip()
        self.root = self.tmp / "root"
        self.env["AXIOM_GREETER_ROOT"] = str(self.root)
        self.config = self.root / "etc/greetd/config.toml"
        self.config.parent.mkdir(parents=True)
        self.original = ('[terminal]\nvt = 1\n\n[default_session]\n# the greeter\n'
                         f'command = "agreety --cmd /bin/sh"\nuser = "{self.user}"\n')
        self.config.write_text(self.original)
        for name in ["greetd", "agreety", "sway"]:
            program = self.root / "usr/bin" / name
            program.parent.mkdir(parents=True, exist_ok=True)
            program.write_text("#!/bin/sh\n")
            program.chmod(0o755)
        link = self.root / "etc/systemd/system/display-manager.service"
        link.parent.mkdir(parents=True)
        link.symlink_to("/usr/lib/systemd/system/sddm.service")
        # go, as the build of a git copy's binary runs it: `build -o OUT`
        # writes "built" (fails while go-fails exists)
        tools = self.tmp / "tools"
        tools.mkdir()
        go = tools / "go"
        go.write_text(f'#!/bin/sh\n[ -e "{self.tmp}/go-fails" ] && exit 1\n[ "$1" = build ] || exit 0\n'
                      'while [ $# -gt 0 ]; do [ "$1" = -o ] && { echo built >"$2"; exit 0; }; shift; done\nexit 1\n')
        go.chmod(0o755)
        self.env["PATH"] = f"{tools}:{self.env['PATH']}"
        # The binary the shell runs, which a local copy takes
        self.binary = self.tmp / "axiom-bin"
        self.binary.write_bytes(b"\x7fELF local binary")
        self.binary.chmod(0o755)
        self.repo = self.tmp / "repo"
        for name in ["greeter.qml", "shell.qml", "scripts/greeter/greeter-session.sh", "tests/tst_x.qml",
                     "docs/notes.md", "backend/go.mod"]:
            (self.repo / name).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / name).write_text(name)
        policy = self.repo / "scripts/greeter/org.axiom.greeter.policy"
        policy.write_text((SCRIPTS / "greeter" / "org.axiom.greeter.policy").read_text())
        helper = self.repo / "scripts/greeter/greeter_install.sh"
        shutil.copy(SCRIPTS / "greeter" / "greeter_install.sh", helper)
        helper.chmod(0o755)
        self.policy = self.root / "usr/share/polkit-1/actions/org.axiom.greeter.policy"
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.repo)], env=self.env, check=True)
        self.git("add", ".")
        self.git("commit", "-q", "-m", "x")
        self.git("tag", "-a", "v1.0", "-m", "v1.0")
        # The clone's upstream, where git installs fetch from
        self.upstream = self.tmp / "upstream.git"
        subprocess.run(["git", "clone", "-q", "--bare", str(self.repo), str(self.upstream)], env=self.env, check=True)
        self.git("remote", "add", "origin", str(self.upstream))

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env, check=True,
                              capture_output=True, text=True).stdout.strip()

    def publish(self, name, text, tag=None):
        """A commit on the upstream's main (and a tag on it)."""
        (self.repo / name).write_text(text)
        self.git("commit", "-qam", f"{name}: {text}")
        if tag:
            self.git("tag", "-a", tag, "-m", tag)
        self.git("push", "-q", "origin", "main", "--tags")

    def copied(self, name="greeter.qml"):
        return (self.root / "usr/share/axiom-greeter" / name).read_text()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_script(self, action, ok=True, source="git", channel="tags", staged="", binary=None):
        args = [str(SCRIPTS / "greeter" / "greeter_install.sh"), action, str(self.repo)]
        if action in ("install", "update"):
            args += [self.user, staged, source, channel, str(self.binary) if binary is None else binary]
        elif action == "uninstall":
            args.append(self.user)
        else:
            args += [source, channel]
        result = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return json.loads(result.stdout) if action != "hash" else result.stdout.strip()

    def command(self):
        return tomllib.loads(self.config.read_text())["default_session"]["command"]

    def test_check_before_install(self):
        report = self.run_script("check")
        self.assertEqual((report["greetd"], report["displayManager"], report["installed"], report["configured"]),
                         (True, "sddm", False, False))
        self.assertEqual(report["greeterUser"], self.user)
        self.assertEqual(report["url"], str(self.upstream))
        self.assertEqual(report["currentHash"], self.git("rev-parse", "v1.0^{commit}"))
        self.assertEqual(self.run_script("hash"), report["currentHash"])
        local = self.run_script("hash", source="local")
        self.assertRegex(local, "^[0-9a-f]{64}$")
        # A content hash: it doesn't move with the clock
        time.sleep(1.1)
        self.assertEqual(self.run_script("hash", source="local"), local)

    def test_compositor_the_login_screen_runs_in(self):
        """sway, else Hyprland (start-hyprland), as greeter-session.sh picks;
        Install refuses with neither, which would only ever show agreety."""
        self.assertEqual(self.run_script("check")["compositor"], "sway")
        (self.root / "usr/bin/sway").unlink()
        hyprland = self.root / "usr/local/bin/start-hyprland"
        hyprland.parent.mkdir(parents=True)
        hyprland.write_text("#!/bin/sh\n")
        hyprland.chmod(0o755)
        self.assertEqual(self.run_script("check")["compositor"], "hyprland")
        hyprland.unlink()
        self.assertEqual(self.run_script("check")["compositor"], "")
        self.assertIn("neither sway nor Hyprland", self.run_script("install", ok=False)["error"])
        self.assertEqual(self.config.read_text(), self.original)

    def test_check_as_root(self):
        """As root (pkexec, CI) check runs nothing as another user: its third
        argument is the source, never a user name."""
        args = ["unshare", "-r", str(SCRIPTS / "greeter" / "greeter_install.sh"), "check", str(self.repo), "local"]
        if os.geteuid() == 0:
            args = args[2:]
        elif not shutil.which("unshare") or subprocess.run(["unshare", "-r", "true"], capture_output=True).returncode:
            self.skipTest("no user namespaces to be root in")
        result = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=60)
        report = json.loads(result.stdout)
        self.assertEqual(report["url"], "")
        self.assertEqual(report["currentHash"], self.run_script("hash", source="local"))
        args[args.index("local")] = "git"
        self.assertEqual(json.loads(subprocess.run(args, env=self.env, capture_output=True, text=True,
                                                   timeout=60).stdout)["url"], str(self.upstream))

    def test_https_for_ssh_remotes(self):
        self.git("remote", "set-url", "origin", "git@github.com:axiom-shell/axiom.git")
        self.assertEqual(self.run_script("check")["url"], "https://github.com/axiom-shell/axiom.git")
        self.git("remote", "set-url", "origin", "ssh://git@example.org/me/axiom.git")
        self.assertEqual(self.run_script("check")["url"], "https://example.org/me/axiom.git")

    def package(self, version="1.2.0-1"):
        """A packaged axiom at /usr/share/axiom, as its PKGBUILD lays it out."""
        package = self.root / "usr/share/axiom"
        for name in ["greeter.qml", "shell.qml", "scripts/greeter/greeter-session.sh", "scripts/greeter/hyprland.lua"]:
            (package / name).parent.mkdir(parents=True, exist_ok=True)
            (package / name).write_text(name)
        for name in ["greeter_install.sh", "org.axiom.greeter.policy"]:
            shutil.copy(self.repo / "scripts/greeter" / name, package / "scripts/greeter" / name)
        (package / ".packaged").write_text(version + "\n")
        return package

    def test_package_source(self):
        """A packaged axiom: the greeter runs the package's code, so the
        install folder gets only scripts/greeter/ and the snapshot, and the
        package's version is its hash; the clone isn't read."""
        report = self.run_script("install", ok=False, source="package")
        self.assertIn(".packaged is missing", report["error"])
        package = self.package()
        bundle = self.root / "var/lib/axiom-greeter/config"
        bundle.mkdir(parents=True)
        (bundle / "greeter.json").write_text("{}")
        self.assertTrue(self.run_script("install", source="package")["ok"])
        copy = self.root / "usr/share/axiom-greeter"
        self.assertEqual(sorted(p.name for p in copy.iterdir()),
                         [".greeter-hash", ".greeter-source", "fallback", "scripts"])
        self.assertTrue((copy / "scripts/greeter/greeter_install.sh").is_file())
        self.assertEqual(self.copied(".greeter-source"), "package /usr/share/axiom\n")
        self.assertEqual(self.copied("fallback/greeter.json"), "{}")
        self.assertTrue(self.policy.is_file())
        self.assertEqual(self.command(), self.SESSION)
        report = self.run_script("check", source="package")
        self.assertEqual((report["installedSource"], report["installedHash"], report["currentHash"], report["url"]),
                         ("package", "1.2.0-1", "1.2.0-1", ""))
        # The package manager updated it: behind until Update
        (package / ".packaged").write_text("1.3.0-1\n")
        self.assertEqual(self.run_script("check", source="package")["currentHash"], "1.3.0-1")
        self.assertTrue(self.run_script("update", source="package")["ok"])
        self.assertEqual(self.copied(".greeter-hash"), "1.3.0-1\n")

    def test_install_copies_points_greetd_and_backs_up(self):
        bundle = self.root / "var/lib/axiom-greeter/config"
        bundle.mkdir(parents=True)
        (bundle / "greeter.json").write_text("{}")
        report = self.run_script("install")
        self.assertTrue(report["ok"], report)
        copy = self.root / "usr/share/axiom-greeter"
        self.assertTrue((copy / "greeter.qml").is_file())
        self.assertFalse((copy / "tests").exists())
        self.assertFalse((copy / "docs").exists())
        self.assertEqual((copy / "fallback/greeter.json").read_text(), "{}")
        self.assertEqual(self.command(), self.SESSION)
        parsed = tomllib.loads(self.config.read_text())
        self.assertEqual(parsed["default_session"]["user"], self.user)
        self.assertEqual(parsed["terminal"]["vt"], 1)
        self.assertEqual((self.config.parent / "config.toml.axiom-original").read_text(), self.original)
        self.assertEqual(Path(report["backup"]).read_text(), self.original)
        self.assertTrue((self.root / "var/lib/axiom-greeter/state").is_dir())
        report = self.run_script("check")
        self.assertEqual((report["installed"], report["configured"], report["bundleWritable"]), (True, True, True))
        self.assertEqual(report["installedHash"], report["currentHash"])

    def test_install_snapshots_a_staged_bundle(self):
        staged = self.tmp / "staged"
        staged.mkdir()
        (staged / "greeter.json").write_text('{"staged": true}')
        (staged / "theme.json").symlink_to("/etc/hostname")
        self.run_script("install", staged=str(staged))
        fallback = self.root / "usr/share/axiom-greeter/fallback"
        self.assertEqual((fallback / "greeter.json").read_text(), '{"staged": true}')
        self.assertFalse((fallback / "theme.json").exists())

    def test_update_again_changes_nothing_in_greetd(self):
        self.run_script("install")
        report = self.run_script("update")
        self.assertTrue(report["ok"], report)
        self.assertEqual(report["backup"], "")
        self.assertEqual(len(list(self.config.parent.glob("config.toml.axiom-bak-*"))), 1)

    def test_git_tags_takes_the_newest_release_only(self):
        self.publish("greeter.qml", "unreleased")
        self.run_script("install")
        self.assertEqual(self.copied(), "greeter.qml")
        report = self.run_script("check")
        self.assertEqual(report["installedSource"], "git:tags")
        self.assertEqual(report["installedHash"], report["currentHash"])
        self.publish("greeter.qml", "v1.10", tag="v1.10")
        self.publish("shell.qml", "v1.9", tag="v1.9")
        report = self.run_script("check")
        self.assertEqual(report["currentHash"], self.git("rev-parse", "v1.10^{commit}"))
        self.assertNotEqual(report["installedHash"], report["currentHash"])
        self.run_script("update")
        self.assertEqual(self.copied(), "v1.10")
        report = self.run_script("check")
        self.assertEqual(report["installedHash"], report["currentHash"])

    def test_git_main_follows_the_branch(self):
        self.publish("greeter.qml", "on main")
        self.run_script("install", channel="main")
        self.assertEqual(self.copied(), "on main")
        self.assertEqual(self.run_script("check", channel="main")["installedSource"], "git:main")

    def test_git_ignores_the_clone(self):
        """Uncommitted edits, local commits and a changed remote don't reach a git copy."""
        self.run_script("install")
        (self.repo / "greeter.qml").write_text("edited")
        self.git("commit", "-qam", "local only")
        other = self.tmp / "other.git"
        subprocess.run(["git", "clone", "-q", "--bare", str(self.repo), str(other)], env=self.env, check=True)
        self.git("tag", "-a", "v9.0", "-m", "v9.0")
        self.git("push", "-q", str(other), "v9.0")
        self.git("remote", "set-url", "origin", str(other))
        report = self.run_script("check")
        self.assertEqual(report["url"], str(self.upstream))
        self.assertEqual(report["installedHash"], report["currentHash"])
        self.run_script("update")
        self.assertEqual(self.copied(), "greeter.qml")

    def test_local_copies_the_working_tree(self):
        self.git("checkout", "-q", "-b", "feature")
        (self.repo / "greeter.qml").write_text("uncommitted")
        self.run_script("install", source="local")
        self.assertEqual(self.copied(), "uncommitted")
        self.assertFalse((self.root / "usr/share/axiom-greeter/docs").exists())
        report = self.run_script("check", source="local")
        self.assertEqual(report["installedSource"], "local")
        self.assertEqual(report["installedHash"], report["currentHash"])
        (self.repo / "greeter.qml").write_text("edited again")
        report = self.run_script("check", source="local")
        self.assertNotEqual(report["installedHash"], report["currentHash"])
        # A docs edit isn't code
        self.run_script("update", source="local")
        (self.repo / "docs/notes.md").write_text("more")
        report = self.run_script("check", source="local")
        self.assertEqual(report["installedHash"], report["currentHash"])

    def installed_binary(self):
        return (self.root / "usr/share/axiom-greeter/bin/axiom").read_bytes()

    def test_local_copies_the_shells_binary(self):
        self.run_script("install", source="local")
        self.assertEqual(self.installed_binary(), b"\x7fELF local binary")
        self.assertTrue(self.run_script("check")["binaries"])
        self.assertIn("no axiom binary given", self.run_script("update", ok=False, source="local", binary="")["error"])
        script = self.tmp / "not-a-program"
        script.write_text("#!/bin/sh\n")
        script.chmod(0o755)
        self.assertIn("isn't a program", self.run_script("update", ok=False, source="local", binary=str(script))["error"])
        # A failed update leaves the copy as it was
        self.assertEqual(self.installed_binary(), b"\x7fELF local binary")

    def test_git_builds_the_binary_without_a_release(self):
        self.run_script("install")
        self.assertEqual(self.installed_binary(), b"built\n")

    def release(self, tag, data, sums=None):
        """A release of `tag` with axiom-linux-<arch> (`data`) and its SHA256SUMS."""
        arch = {"x86_64": "amd64", "aarch64": "arm64"}.get(os.uname().machine, os.uname().machine)
        folder = self.tmp / "releases" / tag
        folder.mkdir(parents=True)
        (folder / f"axiom-linux-{arch}").write_bytes(data)
        digest = sums or hashlib.sha256(data).hexdigest()
        (folder / "SHA256SUMS").write_text(f"{digest}  axiom-linux-{arch}\n")
        self.env["AXIOM_GREETER_RELEASES"] = (self.tmp / "releases").as_uri()

    def test_git_takes_a_releases_binary(self):
        self.release("v1.0", b"\x7fELF released")
        (self.tmp / "go-fails").touch()
        self.run_script("install")
        self.assertEqual(self.installed_binary(), b"\x7fELF released")

    def test_git_refuses_a_binary_its_sums_dont_match(self):
        self.release("v1.0", b"\x7fELF released", sums="0" * 64)
        self.assertIn("doesn't match its SHA256SUMS", self.run_script("install", ok=False)["error"])
        self.assertFalse((self.root / "usr/share/axiom-greeter").exists())

    def test_git_without_release_or_go(self):
        (self.tmp / "go-fails").touch()
        self.assertIn("no axiom binary", self.run_script("install", ok=False)["error"])
        self.assertFalse((self.root / "usr/share/axiom-greeter").exists())

    def test_switching_source(self):
        self.run_script("install", source="local")
        self.assertEqual(self.run_script("check")["installedSource"], "local")
        self.run_script("update")
        self.assertEqual(self.run_script("check")["installedSource"], "git:tags")

    def test_refuses_a_release_without_a_login_screen(self):
        self.git("rm", "-q", "greeter.qml")
        self.git("commit", "-qm", "old")
        self.git("tag", "-a", "v2.0", "-m", "v2.0")
        self.git("push", "-q", "origin", "main", "--tags")
        self.assertIn("v2.0 has no login screen", self.run_script("install", ok=False)["error"])
        self.assertIn("has no login screen", self.run_script("install", ok=False, source="local")["error"])
        self.assertFalse((self.root / "usr/share/axiom-greeter").exists())

    def test_git_unreachable(self):
        self.git("remote", "set-url", "origin", str(self.tmp / "missing.git"))
        self.assertEqual(self.run_script("check")["currentHash"], "")
        self.assertIn("offline", self.run_script("install", ok=False)["error"])

    def test_policy_names_the_installed_helper(self):
        self.assertFalse(self.run_script("check")["helper"])
        self.run_script("install")
        self.assertTrue(self.run_script("check")["helper"])
        self.assertIn("<annotate key=\"org.freedesktop.policykit.exec.path\">/usr/share/axiom-greeter/scripts/greeter/greeter_install.sh<",
                      self.policy.read_text())
        self.run_script("uninstall")
        self.assertFalse(self.policy.exists())

    def test_section_without_a_command_gets_one(self):
        self.config.write_text(f'[default_session]\nuser = "{self.user}"\n\n[terminal]\nvt = 1\n')
        self.assertTrue(self.run_script("install")["ok"])
        parsed = tomllib.loads(self.config.read_text())
        self.assertEqual(parsed["default_session"], {"command": self.SESSION, "user": self.user})
        self.assertEqual(parsed["terminal"]["vt"], 1)

    def test_uninstall_restores_the_original(self):
        self.run_script("install")
        report = self.run_script("uninstall")
        self.assertTrue(report["ok"], report)
        self.assertEqual(self.config.read_text(), self.original)
        self.assertFalse((self.root / "usr/share/axiom-greeter").exists())
        self.assertFalse((self.root / "var/lib/axiom-greeter").exists())
        self.assertFalse((self.config.parent / "config.toml.axiom-original").exists())

    def test_reinstall_after_uninstall_restores_the_config_of_then(self):
        self.run_script("install")
        self.run_script("uninstall")
        changed = self.original.replace("vt = 1", "vt = 2")
        self.config.write_text(changed)
        self.run_script("install")
        self.run_script("uninstall")
        self.assertEqual(self.config.read_text(), changed)

    def test_refusals(self):
        (self.root / "usr/bin/agreety").unlink()
        self.assertFalse(self.run_script("check")["agreety"])
        self.assertIn("agreety", self.run_script("install", ok=False)["error"])
        self.config.unlink()
        self.assertIn("greetd isn't installed", self.run_script("install", ok=False)["error"])
        self.assertIn("usage", self.run_script("bogus", ok=False)["error"])

    def test_refuses_unknown_source_and_channel(self):
        self.assertIn("unknown source", self.run_script("install", ok=False, source="svn")["error"])
        self.assertIn("unknown channel", self.run_script("install", ok=False, channel="beta")["error"])


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


class PickPath(unittest.TestCase):
    """pick_path.py with no portal (a dead session bus), so it falls back
    to a stubbed zenity or kdialog that logs its arguments."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.stubs = self.tmp / "stubs"
        self.stubs.mkdir()
        self.start = self.tmp / "start"
        self.start.mkdir()

    def stub(self, name, code=0):
        stub = self.stubs / name
        stub.write_text(f'#!/bin/sh\nprintf "%s\\n" "$@" > "{self.tmp}/args"\necho /picked/path\nexit {code}\n')
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)

    def pick(self, *args):
        env = dict(os.environ, PATH=str(self.stubs), HOME=str(self.tmp),
                   DBUS_SESSION_BUS_ADDRESS=f"unix:path={self.tmp}/no-bus")
        done = subprocess.run([sys.executable, str(SCRIPTS / "pick_path.py"), *args],
                              env=env, capture_output=True, text=True, timeout=30)
        logged = (self.tmp / "args").read_text().splitlines() if (self.tmp / "args").exists() else []
        return done.returncode, done.stdout.strip(), logged

    def test_zenity_folder(self):
        self.stub("zenity")
        code, out, logged = self.pick("--folder", "Pick", str(self.start))
        self.assertEqual((code, out), (0, "/picked/path"))
        self.assertIn("--directory", logged)
        self.assertIn(f"{self.start}/", logged)

    def test_zenity_file_filter(self):
        self.stub("zenity")
        _, _, logged = self.pick("--filter", "JSON:*.json", "Pick", str(self.start))
        self.assertNotIn("--directory", logged)
        self.assertIn("JSON | *.json", logged)

    def test_kdialog_folder(self):
        self.stub("kdialog")
        code, out, logged = self.pick("--folder", "Pick", str(self.start))
        self.assertEqual((code, out), (0, "/picked/path"))
        self.assertEqual(logged[-2:], ["--getexistingdirectory", str(self.start)])

    def test_missing_start_opens_home(self):
        self.stub("kdialog")
        _, _, logged = self.pick("--folder", "Pick", str(self.tmp / "gone"))
        self.assertEqual(logged[-1], str(self.tmp))

    def test_cancelled_and_no_picker(self):
        self.stub("zenity", code=1)
        self.assertEqual(self.pick("--folder", "Pick")[0], 1)
        (self.stubs / "zenity").unlink()
        self.assertEqual(self.pick("--folder", "Pick")[0], 2)


if __name__ == "__main__":
    unittest.main()
