#!/usr/bin/env python3
"""Smoke tests for the scripts in scripts/, each run in a scratch $HOME.

  - every shipped theme is complete (config/themes/theme.schema.json's
    required keys, hex colors, semantic names that resolve, pairs that exist)
  - every theme_*.sh integration renders every shipped theme (and any
    generated ones) into a scratch dir with no warnings, no unfilled
    ${VAR}s and only well-formed colors, and each output parses as its
    format (TOML, JSON, plist, INI; YAML and GTK CSS when PyYAML / PyGObject
    are installed). The apps they need (and pkill, which they signal
    running apps with) are stubbed
  - integration_hookup.py (Settings' Apply) adds each placement where it
    belongs, backs files up, follows symlinks, and does nothing twice
  - self_update.sh reports and applies updates on scratch git clones, and
    refuses the blocked cases
  - generate_theme.py turns an image into a valid dark/light pair, and exits
    3 naming a missing module (skipped without numpy and Pillow)
  - calendar_sync.py reads a locally served .ics feed into occurrences,
    expands recurrences (DST, UNTIL, RDATE, EXDATE, overrides) without
    recurring-ical-events, and edits events (new, one occurrence, excluded,
    the series moved) so they read back right (skipped without icalendar)
  - cursor_theme.py makes the companion theme filling in a cursor theme's
    missing standard names, and only for a theme that needs it
  - check_sizes.py finds sizes written as numbers, skipping hairlines and
    lines marked `// fixed px:`
  - pick_path.py falls back to zenity/kdialog without a portal, asking for
    a folder or a filtered file, and exits 1 when cancelled, 2 with no picker

  python3 tests/scripts/test_scripts.py [-v] [TestCase[.test_name]]
"""
import configparser
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPTS = ROOT / "scripts"
THEMES = ROOT / "config" / "themes"
BASES = [f"base0{c}" for c in "0123456789ABCDEF"]
SHIPPED_THEMES = sorted(p for p in THEMES.glob("*.json") if p.name != "theme.schema.json") + \
    sorted((THEMES / "generated").glob("*.json"))
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")
# envsubst leaves nothing behind, so a ${VAR} left over is a template typo
UNFILLED = re.compile(r"\$\{[A-Z0-9_]+\}")
# The ncspot x-hookup's text: theme_ncspot.sh fills the lines between them
NCSPOT_MARKERS = "# axiom theme: begin (rewritten on every theme change)\n# axiom theme: end\n"
# Apps the integrations require or signal; stubs keep them from touching a
# running session
STUBS = ["alacritty", "bat", "btop", "foot", "fzf", "ghostty", "hx", "kitty", "lazygit",
         "nvim", "wezterm", "yazi", "qt5ct", "qt6ct", "pkill", "gsettings", "busctl"]


def parallel(fn, items):
    """fn over items on a thread per CPU (they wait on subprocesses), in order"""
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        return list(pool.map(fn, items))


def scratch_env(tmp):
    """Environment with $HOME, XDG dirs and stubbed apps under `tmp`."""
    tmp = Path(tmp)
    stubs = tmp / "stubs"
    stubs.mkdir()
    for name in STUBS:
        stub = stubs / name
        stub.write_text("#!/bin/sh\nexit 0\n")
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
    env = dict(os.environ)
    env.update({
        "HOME": str(tmp / "home"),
        "XDG_CONFIG_HOME": str(tmp / "home" / ".config"),
        "XDG_STATE_HOME": str(tmp / "home" / ".local" / "state"),
        "XDG_DATA_HOME": str(tmp / "home" / ".local" / "share"),
        "XDG_RUNTIME_DIR": str(tmp / "run"),
        "PATH": f"{stubs}:{env['PATH']}",
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


def luminance(color):
    channels = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    r, g, b = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    high, low = sorted((luminance(a), luminance(b)), reverse=True)
    return (high + 0.05) / (low + 0.05)


class TerminalPalette(unittest.TestCase):
    """export_theme_colors / readable_text_colors keep text readable."""
    TEXT = ["RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN", "ORANGE",
            "ERROR", "WARNING", "SUCCESS", "INFO"]

    @classmethod
    def palette(cls, theme):
        """(the palette's variables, bash's stderr when it failed)"""
        script = (f'set -euo pipefail; source "{SCRIPTS}/lib/theme_env.sh"; '
                  f'load_theme "{theme}" >/dev/null; export_theme_colors; readable_text_colors; '
                  'env | grep -E "^(ANSI_[0-9]+|BACKGROUND|THEME_VARIANT|'
                  + "|".join(cls.TEXT) + ')="')
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            return None, result.stderr
        return dict(line.split("=", 1) for line in result.stdout.splitlines()), None

    def test_every_theme_is_readable(self):
        for f, (c, error) in zip(SHIPPED_THEMES, parallel(self.palette, SHIPPED_THEMES)):
            with self.subTest(theme=f.name):
                self.assertIsNone(error)
                bg = c["BACKGROUND"]
                for i in [*range(1, 7), *range(9, 15)]:
                    self.assertGreaterEqual(contrast(c[f"ANSI_{i}"], bg), 4.5, f"ANSI_{i} {c[f'ANSI_{i}']}")
                self.assertGreaterEqual(contrast(c["ANSI_8"], bg), 3.0, f"ANSI_8 {c['ANSI_8']}")
                for key in self.TEXT:
                    self.assertGreaterEqual(contrast(c[key], bg), 4.5, f"{key} {c[key]}")
                if c["THEME_VARIANT"] == "light":
                    self.assertLess(luminance(c["ANSI_0"]), luminance(bg), "black isn't dark")


# Each integration's output format, for the parse checks (the others are
# key=value lines, checked for their colors only)
FORMATS = {
    "alacritty": "toml", "helix": "toml", "wezterm": "toml", "yazi": "toml",
    "k9s": "yaml", "lazygit": "yaml", "bat": "plist", "nvim": "json",
    "vscode": "json", "zed": "json", "qt": "ini", "foot": "ini", "gtk": "css", "vesktop": "css", "ncspot": "toml", "firefox": "css",
}
COLOR = re.compile(r"#([0-9a-fA-F]+)\b")


def run_problems(script, args, env):
    """(problems, result) of running an integration script: a failure, or
    stderr lines starting with "Warning:" (ThemeManager logs them)"""
    result = subprocess.run([str(script)] + [str(a) for a in args], env=env,
                            capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        return [f"{script.name} failed:\n{result.stderr}"], result
    warnings = [line for line in result.stderr.splitlines() if line.startswith("Warning:")]
    return [f"{script.name} warned: {w}" for w in warnings], result


def output_files(root):
    return [p for p in Path(root).rglob("*") if p.is_file()] if Path(root).is_dir() else [Path(root)]


def rendered_problems(root):
    """Something was written, and no file is empty or has unfilled ${VAR}s"""
    files = output_files(root)
    if not files or not files[0].exists():
        return [f"nothing written to {root}"]
    problems = []
    for f in files:
        text = f.read_text()
        if not text.strip():
            problems.append(f"{f} is empty")
        if UNFILLED.findall(text):
            problems.append(f"{f} has unfilled variables: {UNFILLED.findall(text)}")
    return problems


def parse_problems(key, root, gtk=False):
    """Each output file of an integration parses as its format (GTK's own
    CSS parser only when `gtk`: it costs an interpreter per file)"""
    fmt = FORMATS.get(key)
    problems = []
    for f in output_files(root):
        text = f.read_text()
        odd = [m.group(0) for m in COLOR.finditer(text) if len(m.group(1)) not in (6, 8)]
        if odd:
            problems.append(f"{f}: malformed colors {odd}")
        try:
            if fmt == "toml":
                tomllib.loads(text)
            elif fmt == "json" and (f.suffix == ".json" or key == "nvim"):
                json.loads(text)
            elif fmt == "plist":
                plistlib.loads(f.read_bytes())
            elif fmt == "ini":
                configparser.ConfigParser(interpolation=None, strict=False).read_string(text)
            elif fmt == "yaml":
                try:
                    import yaml
                except ImportError:
                    continue
                yaml.safe_load(text)
            elif fmt == "css" and f.suffix == ".css":
                if text.count("{") != text.count("}"):
                    problems.append(f"{f}: unbalanced braces")
                if key == "gtk" and gtk:
                    problems += gtk_css_problems(f)
        except Exception as e:  # noqa: BLE001 (any parser's error is a finding)
            problems.append(f"{f}: doesn't parse as {fmt}: {e}")
    return problems


def gtk_css_problems(path):
    """GTK's own parser, when PyGObject and GTK are installed"""
    version = "4.0" if path.parent.name == "gtk-4.0" else "3.0"
    check = (
        "import sys, gi\n"
        "gi.require_version('Gtk', sys.argv[1])\n"
        "from gi.repository import Gtk\n"
        "errors = []\n"
        "p = Gtk.CssProvider()\n"
        "p.connect('parsing-error', lambda p, s, e: errors.append(e.message))\n"
        "p.load_from_path(sys.argv[2])\n"
        "print('\\n'.join(errors))\n"
    )
    result = subprocess.run([sys.executable, "-c", check, version, str(path)], capture_output=True, text=True)
    if result.returncode != 0 or not result.stdout.strip():
        return []  # fine, or no PyGObject / no GTK of that version
    return [f"{path}: GTK CSS errors:\n{result.stdout.strip()}"]


def integration_args(key, theme, target):
    """(output path to check, the script's arguments) for rendering `theme`
    into the directory `target`"""
    if key in ("gtk", "vscode", "qt"):
        return target, [theme, target]
    if key in ("vesktop", "firefox"):
        target = target / "axiom.css"
        return target, [theme, target]
    if key == "ncspot":
        target = target / "config.toml"
        target.parent.mkdir(parents=True)
        target.write_text("[theme]\n" + NCSPOT_MARKERS)
        return target, [theme, target]
    target = target / "axiom.out"
    return target, [theme, target]


class ThemeIntegrations(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.env = scratch_env(self.tmp)
        self.out = Path(self.tmp) / "out"

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_script(self, script, args):
        problems, result = run_problems(script, args, self.env)
        self.assertEqual(problems, [])
        return result

    def test_every_integration_renders(self):
        scripts = sorted(SCRIPTS.glob("theme_*.sh"))
        self.assertTrue(scripts)
        # GTK's parser checks one theme of each variant
        gtk_themes = {next(t for t in SHIPPED_THEMES if json.loads(t.read_text()).get("variant") == v)
                      for v in ("dark", "light")}
        jobs = [(theme, script) for theme in SHIPPED_THEMES for script in scripts]

        def render(job):
            theme, script = job
            key = script.stem.removeprefix("theme_")
            target, args = integration_args(key, theme, self.out / theme.stem / key)
            problems, _ = run_problems(script, args, self.env)
            if not problems:
                problems = rendered_problems(target) + parse_problems(key, target, theme in gtk_themes)
            return problems

        for (theme, script), problems in zip(jobs, parallel(render, jobs)):
            with self.subTest(script=script.name, theme=theme.name):
                self.assertEqual(problems, [])

    def test_qt_keeps_kdeglobals_in_step_once_chosen(self):
        kdeglobals = Path(self.env["XDG_CONFIG_HOME"]) / "kdeglobals"
        kdeglobals.parent.mkdir(parents=True)
        mine = "[Colors:View]\nBackgroundNormal=1,2,3\nCustom=x\n\n[General]\nColorScheme=BreezeDark\n\n[WM]\nactiveFont=Sans,10\n"
        kdeglobals.write_text(mine)
        theme = THEMES / "ayu-dark.json"
        self.run_script(SCRIPTS / "theme_qt.sh", [theme])
        scheme = Path(self.env["XDG_DATA_HOME"]) / "color-schemes" / "Axiom.colors"
        self.assertTrue(scheme.is_file())
        self.assertEqual(kdeglobals.read_text(), mine, "untouched until it names the scheme")
        kdeglobals.write_text(mine.replace("BreezeDark", "Axiom"))
        self.run_script(SCRIPTS / "theme_qt.sh", [theme])
        first = kdeglobals.read_text()
        data = configparser.ConfigParser(interpolation=None, strict=False)
        data.optionxform = str
        data.read_string(first)
        colors = configparser.ConfigParser(interpolation=None, strict=False)
        colors.optionxform = str
        colors.read_string(scheme.read_text())
        self.assertEqual(data["Colors:View"]["BackgroundNormal"], colors["Colors:View"]["BackgroundNormal"])
        self.assertRegex(data["Colors:View"]["BackgroundNormal"], r"^\d+,\d+,\d+$")
        self.assertEqual(data["Colors:View"]["Custom"], "x", "keys the scheme doesn't set stay")
        self.assertEqual(data["WM"]["activeFont"], "Sans,10")
        self.assertEqual(data["WM"]["activeBackground"], colors["WM"]["activeBackground"])
        self.assertEqual(dict(data["Colors:Selection"]), dict(colors["Colors:Selection"]), "missing groups are added")
        self.assertEqual(dict(data["General"]), {"ColorScheme": "Axiom"})
        self.run_script(SCRIPTS / "theme_qt.sh", [theme])
        self.assertEqual(kdeglobals.read_text(), first, "a second run changes nothing")

    def test_qt_warns_of_kde_apps_picking_their_own_scheme(self):
        """Okular and the like read [UiSettings] from their own rc before
        kdeglobals': one naming another scheme there is said, not changed."""
        config = Path(self.env["XDG_CONFIG_HOME"])
        config.mkdir(parents=True)
        (config / "kdeglobals").write_text("[General]\nColorScheme=Axiom\n\n[UiSettings]\nColorScheme=Axiom\n")
        okular = config / "okularrc"
        okular.write_text("[UiSettings]\nColorScheme=BreezeDark\n")
        (config / "dolphinrc").write_text("[UiSettings]\nColorScheme=Axiom\n")
        (config / "katerc").write_text("[General]\nColorScheme=Other\n")
        problems, _ = run_problems(SCRIPTS / "theme_qt.sh", [THEMES / "ayu-dark.json"], self.env)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("okularrc", problems[0])
        self.assertIn("BreezeDark", problems[0])
        self.assertEqual(okular.read_text(), "[UiSettings]\nColorScheme=BreezeDark\n")
        okular.write_text("[UiSettings]\nColorScheme=Axiom\n")
        self.assertEqual(run_problems(SCRIPTS / "theme_qt.sh", [THEMES / "ayu-dark.json"], self.env)[0], [])

    def test_ncspot_leaves_your_keys(self):
        config = self.out / "config.toml"
        config.parent.mkdir(parents=True)
        config.write_text('use_nerdfont = true\n\n[theme]\nprimary = "red"\n' + NCSPOT_MARKERS + '\n[keybindings]\n"q" = "quit"\n')
        theme = THEMES / "ayu-dark.json"
        self.run_script(SCRIPTS / "theme_ncspot.sh", [theme, config])
        first = config.read_text()
        data = tomllib.loads(first)
        self.assertEqual(data["theme"]["primary"], "red")
        self.assertIn("background", data["theme"])
        self.assertEqual(data["keybindings"], {"q": "quit"})
        self.run_script(SCRIPTS / "theme_ncspot.sh", [theme, config])
        self.assertEqual(config.read_text(), first)

    def test_nvim_module_compiles(self):
        luac = shutil.which("luac")
        if not luac:
            self.skipTest("no luac")
        module = SCRIPTS / "templates" / "nvim" / "axiom_theme.lua"
        result = subprocess.run([luac, "-p", str(module)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_nvim_palette_has_readable_accents(self):
        target = self.out / "nvim-theme.json"
        for theme in (THEMES / "ayu-light.json", THEMES / "submarine-sonar.json"):
            with self.subTest(theme=theme.name):
                self.run_script(SCRIPTS / "theme_nvim.sh", [theme, target])
                data = json.loads(target.read_text())
                semantic = data["semantic"]
                self.assertRegex(semantic["accent"], HEX)
                for key in ("accent", "accentAlt"):
                    self.assertGreaterEqual(contrast(data["text"][key], semantic["background"]), 4.5, key)

    def test_nvim_module_maps_shipped_themes(self):
        text = (SCRIPTS / "templates" / "nvim" / "axiom_theme.lua").read_text()
        mapped = set(re.findall(r'^\s*\["([\w-]+)"\] = scheme\(', text, re.M))
        shipped = {p.stem for p in THEMES.glob("*.json")} - {"theme.schema"}
        self.assertEqual(mapped - shipped, set(), "map entries without a theme")
        self.assertEqual(shipped - mapped - {"submarine-sonar", "submarine-sonar-light", "nord-light", "alucard"},
                         set(), "themes without a map entry")


class HookupScript(unittest.TestCase):
    """integration_hookup.py on scratch configs (ThemeIntegrations' x-hookup)"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.env = scratch_env(self.tmp)
        self.env["SHELL"] = "/bin/bash"
        self.config = Path(self.env["XDG_CONFIG_HOME"])

    def tearDown(self):
        system = Path(self.tmp) / "system"
        if system.is_dir():
            system.chmod(0o755)
        shutil.rmtree(self.tmp)

    def hookup(self, action, key, schema=None, targets=None):
        args = [sys.executable, str(SCRIPTS / "integration_hookup.py"), action, key]
        if schema:
            args += ["--schema", str(schema)]
        if targets is not None:
            args += ["--targets", json.dumps(targets)]
        result = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def write(self, rel, text):
        path = self.config / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def backups(self, path):
        return sorted(Path(path).parent.glob(Path(path).name + ".axiom-bak-*"))

    def test_every_hookup_applies_to_empty_configs(self):
        schema = json.loads((ROOT / "config/json/config.schema.json").read_text())
        for key, prop in schema["properties"]["ThemeIntegrations"]["properties"].items():
            with self.subTest(key=key):
                self.assertIn("x-hookup", prop)
                self.hookup("apply", key)
                for target in self.hookup("status", key)["targets"]:
                    if not target["copyOnly"] and not target["skipped"]:
                        self.assertTrue(target["done"], f"{key}: {target}")

    def test_per_profile_targets(self):
        home = Path(self.env["HOME"])
        root = home / ".mozilla" / "firefox"
        for profile in ("a.default-release", "b c.other"):
            (root / profile).mkdir(parents=True)
        (root / "profiles.ini").write_text(
            "[Profile0]\nIsRelative=1\nPath=a.default-release\n\n"
            "[Profile1]\nIsRelative=1\nPath=b c.other\n\n[General]\nVersion=2\n")
        (root / "a.default-release" / "user.js").write_text(
            'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);\n')
        targets = self.hookup("status", "firefox")["targets"]
        self.assertEqual(len(targets), 4)
        self.hookup("apply", "firefox")
        self.assertTrue(all(t["done"] for t in self.hookup("status", "firefox")["targets"]))
        for profile in ("a.default-release", "b c.other"):
            css = (root / profile / "chrome" / "userChrome.css").read_text()
            self.assertTrue(css.startswith('@import url("axiom.css");'))
            prefs = (root / profile / "user.js").read_text().splitlines()
            self.assertEqual(prefs[-1], 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);')
        # The theme script themes the same profiles
        result = subprocess.run([str(SCRIPTS / "theme_firefox.sh"), str(THEMES / "ayu-dark.json")],
                                env=self.env, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        for profile in ("a.default-release", "b c.other"):
            self.assertTrue((root / profile / "chrome" / "axiom.css").is_file())

    def test_per_profile_without_profiles_is_skipped(self):
        targets = self.hookup("status", "firefox")["targets"]
        self.assertTrue(targets)
        self.assertTrue(all(t["skipped"] == "profiles" for t in targets))

    def readonly_file(self, name, text):
        """A file in a directory the user can't write (like /usr/share/themes)"""
        if os.geteuid() == 0:
            self.skipTest("root can write anywhere")
        theme = Path(self.tmp) / "system" / name
        theme.parent.mkdir(parents=True)
        theme.write_text(text)
        theme.chmod(0o444)
        theme.parent.chmod(0o555)
        return theme

    def test_link_to_a_readonly_file_is_skipped(self):
        real = self.readonly_file("kitty.conf", "font_size 12\n")
        link = self.config / "kitty" / "kitty.conf"
        link.parent.mkdir(parents=True)
        link.symlink_to(real)
        self.assertEqual(self.hookup("status", "kitty")["targets"][0]["skipped"], "readonly")
        result = self.hookup("apply", "kitty")["results"][0]
        self.assertFalse(result["changed"])
        self.assertEqual(result["error"], "")
        self.assertTrue(link.is_symlink())
        self.assertEqual(real.read_text(), "font_size 12\n")

    def test_gtk_link_to_a_theme_is_wrapped(self):
        real = self.readonly_file("gtk.css", "@define-color window_bg_color #fff;\n")
        self.write("gtk-3.0/gtk.css", "")
        link = self.config / "gtk-4.0" / "gtk.css"
        link.parent.mkdir(parents=True)
        link.symlink_to(real)
        status = self.hookup("status", "gtk")["targets"][1]
        self.assertTrue(status["wraps"])
        self.assertEqual(status["skipped"], "")
        self.hookup("apply", "gtk")
        self.assertFalse(link.is_symlink())
        self.assertEqual(link.read_text(), f'@import url("file://{real}");\n@import url("axiom.css");\n')
        backups = self.backups(link)
        self.assertEqual(len(backups), 1)
        self.assertEqual(os.readlink(backups[0]), str(real))
        self.assertTrue(self.hookup("status", "gtk")["targets"][1]["done"])

    def test_qt_names_the_scheme_for_kde_apps_with_their_own_menu(self):
        """kdeglobals gets ColorScheme=Axiom in [General] (KColorScheme's
        copy) and in [UiSettings], which KColorSchemeManager apps (Okular,
        Dolphin) read and otherwise fall back to Breeze from: two targets in
        one file, both applied, the user's own choice commented out."""
        kdeglobals = self.write("kdeglobals", "[General]\nColorScheme=BreezeDark\n\n[UiSettings]\nColorScheme=BreezeDark\n\n[KDE]\nwidgetStyle=Fusion\n")
        targets = [t for t in self.hookup("status", "qt")["targets"] if t["path"].endswith("kdeglobals")]
        self.assertEqual([(t["section"], t["done"]) for t in targets], [("General", False), ("UiSettings", False)])
        self.hookup("apply", "qt")
        data = configparser.ConfigParser(interpolation=None, strict=False, comment_prefixes=("#",))
        data.optionxform = str
        data.read_string(kdeglobals.read_text())
        self.assertEqual(data["General"]["ColorScheme"], "Axiom")
        self.assertEqual(data["UiSettings"]["ColorScheme"], "Axiom")
        self.assertEqual(data["KDE"]["widgetStyle"], "Fusion")
        self.assertEqual(kdeglobals.read_text().count("# axiom: ColorScheme=BreezeDark"), 2)
        self.assertTrue(all(t["done"] for t in self.hookup("status", "qt")["targets"] if t["path"].endswith("kdeglobals")))
        # Without a [UiSettings] of its own, Apply adds the group
        kdeglobals.write_text("[General]\nColorScheme=Axiom\n")
        self.hookup("apply", "qt")
        data = configparser.ConfigParser(interpolation=None, strict=False)
        data.optionxform = str
        data.read_string(kdeglobals.read_text())
        self.assertEqual(data["UiSettings"]["ColorScheme"], "Axiom")

    def test_end_keeps_a_symlink_and_backs_up(self):
        real = Path(self.tmp) / "dotfiles" / "kitty.conf"
        real.parent.mkdir()
        real.write_text("font_size 12\n")
        link = self.config / "kitty" / "kitty.conf"
        link.parent.mkdir(parents=True)
        link.symlink_to(real)
        status = self.hookup("status", "kitty")["targets"][0]
        self.assertTrue(status["link"])
        self.hookup("apply", "kitty")
        self.assertTrue(link.is_symlink())
        self.assertEqual(real.read_text(), "font_size 12\n\ninclude axiom.conf\n")
        self.assertEqual(len(self.backups(real)), 1)
        self.assertEqual(self.backups(real)[0].read_text(), "font_size 12\n")
        # Done: a second Apply changes nothing
        self.assertFalse(self.hookup("apply", "kitty")["results"][0]["changed"])
        self.assertEqual(len(self.backups(real)), 1)

    def test_given_targets_hook_hyprland_up(self):
        path = self.write("hypr/hyprland.lua", '-- mine\nhl.bind("SUPER + Q", hl.dsp.exec_cmd("kitty"))\n')
        include = {"file": str(path), "place": "start", "comment": "--", "accept": r"axiom\.setup\(",
                   "text": 'local ok, axiom = pcall(dofile, "/x/axiom/hyprland.lua")\nif ok then axiom.setup() end'}
        autostart = {"file": str(path), "place": "end", "comment": "--", "accept": r"(^|[\s'\"/])axiom['\"]? +run\b",
                     "text": 'hl.on("hyprland.start", function() hl.exec_cmd("\'/x/axiom\' run") end) -- axiom'}
        targets = [include, autostart]
        self.assertFalse(any(t["done"] for t in self.hookup("status", "hyprland", targets=targets)["targets"]))
        self.hookup("apply", "hyprland", targets=targets)
        lines = path.read_text().splitlines()
        self.assertEqual(lines[:2], include["text"].splitlines())
        self.assertEqual(lines[-1], autostart["text"])
        self.assertEqual(len(self.backups(path)), 1)
        self.assertTrue(all(t["done"] for t in self.hookup("status", "hyprland", targets=targets)["targets"]))
        # install.sh's own autostart line counts as done
        path.write_text('hl.on("hyprland.start", function() hl.exec_cmd("\'/usr/bin/axiom\' run") end) -- axiom\n')
        self.assertTrue(self.hookup("status", "hyprland", targets=[autostart])["targets"][0]["done"])

    def test_start_goes_first(self):
        path = self.write("gtk-3.0/gtk.css", "window { color: red; }\n")
        self.hookup("apply", "gtk")
        self.assertEqual(path.read_text().splitlines()[0], '@import url("axiom.css");')

    def test_top_comments_out_the_old_key(self):
        path = self.write("helix/config.toml", 'theme = "onedark"\n\n[editor]\nline-number = "relative"\n')
        status = self.hookup("status", "helix")["targets"][0]
        self.assertEqual(status["replaces"], ['theme = "onedark"'])
        self.hookup("apply", "helix")
        parsed = tomllib.loads(path.read_text())
        self.assertEqual(parsed["theme"], "axiom")
        self.assertEqual(parsed["editor"], {"line-number": "relative"})
        self.assertIn('# axiom: theme = "onedark"', path.read_text())

    def test_section_present_and_missing(self):
        path = self.write("yazi/theme.toml", '[flavor]\ndark = "x"\n\n[mgr]\nfoo = 1\n')
        self.hookup("apply", "yazi")
        self.assertEqual(tomllib.loads(path.read_text())["flavor"], {"dark": "axiom", "light": "axiom"})
        path.write_text("[mgr]\nfoo = 1\n")
        self.assertTrue(self.hookup("status", "yazi")["targets"][0]["createsSection"])
        self.hookup("apply", "yazi")
        self.assertEqual(tomllib.loads(path.read_text())["flavor"], {"dark": "axiom", "light": "axiom"})

    def test_keep_leaves_other_lines(self):
        path = self.write("foot/foot.ini", "include=~/mine.ini\n\n[main]\nfont=x\n")
        status = self.hookup("status", "foot")["targets"][0]
        self.assertEqual(status["alongside"], ["include=~/mine.ini"])
        self.hookup("apply", "foot")
        lines = path.read_text().splitlines()
        self.assertEqual(lines[0], "include=~/mine.ini")
        self.assertTrue(lines[1].startswith("include=") and lines[1].endswith("foot/axiom.ini"))

    def test_conflict_is_left_alone(self):
        path = self.write("alacritty/alacritty.toml", '[general]\nimport = ["~/mine.toml"]\n')
        status = self.hookup("status", "alacritty")["targets"][0]
        self.assertEqual(status["conflicts"], ['import = ["~/mine.toml"]'])
        result = self.hookup("apply", "alacritty")["results"][0]
        self.assertEqual(result["error"], "conflict")
        self.assertEqual(path.read_text(), '[general]\nimport = ["~/mine.toml"]\n')

    def test_accept_counts_another_spelling(self):
        self.write("btop/btop.conf", 'color_theme = "/home/me/.config/btop/themes/axiom.theme"\n')
        self.assertTrue(self.hookup("status", "btop")["targets"][0]["done"])

    def test_shellrc_and_fish(self):
        self.hookup("apply", "fzf")
        rc = Path(self.env["HOME"]) / ".bashrc"
        self.assertIn("export FZF_DEFAULT_OPTS_FILE=", rc.read_text())
        self.env["SHELL"] = "/usr/bin/fish"
        self.hookup("apply", "fzf")
        fish = self.config / "fish" / "conf.d" / "axiom.fish"
        self.assertTrue(fish.read_text().startswith("set -gx FZF_DEFAULT_OPTS_FILE "))

    def test_requires_skips(self):
        schema = {"properties": {"ThemeIntegrations": {"properties": {"x": {"x-hookup": [
            {"file": "{config}/x.conf", "place": "end", "text": "x", "requires": "axiom-no-such-command"}]}}}}}
        path = Path(self.tmp) / "schema.json"
        path.write_text(json.dumps(schema))
        self.assertEqual(self.hookup("status", "x", path)["targets"][0]["skipped"], "requires")
        self.hookup("apply", "x", path)
        self.assertFalse((self.config / "x.conf").exists())

    def test_copy_never_overwrites(self):
        module = self.write("nvim/lua/axiom_theme.lua", "-- mine\n")
        self.hookup("apply", "nvim")
        self.assertEqual(module.read_text(), "-- mine\n")
        module.unlink()
        self.hookup("apply", "nvim")
        self.assertEqual(module.read_text(), (SCRIPTS / "templates/nvim/axiom_theme.lua").read_text())


class SelfUpdate(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.env = scratch_env(self.tmp)
        self.env.update({"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
                         "GIT_COMMITTER_EMAIL": "t@t"})
        self.upstream = self.tmp / "upstream"
        self.git("init", "-q", "-b", "main", str(self.upstream), cwd=self.tmp)
        self.commit(self.upstream, "one")
        self.git("tag", "-a", "v1.0.0", "-m", "first", cwd=self.upstream)
        self.clone = self.tmp / "clone"
        self.git("clone", "-q", str(self.upstream), str(self.clone), cwd=self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def git(self, *args, cwd):
        subprocess.run(["git", *args], cwd=cwd, env=self.env, check=True, capture_output=True)

    def commit(self, repo, name):
        (repo / f"{name}.txt").write_text(name)
        self.git("add", ".", cwd=repo)
        self.git("commit", "-q", "-m", name, cwd=repo)

    def release(self, tag, notes="notes"):
        self.commit(self.upstream, tag)
        self.git("tag", "-a", tag, "-m", notes, cwd=self.upstream)

    def run_update(self, *args, ok=True):
        result = subprocess.run([str(SCRIPTS / "self_update.sh"), *args, str(self.clone)], env=self.env,
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_uptodate(self):
        report = self.run_update("check")
        self.assertEqual((report["state"], report["current"], report["blocked"]), ("uptodate", "v1.0.0", ""))

    def test_available_then_applied(self):
        self.release("v1.1.0", "Better things")
        report = self.run_update("check")
        self.assertEqual((report["state"], report["latest"], report["behind"]), ("available", "v1.1.0", 1))
        self.assertIn("Better things", report["notes"])
        applied = self.run_update("apply", "v1.1.0")
        self.assertEqual((applied["state"], applied["current"], applied["error"]), ("uptodate", "v1.1.0", ""))
        self.assertTrue((self.clone / "v1.1.0.txt").exists())

    def test_dirty_clone_is_blocked(self):
        self.release("v1.1.0")
        self.run_update("check")
        (self.clone / "one.txt").write_text("local edit")
        self.assertEqual(self.run_update("check")["blocked"], "dirty")
        self.run_update("apply", "v1.1.0", ok=False)
        self.assertEqual((self.clone / "one.txt").read_text(), "local edit")

    def test_diverged_clone_is_blocked(self):
        self.release("v1.1.0")
        self.commit(self.clone, "mine")
        report = self.run_update("check")
        self.assertEqual((report["state"], report["blocked"]), ("diverged", "diverged"))
        self.run_update("apply", "v1.1.0", ok=False)

    def test_other_branch_is_blocked(self):
        self.release("v1.1.0")
        self.git("checkout", "-q", "-b", "feature", cwd=self.clone)
        self.assertEqual(self.run_update("check")["blocked"], "branch")

    def test_only_the_latest_tag_applies(self):
        self.release("v1.1.0")
        self.release("v1.2.0")
        self.run_update("check")
        self.assertIn("not an available update", self.run_update("apply", "v1.1.0", ok=False)["error"])

    def test_not_a_clone(self):
        shutil.rmtree(self.clone / ".git")
        self.assertEqual(self.run_update("check")["blocked"], "nogit")

    def test_main_channel_follows_commits(self):
        self.commit(self.upstream, "two")
        self.assertEqual(self.run_update("check")["state"], "uptodate")
        report = self.run_update("--channel", "main", "check")
        self.assertEqual((report["channel"], report["state"], report["behind"], report["current"]),
                         ("main", "available", 1, "v1.0.0"))
        self.assertIn("- two", report["notes"])
        applied = self.run_update("--channel", "main", "apply", report["latest"])
        self.assertEqual((applied["state"], applied["ahead"], applied["error"]), ("uptodate", False, ""))
        self.assertTrue((self.clone / "two.txt").exists())
        # Back on tags, being past the newest release isn't a downgrade
        report = self.run_update("check")
        self.assertEqual((report["state"], report["ahead"]), ("uptodate", True))

    def test_main_channel_falls_back_to_master(self):
        self.git("branch", "-m", "main", "master", cwd=self.upstream)
        self.commit(self.upstream, "two")
        report = self.run_update("--channel", "main", "check")
        self.assertEqual((report["state"], report["error"]), ("available", ""))

    def test_main_channel_detached_clone(self):
        self.git("checkout", "-q", "v1.0.0", cwd=self.clone)
        self.commit(self.upstream, "two")
        report = self.run_update("--channel", "main", "check")
        self.assertEqual((report["state"], report["blocked"]), ("available", ""))
        self.run_update("--channel", "main", "apply", report["latest"])
        self.assertTrue((self.clone / "two.txt").exists())


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


class CommunityFetch(unittest.TestCase):
    """community_fetch.sh: downloads from a local server, checks sha256,
    keeps a cached file without fetching, and never leaves a bad file."""

    @classmethod
    def setUpClass(cls):
        import functools
        import http.server
        import threading
        cls.served = Path(tempfile.mkdtemp())
        (cls.served / "a.json").write_text('{"a": 1}')
        class Quiet(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass
        handler = functools.partial(Quiet, directory=str(cls.served))
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}/"
        cls.sha = hashlib.sha256(b'{"a": 1}').hexdigest()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        shutil.rmtree(cls.served)

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def fetch(self, *args):
        return subprocess.run([str(SCRIPTS / "community_fetch.sh"), *args], capture_output=True, text=True, timeout=30)

    def test_downloads_and_checks(self):
        dest = self.tmp / "sub" / "a.json"
        run = self.fetch(self.base + "a.json", str(dest), self.sha, self.base + "a.json", str(self.tmp / "nosha.json"), "-")
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual(dest.read_text(), '{"a": 1}')
        self.assertTrue((self.tmp / "nosha.json").exists())
        self.assertEqual(run.stdout.splitlines(), [f"ok {dest}", f"ok {self.tmp / 'nosha.json'}"])

    def test_bad_checksum_leaves_nothing(self):
        dest = self.tmp / "a.json"
        run = self.fetch(self.base + "a.json", str(dest), "0" * 64)
        self.assertEqual(run.returncode, 1)
        self.assertIn("checksum mismatch", run.stdout)
        self.assertEqual(list(self.tmp.iterdir()), [], "no file, no .part")

    def test_cached_file_is_kept(self):
        dest = self.tmp / "a.json"
        dest.write_text('{"a": 1}')
        run = self.fetch(self.base + "missing.json", str(dest), self.sha)
        self.assertEqual(run.returncode, 0, "a matching file isn't fetched again")

    def test_failures_are_reported_per_file(self):
        good, bad = self.tmp / "good.json", self.tmp / "bad.json"
        run = self.fetch(self.base + "missing.json", str(bad), "-", self.base + "a.json", str(good), self.sha)
        self.assertEqual(run.returncode, 1)
        self.assertTrue(run.stdout.startswith(f"fail {bad}"))
        self.assertIn(f"ok {good}", run.stdout)
        self.assertFalse(bad.exists())

    def test_only_http(self):
        run = self.fetch("file:///etc/hostname", str(self.tmp / "x"), "-")
        self.assertEqual(run.returncode, 1)
        self.assertFalse((self.tmp / "x").exists())

    def test_usage(self):
        self.assertEqual(self.fetch("only-one").returncode, 2)


def skip_without_modules(*modules):
    """Skips (fails in CI, which installs them) when python3 lacks one of
    the system packages a script uses."""
    import importlib.util
    missing = [m for m in modules if importlib.util.find_spec(m) is None]
    if missing:
        message = f"python modules not installed: {', '.join(missing)}"
        if os.environ.get("CI"):
            raise AssertionError(message)
        raise unittest.SkipTest(message)


class GenerateTheme(unittest.TestCase):
    def test_missing_module_exits_3(self):
        tmp = Path(tempfile.mkdtemp())
        try:
            # A numpy that can't be imported, ahead of the real one
            (tmp / "numpy.py").write_text("raise ModuleNotFoundError('no numpy', name='numpy')\n")
            env = dict(scratch_env(tmp), PYTHONPATH=str(tmp))
            result = subprocess.run([sys.executable, str(SCRIPTS / "generate_theme.py"), str(tmp / "x.png"),
                                     "--output_dir", str(tmp)], env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertEqual(result.stderr.strip(), "missing python module: numpy")
        finally:
            shutil.rmtree(tmp)

    def test_wallpaper_makes_a_valid_pair(self):
        skip_without_modules("numpy", "PIL")
        tmp = Path(tempfile.mkdtemp())
        try:
            env = scratch_env(tmp)
            python = sys.executable
            image = tmp / "wall.png"
            # Bands of colour, so every accent slot has something to pick from
            subprocess.run([python, "-c", (
                "from PIL import Image\n"
                "img = Image.new('RGB', (120, 80))\n"
                "cols = [(30, 40, 90), (200, 80, 60), (60, 160, 90), (220, 200, 80), (140, 60, 160)]\n"
                "for x in range(120):\n"
                "    for y in range(80):\n"
                "        img.putpixel((x, y), cols[(x // 24) % len(cols)])\n"
                f"img.save({str(image)!r})\n")], check=True, env=env)
            out = tmp / "themes"
            out.mkdir()
            result = subprocess.run([python, str(SCRIPTS / "generate_theme.py"), str(image), "--output_dir",
                                     str(out)], env=env, capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stderr)
            styles = ["alternate", "faithful", "muted", "tonal", "vibrant"]
            files = sorted(out.glob("*.json"))
            self.assertEqual([f.stem for f in files],
                             [f"wallpaper-{s}-{v}" for s in styles for v in ("dark", "light")])
            themes = {f.stem: json.loads(f.read_text()) for f in files}
            names = {t["name"] for t in themes.values()} | set(themes)
            for stem, theme in themes.items():
                with self.subTest(theme=stem):
                    self.assertEqual(theme["variant"], stem.rsplit("-", 1)[1])
                    self.assertEqual(theme_problems(theme, names), [])
            # Every style looks different from every other
            palettes = [tuple(sorted(themes[f"wallpaper-{s}-dark"]["colors"].items())) for s in styles]
            self.assertEqual(len(set(palettes)), len(styles))
        finally:
            shutil.rmtree(tmp)


CALENDAR_FEED = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
X-WR-CALNAME:Team
X-APPLE-CALENDAR-COLOR:#3366CCFF
BEGIN:VEVENT
UID:weekly
DTSTART;TZID=Europe/Berlin:20260707T100000
DTEND;TZID=Europe/Berlin:20260707T103000
RRULE:FREQ=WEEKLY;COUNT=4
EXDATE;TZID=Europe/Berlin:20260714T100000
SUMMARY:Standup
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER:-PT15M
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:weekly
RECURRENCE-ID;TZID=Europe/Berlin:20260721T100000
DTSTART;TZID=Europe/Berlin:20260721T120000
DTEND;TZID=Europe/Berlin:20260721T123000
SUMMARY:Standup (moved)
END:VEVENT
BEGIN:VEVENT
UID:trip
DTSTART;VALUE=DATE:20260710
DTEND;VALUE=DATE:20260713
SUMMARY:Trip
LOCATION:Coast
END:VEVENT
END:VCALENDAR
"""


class CalendarSync(unittest.TestCase):
    """calendar_sync.py: an .ics feed served locally (discover, sync and the
    occurrences it writes), and the edits it makes to events, without a
    server. Times in UTC (TZ), so the expected values don't depend on the
    machine. recurring-ical-events is made unimportable: Fedora doesn't
    package it, so the helper must never use it, even where it's installed.
    Skipped without icalendar."""

    @classmethod
    def setUpClass(cls):
        skip_without_modules("icalendar", "dateutil")
        cls.tmp = Path(tempfile.mkdtemp())
        blocked = cls.tmp / "blocked"
        blocked.mkdir()
        (blocked / "recurring_ical_events.py").write_text(
            "raise ImportError('calendar_sync.py must not use recurring_ical_events (not packaged on Fedora)')\n")
        cls.env = dict(scratch_env(cls.tmp), TZ="UTC", PYTHONPATH=str(blocked))
        cls.python = sys.executable

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_helper(self, command, request):
        result = subprocess.run([self.python, str(SCRIPTS / "calendar_sync.py"), command], input=json.dumps(request),
                                env=self.env, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def serve(self, directory):
        import functools
        import http.server
        import threading
        class Quiet(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(directory)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_address[1]}"

    def test_feed_discover_and_sync(self):
        site = self.tmp / "site"
        site.mkdir(exist_ok=True)
        (site / "team.ics").write_text(CALENDAR_FEED)
        url = self.serve(site) + "/team.ics"

        found = self.run_helper("discover", {"kind": "ics", "url": url})
        self.assertEqual(found["calendars"], [{"href": url, "name": "Team", "color": "#3366CC",
                                               "components": ["VEVENT"], "readOnly": True}])

        state = self.tmp / "state"
        ms = lambda *args: int(__import__("datetime").datetime(*args, tzinfo=__import__("datetime").timezone.utc)
                               .timestamp() * 1000)
        result = self.run_helper("sync", {
            "stateDir": str(state),
            "range": {"from": ms(2026, 7, 1), "to": ms(2026, 8, 1)},
            "accounts": [{"id": "feed", "kind": "ics", "url": url, "calendars": [{"href": url}]}],
        })
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["errors"], [])
        events = json.loads((state / "events.json").read_text())["events"]
        self.assertEqual(stat.S_IMODE((state / "events.json").stat().st_mode), 0o600)
        self.assertEqual([(e["title"], e["start"]) for e in events], [
            ("Standup", ms(2026, 7, 7, 8)),           # 10:00 in Berlin's summer time
            ("Trip", ms(2026, 7, 10)),
            ("Standup (moved)", ms(2026, 7, 21, 10)),  # the override; the 14th is excluded
            ("Standup", ms(2026, 7, 28, 8)),
        ])
        first, trip, moved = events[0], events[1], events[2]
        self.assertEqual(first["calendar"], "feed|" + url)
        self.assertTrue(first["recurring"])
        self.assertEqual(first["repeat"], "custom")  # COUNT makes it more than a plain weekly rule
        self.assertEqual(first["reminder"], 15)
        self.assertEqual(first["alarms"], [ms(2026, 7, 7, 7, 45)])
        self.assertEqual(moved["rid"], f"T:{ms(2026, 7, 21, 8) // 1000}")
        self.assertEqual(moved["alarms"], [])
        self.assertTrue(trip["allDay"])
        self.assertEqual((trip["dayStart"], trip["dayEnd"], trip["location"]), ("2026-07-10", "2026-07-13", "Coast"))
        self.assertFalse(trip["recurring"])
        self.assertEqual(trip["rid"], "")

        # A feed that's gone keeps the last copy and reports it
        (site / "team.ics").unlink()
        result = self.run_helper("sync", {
            "stateDir": str(state),
            "range": {"from": ms(2026, 7, 1), "to": ms(2026, 8, 1)},
            "accounts": [{"id": "feed", "kind": "ics", "url": url, "calendars": [{"href": url}]}],
        })
        self.assertEqual([e["code"] for e in result["errors"]], ["notFound"])
        self.assertEqual(len(json.loads((state / "events.json").read_text())["events"]), 4)

    def test_local_calendar(self):
        """A local calendar: an event saved as a file in its folder, edited,
        read back by sync and deleted. Hrefs outside <dataDir>/calendars
        are refused."""
        data, state = self.tmp / "local-data", self.tmp / "local-state"
        ms = lambda *args: int(__import__("datetime").datetime(*args, tzinfo=__import__("datetime").timezone.utc)
                               .timestamp() * 1000)
        base = {
            "stateDir": str(state), "dataDir": str(data),
            "range": {"from": ms(2026, 7, 1), "to": ms(2026, 8, 1)},
            "accounts": [{"id": "here", "kind": "local", "calendars": [{"href": "personal"}]}],
        }
        event = {"title": "Dentist", "allDay": False, "start": ms(2026, 7, 9, 14), "end": ms(2026, 7, 9, 15),
                 "reminder": -1}
        saved = self.run_helper("save", dict(base, account="here", calendar="personal", scope="series", event=event))
        self.assertTrue(saved["ok"], saved)
        path = data / "calendars" / saved["href"]
        self.assertTrue(path.is_file())
        events = json.loads((state / "events.json").read_text())["events"]
        self.assertEqual([(e["title"], e["start"], e["calendar"]) for e in events],
                         [("Dentist", ms(2026, 7, 9, 14), "here|personal")])

        edited = self.run_helper("save", dict(base, account="here", calendar="personal", scope="series",
                                              href=saved["href"], etag=events[0]["etag"],
                                              event=dict(event, title="Dentist (moved)")))
        self.assertTrue(edited["ok"], edited)
        events = json.loads((state / "events.json").read_text())["events"]
        self.assertEqual([e["title"] for e in events], ["Dentist (moved)"])
        # A stale etag is a conflict, not an overwrite
        stale = self.run_helper("save", dict(base, account="here", calendar="personal", scope="series",
                                             href=saved["href"], etag="0-0", event=event))
        self.assertEqual(stale["code"], "conflict")

        # A file dropped into the folder by hand is picked up
        (data / "calendars" / "personal" / "extra.ics").write_text(CALENDAR_FEED)
        synced = self.run_helper("sync", base)
        self.assertTrue(synced["changed"])
        self.assertGreater(len(json.loads((state / "events.json").read_text())["events"]), 1)
        (data / "calendars" / "personal" / "extra.ics").unlink()

        deleted = self.run_helper("delete", dict(base, account="here", calendar="personal", scope="series",
                                                 href=saved["href"], etag=events[0]["etag"]))
        self.assertTrue(deleted["ok"], deleted)
        self.assertFalse(path.exists())
        self.assertEqual(json.loads((state / "events.json").read_text())["events"], [])

        for bad in ("..", "a/b"):
            refused = self.run_helper("sync", dict(base, accounts=[{"id": "here", "kind": "local",
                                                                    "calendars": [{"href": bad}]}]))
            self.assertEqual([e["code"] for e in refused["errors"]], ["notFound"], bad)
        refused = self.run_helper("delete", dict(base, account="here", calendar="personal", scope="series",
                                                 href="personal/../../escape.ics", etag=""))
        self.assertEqual(refused["code"], "notFound")

    def test_edits(self):
        """New events, a moved occurrence, an excluded one and a shifted
        series, read back through the same expansion the sync uses."""
        script = r'''
import datetime as dt, json, sys
sys.path.insert(0, sys.argv[1])
import calendar_sync as c
import icalendar
utc = dt.timezone.utc
tz = c.local_zone()
ms = lambda *a: int(dt.datetime(*a, tzinfo=utc).timestamp() * 1000)
def occurrences(cal):
    obj = {"ics": cal.to_ical().decode(), "etag": ""}
    return [(o["title"], o["start"], o["rid"], o["repeat"], o["reminder"]) for o in
            c.expand_object("a|cal", "h", obj, dt.datetime(2026, 7, 1, tzinfo=utc), dt.datetime(2026, 8, 1, tzinfo=utc))]
out = {}
cal, uid = c.build_new({"title": "Gym", "allDay": False, "start": ms(2026, 7, 6, 18), "end": ms(2026, 7, 6, 19),
                        "repeat": "weekly", "reminder": 30, "location": "", "description": ""}, tz)
out["new"] = occurrences(cal)
rid = out["new"][1][2]
c.apply_occurrence(cal, {"title": "Gym (late)", "allDay": False, "start": ms(2026, 7, 13, 20), "end": ms(2026, 7, 13, 21)}, rid, tz)
c.exclude_occurrence(cal, out["new"][2][2], tz)
out["occurrence"] = occurrences(cal)
c.apply_series(cal, {"title": "Gym", "allDay": False, "start": ms(2026, 7, 6, 17), "end": ms(2026, 7, 6, 18),
                     "origStart": ms(2026, 7, 6, 18), "repeat": "weekly", "repeatChanged": False,
                     "reminder": 30, "reminderChanged": False}, tz)
out["shifted"] = occurrences(cal)
c.apply_series(cal, {"title": "Gym once", "allDay": False, "start": ms(2026, 7, 6, 17), "end": ms(2026, 7, 6, 18),
                     "origStart": ms(2026, 7, 6, 17), "repeat": "none", "repeatChanged": True,
                     "reminder": -1, "reminderChanged": True}, tz)
out["single"] = occurrences(cal)
day, _ = c.build_new({"title": "Holiday", "allDay": True, "dayStart": "2026-07-20", "dayEnd": "2026-07-22",
                      "repeat": "none", "reminder": -1}, tz)
out["allDay"] = [(o["title"], o["dayStart"], o["dayEnd"]) for o in
                 c.expand_object("a|cal", "h", {"ics": day.to_ical().decode()}, dt.datetime(2026, 7, 1), dt.datetime(2026, 8, 1))]
print(json.dumps(out))
'''
        result = subprocess.run([self.python, "-c", script, str(SCRIPTS)], env=self.env, capture_output=True,
                                text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        utc = __import__("datetime").timezone.utc
        ms = lambda *args: int(__import__("datetime").datetime(*args, tzinfo=utc).timestamp() * 1000)
        rid = lambda *args: f"T:{ms(*args) // 1000}"
        self.assertEqual([tuple(o) for o in out["new"]], [
            ("Gym", ms(2026, 7, d, 18), rid(2026, 7, d, 18), "weekly", 30) for d in (6, 13, 20, 27)])
        # The 13th moved to 20:00 under its own title, the 20th gone
        self.assertEqual([tuple(o[:3]) for o in out["occurrence"]], [
            ("Gym", ms(2026, 7, 6, 18), rid(2026, 7, 6, 18)),
            ("Gym (late)", ms(2026, 7, 13, 20), rid(2026, 7, 13, 18)),
            ("Gym", ms(2026, 7, 27, 18), rid(2026, 7, 27, 18))])
        # An hour earlier: the override and the exclusion move with the series
        self.assertEqual([tuple(o[:3]) for o in out["shifted"]], [
            ("Gym", ms(2026, 7, 6, 17), rid(2026, 7, 6, 17)),
            ("Gym (late)", ms(2026, 7, 13, 20), rid(2026, 7, 13, 17)),
            ("Gym", ms(2026, 7, 27, 17), rid(2026, 7, 27, 17))])
        # No longer repeating: one event, no reminder, overrides dropped
        self.assertEqual([tuple(o) for o in out["single"]], [("Gym once", ms(2026, 7, 6, 17), "", "none", -1)])
        self.assertEqual([tuple(o) for o in out["allDay"]], [("Holiday", "2026-07-20", "2026-07-22")])

    def test_recurrences(self):
        """The expansion's hard cases, in October 2026 (TZ UTC): checked
        against recurring-ical-events, which it replaces."""
        script = r'''
import datetime as dt, json, sys
sys.path.insert(0, sys.argv[1])
import calendar_sync as c
def ev(body): return "BEGIN:VEVENT\r\n" + body.strip().replace("\n", "\r\n") + "\r\nEND:VEVENT\r\n"
def cal(*evs): return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\n" + "".join(evs) + "END:VCALENDAR\r\n"
cases = {
    # Wall-clock time kept across Berlin's change to winter time (Oct 25)
    "dst": cal(ev("UID:a\nDTSTART;TZID=Europe/Berlin:20261020T090000\nDTEND;TZID=Europe/Berlin:20261020T100000\nRRULE:FREQ=WEEKLY")),
    # A UTC UNTIL on a zoned start, and on a floating one (read as wall time)
    "until": cal(ev("UID:a\nDTSTART;TZID=America/New_York:20261001T090000\nDURATION:PT1H\nRRULE:FREQ=DAILY;UNTIL=20261005T130000Z")),
    "floating": cal(ev("UID:a\nDTSTART:20261001T090000\nDTEND:20261001T093000\nRRULE:FREQ=DAILY;UNTIL=20261003T090000Z")),
    # A DATE UNTIL counts its whole day; all-day stays all-day
    "allDay": cal(ev("UID:a\nDTSTART;VALUE=DATE:20261001\nRRULE:FREQ=WEEKLY;UNTIL=20261015;BYDAY=TH,FR")),
    # RDATEs (one a period with its own length), the start excluded
    "rdate": cal(ev("UID:a\nDTSTART:20261002T100000Z\nDTEND:20261002T110000Z\nEXDATE:20261002T100000Z\n"
                    "RDATE:20261015T100000Z\nRDATE;VALUE=PERIOD:20261020T100000Z/20261020T140000Z")),
    # An occurrence moved out of the window, and one moved into it
    "movedOut": cal(ev("UID:a\nDTSTART:20261001T100000Z\nDTEND:20261001T110000Z\nRRULE:FREQ=DAILY;COUNT=3"),
                    ev("UID:a\nRECURRENCE-ID:20261002T100000Z\nDTSTART:20261210T100000Z\nDTEND:20261210T110000Z")),
    "movedIn": cal(ev("UID:a\nDTSTART:20260901T100000Z\nDTEND:20260901T110000Z\nRRULE:FREQ=DAILY;COUNT=10"),
                   ev("UID:a\nRECURRENCE-ID:20260905T100000Z\nDTSTART:20261012T100000Z\nDTEND:20261012T110000Z")),
    # Started before the window, still running in it
    "spanning": cal(ev("UID:a\nDTSTART:20260928T100000Z\nDTEND:20261003T100000Z\nRRULE:FREQ=WEEKLY;COUNT=2")),
}
utc = dt.timezone.utc
out = {name: sorted([o["start"], o["end"], o["rid"], o["dayStart"]] for o in c.expand_object(
    "a|cal", "h", {"ics": ics}, dt.datetime(2026, 10, 1, tzinfo=utc), dt.datetime(2026, 11, 1, tzinfo=utc)))
    for name, ics in cases.items()}
print(json.dumps(out))
'''
        result = subprocess.run([self.python, "-c", script, str(SCRIPTS)], env=self.env, capture_output=True,
                                text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        out = json.loads(result.stdout)
        utc = __import__("datetime").timezone.utc
        ms = lambda *args: int(__import__("datetime").datetime(*args, tzinfo=utc).timestamp() * 1000)
        hour = 3600 * 1000
        timed = lambda *args, length=hour: [ms(*args), ms(*args) + length, f"T:{ms(*args) // 1000}", ""]
        self.assertEqual(out["dst"], [timed(2026, 10, 20, 7), timed(2026, 10, 27, 8)])
        self.assertEqual(out["until"], [timed(2026, 10, d, 13) for d in range(1, 6)])
        self.assertEqual(out["floating"], [timed(2026, 10, d, 9, length=hour // 2) for d in range(1, 4)])
        self.assertEqual([o[3] for o in out["allDay"]],
                         ["2026-10-01", "2026-10-02", "2026-10-08", "2026-10-09", "2026-10-15"])
        self.assertEqual(out["rdate"], [timed(2026, 10, 15, 10), timed(2026, 10, 20, 10, length=4 * hour)])
        self.assertEqual(out["movedOut"], [timed(2026, 10, 1, 10), timed(2026, 10, 3, 10)])
        self.assertEqual(out["movedIn"], [[ms(2026, 10, 12, 10), ms(2026, 10, 12, 11), f"T:{ms(2026, 9, 5, 10) // 1000}", ""]])
        self.assertEqual(out["spanning"], [timed(2026, 9, 28, 10, length=120 * hour), timed(2026, 10, 5, 10, length=120 * hour)])

    def test_failures_are_json(self):
        self.assertEqual(self.run_helper("discover", {"kind": "caldav", "url": "https://example.invalid"})["code"],
                         "noPassword")
        unreachable = self.run_helper("discover", {"kind": "ics", "url": "http://127.0.0.1:9/feed.ics"})
        self.assertEqual(unreachable["code"], "network")
        self.assertEqual(self.run_helper("save", {"stateDir": str(self.tmp), "range": {"from": 0, "to": 1},
                                                  "accounts": [], "account": "nope", "calendar": "x",
                                                  "event": {}})["code"], "notFound")


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


class CursorTheme(unittest.TestCase):
    """cursor_theme.py on scratch icon folders (never --gsettings)."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.home, self.data, self.system = self.tmp / "home", self.tmp / "data", self.tmp / "system"
        self.home.mkdir()

    def theme(self, name, cursors, inherits=None):
        folder = self.system / "icons" / name
        (folder / "cursors").mkdir(parents=True)
        for cursor in cursors:
            (folder / "cursors" / cursor).write_text(cursor)
        if inherits:
            (folder / "index.theme").write_text(f"[Icon Theme]\nInherits={inherits}\n")

    def run_script(self, theme):
        env = {**os.environ, "HOME": str(self.home), "XDG_DATA_HOME": str(self.data), "XDG_DATA_DIRS": str(self.system)}
        done = subprocess.run([sys.executable, str(SCRIPTS / "cursor_theme.py"), theme], env=env,
                              capture_output=True, text=True, timeout=30)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    def test_fills_missing_names(self):
        self.theme("Old", ["left_ptr", "hand2", "xterm", "text"])
        self.assertEqual(self.run_script("Old"), {"theme": "axiom-cursor-Old", "filled": 2})
        made = self.data / "icons" / "axiom-cursor-Old"
        self.assertIn("Inherits=Old", (made / "index.theme").read_text())
        self.assertEqual(os.readlink(made / "cursors" / "default"), str(self.system / "icons/Old/cursors/left_ptr"))
        self.assertEqual(os.readlink(made / "cursors" / "pointer"), str(self.system / "icons/Old/cursors/hand2"))
        # The theme has `text` itself: not linked
        self.assertFalse((made / "cursors" / "text").exists())
        # As wanted already: not rewritten
        inode = (made / "index.theme").stat().st_ino
        self.run_script("Old")
        self.assertEqual((made / "index.theme").stat().st_ino, inode)

    def test_inherited_names_count(self):
        self.theme("Base", ["default", "pointer"])
        self.theme("Child", ["left_ptr", "hand2"], inherits="Base")
        self.assertEqual(self.run_script("Child"), {"theme": "Child", "filled": 0})

    def test_complete_theme_removes_the_companion(self):
        self.theme("Old", ["left_ptr"])
        self.theme("New", ["default", "left_ptr"])
        self.run_script("Old")
        self.assertEqual(self.run_script("New"), {"theme": "New", "filled": 0})
        self.assertFalse((self.data / "icons" / "axiom-cursor-Old").exists())
        # A theme with no XCursor cursors (hyprcursor only) keeps its name
        self.assertEqual(self.run_script("Missing"), {"theme": "Missing", "filled": 0})

    def test_each_theme_its_own_name(self):
        # One name for both would leave readers on the cursors they loaded
        self.theme("Old", ["left_ptr"])
        self.theme("Other Theme", ["arrow"])
        self.run_script("Old")
        self.assertEqual(self.run_script("Other Theme"), {"theme": "axiom-cursor-Other_Theme", "filled": 1})
        self.assertFalse((self.data / "icons" / "axiom-cursor-Old").exists())

    def test_leaves_a_folder_not_its_own(self):
        self.theme("Old", ["left_ptr"])
        (self.data / "icons" / "axiom-cursor-Old").mkdir(parents=True)
        env = {**os.environ, "HOME": str(self.home), "XDG_DATA_HOME": str(self.data), "XDG_DATA_DIRS": str(self.system)}
        done = subprocess.run([sys.executable, str(SCRIPTS / "cursor_theme.py"), "Old"], env=env, capture_output=True, text=True)
        self.assertEqual(done.returncode, 1)


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
