#!/usr/bin/env python3
"""PreToolUse guard: refuses the tool calls CLAUDE.md › "Never"
forbids, so they're enforced rather than only written down.

Claude Code runs it before every Bash, Edit and Write call (.claude/settings.json
› hooks) with the call as JSON on stdin; a refusal is printed as a `deny`
decision with the rule it breaks. Every rule lives here (settings.json holds
only the allow list). Tests: tests/scripts/test_guard.py.

A Bash command is judged by its name and leading subcommand words, never by
argument substrings: BASH_RULES is the one table of refusals (`Rule`: command,
words, why, opt, when, section); a command with --help or -h skips it. File
paths go through PROTECTED_PATHS (Bash writes and removals, Edit and Write).
Known gaps: writes from inside an interpreter (`python3 -c`, `node -e`);
`git switch main && git push`; a heredoc written to a file and run later;
`hyprctl --batch`; a pipeline continued after a heredoc body (`cat <<EOF |` …
`sh`); quotes nested in `"$(…)"` hiding a command behind a comment; chmod,
chown, truncate and `find -delete` on protected paths; a `cd` inside a subshell
moving later commands; rules see leading words only (`systemctl restart a greetd`);
a bare push under `push.default=upstream` on a branch tracking main; the dev config
(`~/.config/axiom/dev/config.json`), which the live shell runs in dev mode, is not protected.
"""
import json
import os
import re
import shlex
import subprocess
import sys
from collections import namedtuple
from fnmatch import fnmatchcase
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
HOME = Path(os.path.expanduser("~")).resolve()
# The live config.json (DataDirs.xdg)
LIVE_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config").resolve() / "axiom/config.json"
PUNCTUATION = ";&|()<>`"
# Words that start a command without being its name
KEYWORDS = {"if", "then", "else", "elif", "while", "until", "do", "!", "{", "}"}
# Wrappers and their options that take a value (`sudo -u me`); timeout and
# flock take one positional (the duration, the lock file) before the command
WRAPPERS = {
    "sudo": {"-u", "-g", "-C", "-D", "--chdir", "-h", "-p", "-r", "-t", "-U", "-T"}, "pkexec": {"--user"},
    "env": {"-u", "-C", "--unset", "--chdir"}, "nohup": set(), "exec": {"-a"}, "command": set(), "time": set(),
    "setsid": set(), "timeout": {"-s", "-k", "--signal", "--kill-after"}, "nice": {"-n", "--adjustment"},
    "ionice": {"-c", "-n", "-p", "--class", "--classdata"}, "flock": {"-w", "-E", "--timeout", "--conflict-exit-code"},
    "systemd-run": {"-u", "--unit", "-p", "--property", "-E", "--setenv", "--uid", "--gid", "--slice", "-M", "--machine",
                    "--description", "--working-directory"},
    "xargs": {"-a", "--arg-file", "-d", "--delimiter", "-E", "-I", "-L", "-n", "--max-args", "-P", "--max-procs", "-s",
              "--max-chars", "--process-slot-var"},
}
WRAPPER_POSITIONALS = {"timeout": 1, "flock": 1}
# A substitution a double-quoted word still runs: "$(…)", "`…`"; single-quoted
# text (a commit message, a grep pattern) runs nothing, so it's blanked first
SUBSTITUTION = re.compile(r"\$\((.*)\)|`([^`]*)`", re.S)
QUOTED = re.compile(r"""\\.|"(?:\\.|[^"\\])*"|\$'(?:\\.|[^'\\])*'|'[^']*'""", re.S)
SHELLS = {"bash", "sh", "zsh"}
# Programs judged by the script they run (`bash x.sh`, `python3 -u x.py`)
INTERPRETERS = re.compile(r"bash|sh|zsh|python[0-9.]*")
QS = {"qs", "quickshell"}
# What pkill, killall and kill-by-lookup must not stop: the shell and its daemon
SHELL_PROCESSES = QS | {"axiom"}
LOOKUPS = {"pkill", "killall", "pgrep", "pidof"}
HELP_OPTS = {"--help", "-h"}
# Options that take the next token as their value, by command (so it isn't a word)
VALUE_OPTS = {
    "axiom": {"--socket", "-socket", "--config-dir", "-config-dir", "--tree", "-tree", "--qs", "-qs", "-o", "--kind", "-kind", "--dir", "-dir"},
    "git": {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "-o", "--push-option", "--repo", "--receive-pack", "--exec"},
    **dict.fromkeys(QS, {"-c", "--config", "-p", "--path", "-m", "--manifest", "-i", "--id", "--pid", "--log-rules", "-n", "--newest"}),
    "hyprctl": {"-i", "--instance"}, "swaymsg": {"-s", "--socket", "-t", "--type"}, "bluetoothctl": {"-t", "--timeout", "-a", "--agent"},
    "rfkill": {"-o", "--output"}, "gh": {"-R", "--repo"},
    "systemctl": {"-H", "--host", "-M", "--machine", "-p", "--property", "-t", "--type", "-s", "--signal"},
    **dict.fromkeys(("timedatectl", "hostnamectl", "loginctl"), {"-H", "--host", "-M", "--machine"}),
}


def command_words(name, args):
    """The non-option args in order: `--` ends the options (the rest are words),
    and an option in VALUE_OPTS[name] takes the next token."""
    words, i = [], 0
    while i < len(args):
        if args[i] == "--":
            return words + args[i + 1:]
        if args[i].startswith("-"):
            i += 2 if args[i] in VALUE_OPTS.get(name, ()) else 1
        else:
            words.append(args[i])
            i += 1
    return words


def command_options(args):
    """The tokens starting with `-` before any `--`."""
    return [a for a in args[:args.index("--") if "--" in args else len(args)] if a.startswith("-")]


def names_shell(args):
    """Whether a pkill/killall/pgrep/pidof names a shell process: a word whose
    `|` alternatives include one (`^`/`$` stripped), or with -f/--full a
    pattern's `|` alternatives and words."""
    full = any(a == "--full" or re.fullmatch(r"-[a-zA-Z]*f[a-zA-Z]*", a) for a in command_options(args))
    split = r"[|\s/]+" if full else r"\|"
    return any(w.strip("^$") in SHELL_PROCESSES for p in command_words("pgrep", args) for w in re.split(split, p))


class Denied(Exception):
    pass


def deny(section, why):
    raise Denied(f"Blocked by CLAUDE.md › {section}: {why}")


# --------------------------------------------------------------- parsing

# A quoted string or escape (kept), or a `#` comment (dropped): one starts a
# word and ends at its newline, so `a#b`, `"#x"` and `${#var}` aren't comments
COMMENT = re.compile(QUOTED.pattern + r"|(?<![^\s;&|()<>])#[^\n]*", re.S)


def uncomment(m):
    text = m[0]
    if text[0] == "#":
        return ""
    if text[:2] == "$'":  # an ANSI-C string, which shlex can't read: as a plain one
        return "'" + text[2:-1].replace("'", "") + "'"
    return text


def lex(command):
    command = COMMENT.sub(uncomment, command).replace("\n", " ; ")
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=PUNCTUATION)
        lexer.whitespace_split = True
        lexer.commenters = ""
        return list(lexer)
    except ValueError:  # an unbalanced quote: split on separators still, quotes dropped
        return re.findall(r"[;&|()<>`]+|[^\s;&|()<>`]+", re.sub(r"['\"]", "", command))


# `<<WORD`, `<<-WORD`, `<<'WORD'` (not a `<<<` here-string, nor a `<<` inside
# a quoted string or a comment, which COMMENT's branches consume)
HEREDOC = re.compile(r"""(?<!<)<<(?!<)(-?)[ \t]*(['"]?)([A-Za-z_][\w.-]*)\2(?![^\s;&|<>()])|""" + COMMENT.pattern)


def drop_heredoc_bodies(command):
    """A heredoc's body is text, not commands: it is dropped, unless the line
    holding its `<<WORD` runs a shell, `source`, `.` or `eval` (the body is then
    judged as commands) or its delimiter never comes (judged as written); an
    unquoted body's `$(…)`/backticks run, so they are judged. Line continuations
    are joined first, outside quotes and comments (a comment ends at its newline)."""
    command = COMMENT.sub(lambda m: "" if m[0] == "\\\n" else m[0], command)
    lines, out = command.split("\n"), []
    while lines:
        line = lines.pop(0)
        out.append(line)
        for m in HEREDOC.finditer(line):
            dash, quote, word = m.groups()
            end = next((i for i, body in enumerate(lines) if (body.lstrip("\t") if dash else body) == word), None) if word else None
            if end is None:
                continue
            body, lines = lines[:end], lines[end:]
            if any(Path(argv[0]).name in SHELLS | {"source", ".", "eval"} for _, argv in split_commands(line)):
                out.extend(body)
            elif not quote:
                out.extend(s[1] or s[2] for s in SUBSTITUTION.finditer("\n".join(body)))
    return "\n".join(out)


def split_commands(command):
    """[(env, argv)] for each simple command in a shell command line; a
    redirection `> f` is a command of its own, `[">", f]`."""
    command = drop_heredoc_bodies(command)
    tokens = lex(command)
    out, current, exported = [], [], {}
    for token in lex(QUOTED.sub(lambda m: "''" if m[0].startswith(("'", "$'")) else m[0], command)):
        for m in SUBSTITUTION.finditer(token):
            out.extend(split_commands(m[1] or m[2]))
    i = 0
    while i < len(tokens):
        token = tokens[i]
        punctuation = set(token) <= set(PUNCTUATION)
        if punctuation and set(token) & set("<>") and not set(token) & set("()`"):
            # A redirection: `>`/`>>` write their target, `<` reads it
            if current and current[-1].isdigit():
                current.pop()  # the fd of `2>`
            if i + 1 < len(tokens) and "(" in tokens[i + 1] and set(tokens[i + 1]) <= set(PUNCTUATION):
                i += 1  # `< <(cmd)`: the process substitution is a command, not the target
                continue
            if ">" in token and i + 1 < len(tokens):
                out.append((dict(exported), [">", tokens[i + 1]]))
            if token == "<<<" and i + 1 < len(tokens):
                out.extend(split_commands(tokens[i + 1]))  # a here-string may be fed to a shell
            i += 2
            continue
        if punctuation or not current and token in KEYWORDS:
            if current:
                out.extend(simple(current, exported))
            current = []
        else:
            current.append(token)
        i += 1
    if current:
        out.extend(simple(current, exported))
    return out


ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)


def simple(tokens, exported):
    env = dict(exported)
    i = 0
    while i < len(tokens) and ASSIGN.match(tokens[i]):
        env.update([ASSIGN.match(tokens[i]).groups()])
        i += 1
    argv = tokens[i:]
    if not argv:
        exported.update(env)
        return []
    if argv[0] == "export":
        exported.update(ASSIGN.match(t).groups() for t in argv[1:] if ASSIGN.match(t))
        return []
    # Wrappers: judge the command they run
    while argv and Path(argv[0]).name in WRAPPERS:
        wrapper = Path(argv[0]).name
        argv = argv[1:]
        while argv and (argv[0].startswith("-") or ASSIGN.match(argv[0])):
            if ASSIGN.match(argv[0]):
                env.update([ASSIGN.match(argv[0]).groups()])
            argv = argv[2:] if argv[0] in WRAPPERS[wrapper] else argv[1:]
        argv = argv[WRAPPER_POSITIONALS.get(wrapper, 0):]
        if wrapper == "flock" and argv[:1] in (["-c"], ["--command"]):
            argv = ["sh", "-c", *argv[1:]]  # flock <file> -c <command>
    if not argv:
        return []
    command_flag = next((i for i, a in enumerate(argv[1:-1], 1) if re.fullmatch(r"-[a-z]*c[a-z]*", a)), None)
    if Path(argv[0]).name in SHELLS and command_flag is not None:
        inner = argv[command_flag + 1]
        return [(dict(env, **e), a) for e, a in split_commands(inner)]
    # A script run through an interpreter (`bash data/greeter/greeter_install.sh …`): judge the script
    if INTERPRETERS.fullmatch(Path(argv[0]).name):
        rest = argv[1:]
        while rest and rest[0].startswith("-"):
            rest = rest[1:]
        if rest:
            return [(env, rest)]
    return [(env, argv)]


def resolve(path, cwd, env=None):
    path = os.path.expanduser(expand_vars(path, env or {}))
    return (Path(cwd) / path).resolve() if not os.path.isabs(path) else Path(path).resolve()


def expand_vars(value, env):
    """$VAR / ${VAR} from the command's environment, then this process's."""
    return re.sub(r"\$(?:\{(\w+)\}|(\w+))", lambda m: env.get(m[1] or m[2], os.environ.get(m[1] or m[2], m[0])), value)


# The live config folders: ~/.config and XDG_CONFIG_HOME
CONFIG_HOMES = {HOME / ".config", LIVE_CONFIG.parent.parent}


def path_forms(path, cwd, env):
    """A path as written (`..` folded) and with its links followed."""
    expanded = os.path.expanduser(expand_vars(path, env))
    return {Path(os.path.normpath(os.path.join(cwd, expanded))), resolve(path, cwd, env)}


def live_config_path(path, cwd, env):
    """Whether `path` is a live config folder or inside one (or HOME itself),
    as written and with its links followed; a scratch dir inside the repo isn't."""
    for target in path_forms(path, cwd, env):
        if target == REPO or REPO in target.parents:
            continue
        if target == HOME or any(target == home or home in target.parents for home in CONFIG_HOMES):
            return True
    return False


def scratch(value):
    """Whether an env value (HOME, XDG_CONFIG_HOME, …) points away from the live system."""
    if not value:
        return False
    if "$" in value:
        return True  # a variable the agent made (mktemp): trust it
    real = resolve(value, "/")
    return real != HOME and real != HOME / ".config" and real != Path("/")


# What `axiom` runs against: the live display's daemon unless the command
# names a scratch socket or runtime dir
LIVE_RUNTIME = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")


def axiom_flag(args, flag):
    """An option's value, `--x v` or `--x=v`; Go's flag package also takes `-x`."""
    for i, a in enumerate(args):
        if a.split("=", 1)[0] in (flag, flag[1:]):
            if "=" in a:
                return a.split("=", 1)[1]
            if i + 1 < len(args):
                return args[i + 1]
    return ""


def display_name(value):
    """A $WAYLAND_DISPLAY's runtime folder name (xdg.DisplayName): its base name."""
    return os.path.basename(value.strip().rstrip("/"))


# The live session's display: its daemon's socket is LIVE_RUNTIME/axiom/<it>/axiom.sock
LIVE_DISPLAY = display_name(os.environ.get("WAYLAND_DISPLAY", ""))


def live_socket(socket, env):
    """Whether a daemon socket is the live one: anything in the live runtime
    dir but another display's socket (a nested session's daemon). Without a
    known live display, all of it."""
    path = resolve(socket, "/", env)
    if not path.is_relative_to(Path(LIVE_RUNTIME)):
        return False
    parts = path.relative_to(Path(LIVE_RUNTIME)).parts
    other = len(parts) == 3 and parts[0] == "axiom" and parts[2] == "axiom.sock" and parts[1] != LIVE_DISPLAY
    return not (LIVE_DISPLAY and other)


def axiom_run_live(env, args, rest, cwd):
    """Whether the command's runtime dir and display are the live session's
    (`axiom run`, and `axiom_live_display` without a socket); a value still
    holding `$` is a variable the agent made."""
    runtime, display = (expand_vars(env.get(var, ""), {}) for var in ("XDG_RUNTIME_DIR", "WAYLAND_DISPLAY"))
    if runtime and ("$" in runtime or resolve(runtime, "/") != Path(LIVE_RUNTIME)):
        return False
    return not (display and ("$" in display or LIVE_DISPLAY and display_name(display) != LIVE_DISPLAY))


def axiom_live_display(env, args, rest, cwd):
    """Whether an axiom command reaches the live session's daemon: the CLI's
    order (cli/client.go socketPath) is --socket, $AXIOM_SOCKET (maybe
    inherited), then $XDG_RUNTIME_DIR/axiom/$WAYLAND_DISPLAY."""
    socket = axiom_flag(args, "--socket") or env.get("AXIOM_SOCKET", os.environ.get("AXIOM_SOCKET", ""))
    if not socket:
        return axiom_run_live(env, args, rest, cwd)
    socket = expand_vars(socket, env)
    if "$" in socket:
        return False  # a variable the agent made
    inherited = os.environ.get("AXIOM_SOCKET", "")
    return bool(inherited) and resolve(socket, "/") == resolve(inherited, "/") or live_socket(socket, env)


def live_compositor(variable, instance_opts):
    """A `when`: the command reaches the live compositor, unless an arg names
    another instance (`hyprctl -i`) or its `variable` differs from the session's."""
    return lambda env, args, rest, cwd: not (any(a.split("=")[0] in instance_opts for a in args)
                                             or env.get(variable, os.environ.get(variable, "")) != os.environ.get(variable, ""))


def greeter_unsafe(env, args, rest, cwd):
    gdir = axiom_flag(args, "--dir") or env.get("AXIOM_GREETER_DIR", "")
    installed = gdir and "$" not in gdir and resolve(gdir, "/") == Path("/var/lib/axiom-greeter")
    shown = env.get("AXIOM_GREETER_WINDOWED") == "1" or "--no-shell" in args
    return not shown or not scratch(gdir) or installed


# ----------------------------------------------------------------- rules

# One refusal: `command` is `|`-separated basenames or `*`; `words` are space-separated
# patterns for the command's leading words (`|`-separated globs, `!` = absent or none of
# them); `opt` a regex some option must fullmatch; `when(env, args, rest, cwd)` an extra
# condition (`rest` = the words after the matched ones); `why` follows "Blocked by CLAUDE.md › <section>: "
Rule = namedtuple("Rule", "command words why opt when section", defaults=(None, None, "Never"))
BASH_RULES = [
    # Lock the built-in locker
    Rule("loginctl", "lock-session*", "don't lock the session; only the user can type the password. Test LockSurface in a hidden window."),
    Rule("hyprlock", "", "don't lock the screen; only the user can type the password."),
    # Simulate cursor movement
    *(Rule(c, w, "don't simulate cursor movement; check logs and reason through bindings, or ask the user to look.")
      for c, w in (("ydotool|dotool|dotoolc|wlrctl", ""), ("*", "dispatch|eval movecursor*|*cursor.move*"))),
    # Ending the Hyprland, sway or niri session itself: only a nested one may be told to
    *(Rule(c, w, "hyprctl dispatch exit / hyprshutdown / swaymsg exit only on a nested compositor (its HYPRLAND_INSTANCE_SIGNATURE or SWAYSOCK, `hyprctl -i`, `swaymsg -s`), never the live session.",
           when=live_compositor(v, o))
      for c, w, v, o in (("*", "dispatch|eval exit|*dsp.exit*", "HYPRLAND_INSTANCE_SIGNATURE", {"-i", "--instance"}),
                         ("hyprshutdown", "", "HYPRLAND_INSTANCE_SIGNATURE", {"-i", "--instance"}),
                         ("swaymsg", "exit", "SWAYSOCK", {"-s", "--socket"}))),
    *(Rule("niri", w, "niri msg output / action quit / load-config-file only on a nested niri (NIRI_SOCKET=<its socket>), never the live session.",
           when=live_compositor("NIRI_SOCKET", set())) for w in ("msg output", "msg action quit|load-config-file")),
    # The shell itself, and its daemon
    Rule("qs|quickshell", "kill", "the shell runs detached; never stop it from this session (`qs kill` only the greeter instance you started: `qs kill -p <…>/greeter.qml` or `-i <id>`).", when=lambda env, args, rest, cwd: not any(a in {"-i", "--id", "--pid"} or a.endswith("greeter.qml") for a in args)),
    Rule("qs|quickshell", "", "the shell runs detached; never start another from this session (the windowed greeter: AXIOM_GREETER_WINDOWED=1 AXIOM_COMPOSITOR=none axiom greeter --dir <scratch>).", when=lambda env, args, rest, cwd: not rest and not (env.get("AXIOM_GREETER") == "1" and any(a.endswith("greeter.qml") for a in args))),
    Rule("pkill|killall", "", "don't stop qs or the daemon by name; `qs kill -i <id>` for a nested shell, `axiom --socket <scratch> quit` for a scratch daemon.",
         when=lambda env, args, rest, cwd: names_shell(args)),
    Rule("axiom", "run", "`axiom run` starts a shell on the live display; start a scratch one with XDG_RUNTIME_DIR=<scratch> axiom run --no-shell, or use scripts/dev/nested.sh.", when=axiom_run_live),
    Rule("axiom", "quit|restart", "`axiom quit/restart` starts or stops the live shell; never from this session (reach a scratch daemon with --socket <its socket>, or use nested.sh).", when=axiom_live_display),
    Rule("axiom", "daemon stop|restart|reexec", "`axiom daemon stop/restart/reexec` stops or replaces the live daemon; never from this session.", when=axiom_live_display),
    *(Rule("axiom", w, "`axiom dev on/off/rebuild/set/options` and `dev config copy/pull` change the live daemon's dev mode or config; ask the user, or drive a nested daemon (--socket $XDG_RUNTIME_DIR/axiom/<nested display>/axiom.sock). `axiom dev status` and `dev config diff` read it.",
           when=axiom_live_display) for w in ("dev on|off|rebuild|set|options", "dev config copy|pull")),
    *(Rule("axiom", w, "don't lock the session; only the user can type the password (lock a scratch daemon: --socket <its socket>).", when=axiom_live_display)
      for w in ("lock", "ipc lockscreen")),
    *(Rule("axiom", w, "`monitors keep` / `selfUpdate update` change the live system; ask the user.", when=axiom_live_display)
      for w in ("ipc monitors keep", "ipc selfUpdate update")),
    Rule("axiom", "greeter", "run the greeter only windowed on a scratch folder: AXIOM_GREETER_WINDOWED=1 AXIOM_COMPOSITOR=none axiom greeter --dir <scratch> (or --no-shell).", when=greeter_unsafe),
    *(Rule(c, w, "`axiom greeter-install` / `greeter_install.sh` install/update/uninstall only with a scratch AXIOM_GREETER_ROOT=<dir>.",
           when=lambda env, args, rest, cwd: not scratch(env.get("AXIOM_GREETER_ROOT", "")))
      for c, w in (("axiom", "greeter-install install|update|uninstall"), ("greeter_install.sh", "install|update|uninstall"))),
    # A compositor claim (managed mode) on the live config, or moving binds out of its files
    *(Rule("axiom", w, "`axiom compositor claim/release` and `compositor binds remove` only on a scratch dir, never the live compositor config.",
           when=lambda env, args, rest, cwd: rest and live_config_path(rest[0], cwd, env))
      for w in ("compositor claim|release", "compositor binds remove")),
    Rule("axiom", "config", "`--takeover` changes a setting that takes something over on this PC (compositor mode, locker, idle, polkit, greeter); ask the user.", opt="--takeover", when=lambda env, args, rest, cwd: not scratch(axiom_flag(args, "--config-dir") or env.get("XDG_CONFIG_HOME", "")) or axiom_live_display(env, args, rest, cwd)),
    # git clean -x, and git stash, which every worktree of the repo shares
    Rule("git", "clean", "`git clean -x`/`-X` deletes the generated files and local state; remove the files you mean by name (`git clean -fd` is fine).", opt="-[a-zA-Z]*[xX][a-zA-Z]*"),
    Rule("git", "stash !list|show", "`git stash` is shared by every worktree of the repo; commit, or `git diff > <scratch>/x.patch`."),
    # The translations are filled and pruned by the pre-commit hook
    Rule("check_i18n.py", "", "translations are filled and pruned by the pre-commit hook; run check_i18n.py without --fill/--prune.", opt="--fill|--prune"),
    # Greetd, and the screen-share portal: restarting either ends what is running
    *(Rule(c, w, "don't restart or stop greetd: it ends the session.") for c, w in (
        ("systemctl", "restart|stop|start|reload|kill|disable|enable|mask|try-restart|reload-or-restart greetd*"),
        ("service", "greetd* restart|stop|start|reload"), ("pkill|killall", "greetd*"))),
    *(Rule(c, w, "don't restart or stop the live xdg-desktop-portal (or its backends): it ends the shares running; ask the user (the Screen sharing card's Restart does it on a click).") for c, w in (
        ("systemctl", "restart|stop|kill|reload|try-restart|reload-or-restart|mask|disable xdg-desktop-portal*"),
        ("service", "xdg-desktop-portal* restart|stop|reload"), ("pkill|killall", "xdg-desktop-portal*"))),
    # The machine's own settings: clock, time zone, hostname, the user's account and default apps; Bluetooth devices
    Rule("timedatectl", "set-*", "don't change the machine's clock or time zone."),
    *(Rule("hostnamectl", w, "don't rename the machine or change its hostname1 settings.") for w in ("set-*", "hostname *")),
    Rule("passwd|chpasswd|chfn|usermod|chsh", "", "`passwd`/`chpasswd`/`chfn`/`usermod`/`chsh` change the user's account; only the user changes their password or account."),
    *(Rule(c, w, "`xdg-mime default`/`xdg-settings set` change the user's default apps; only with a scratch XDG_CONFIG_HOME=<dir>.",
           when=lambda env, args, rest, cwd: not scratch(env.get("XDG_CONFIG_HOME", ""))) for c, w in (("xdg-mime", "default"), ("xdg-settings", "set"))),
    *(Rule("bluetoothctl", w, "don't remove, block, disconnect or pair a real Bluetooth device or power the adapter off.") for w in ("remove|block|disconnect|pair", "power off")),
    Rule("rfkill", "block|toggle", "don't rfkill-block the live radios: a Bluetooth mouse or keyboard could drop out."),
    # Another claude loads the settings of the folder it starts in: without this guard
    *(Rule(c, w, "don't start another `claude` from Bash: it runs without this guard; ask the user (or use a subagent, which runs this session's).")
      for c, w in (("claude", ""), ("npx|bunx", "@anthropic-ai/claude-code*"))),
    # qmlformat -i replaces the inode
    Rule("qmlformat", "", "qmlformat -i replaces the file's inode, so qs stops reloading it; verify.sh formats in place.", opt="-i|--inplace", section="Formatting and layout"),
    # Every change reaches main through a PR the maintainer merges
    Rule("gh", "pr merge", "don't merge a PR: the maintainer merges; report it ready and stop."),
]


def word_matches(pattern, word):
    """One `words` pattern against one command word (None = missing)."""
    hit = word is not None and any(fnmatchcase(word, glob) for glob in pattern.lstrip("!").split("|"))
    return hit != pattern.startswith("!")


def check_rules(env, name, args, cwd):
    """Denies with the first BASH_RULES row the command matches."""
    words, options = command_words(name, args), command_options(args)
    for r in BASH_RULES:
        patterns = r.words.split()
        if (r.command != "*" and name not in r.command.split("|")
                or not all(word_matches(p, words[i] if i < len(words) else None) for i, p in enumerate(patterns))
                or r.opt and not any(re.fullmatch(r.opt, o) for o in options)):
            continue
        if r.when is None or r.when(env, args, words[len(patterns):], cwd):
            deny(r.section, r.why)


def current_branch(cwd):
    """The branch checked out in cwd ("" when detached or unknown)."""
    try:
        out = subprocess.run(["git", "-C", cwd, "symbolic-ref", "--short", "-q", "HEAD"], capture_output=True, text=True, timeout=2)
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout.strip()


def push_refused(args, cwd):
    """A force (--force, -f, a `+refspec`; --force-with-lease is fine), --all/--branches/--mirror,
    or a push whose destination is main: the one named, or the checked-out
    branch of cwd when none is (a bare `git push`, `HEAD`)."""
    options, positional = command_options(args), command_words("git", args)
    if any(a == "--force" or a.startswith("--force=") or re.fullmatch(r"-[a-zA-Z]*f[a-zA-Z]*", a) for a in options):
        return True
    if any(a in {"--all", "--branches", "--mirror"} for a in options) or any(a.startswith("+") for a in positional):
        return True
    # git completes `heads/main` to refs/heads/main
    dests = [a.split(":")[-1].removeprefix("refs/").removeprefix("heads/") for a in positional]
    if len(dests) < 2:
        if "--tags" in options:
            return False
        dests = [current_branch(cwd)]
    else:
        dests = [current_branch(cwd) if d == "HEAD" else d for d in dests[1:]]
    return any(d in {"main", "master"} for d in dests)


def check_argv(env, argv, cwd):
    """One command: its rules, a push, then the paths it writes or removes."""
    name, args = Path(argv[0]).name, argv[1:]
    if not HELP_OPTS & set(command_options(args)):
        check_rules(env, name, args, cwd)
        if name == "git":
            cwd = str(resolve(axiom_flag(args, "-C"), cwd)) if axiom_flag(args, "-C") else cwd
            if command_words("git", args)[:1] == ["push"] and push_refused(args[args.index("push") + 1:], cwd):
                deny("Never", "no force-push and no push to main: everything reaches main through a PR.")
    written, removed = touched_paths(name, args, cwd, env)
    for kind, paths in (("write", written), ("remove", removed)):
        for path in paths:
            check_path(path, kind, cwd, env)


# The default-apps files and the screen-share portal configs (under a live XDG_CONFIG_HOME)
DEFAULT_APPS = re.compile(r"(.*-)?(mimeapps|xdg-terminals)\.list")
PORTAL_CONFIG = re.compile(r"hypr/xdph\.conf|xdg-desktop-portal-wlr/.*|xdg-desktop-portal/.*portals\.conf")


REMOVES = {"rm", "unlink", "trash", "trash-put", "shred"}


def touched_paths(name, args, cwd, env):
    """(written, removed): the paths a command writes (cp / mv / install / ln / rsync's
    destination, dd's of=, a file copied into a folder as its own path there, the files
    of > / tee / sed -i / perl -i) and the ones it deletes or moves away (rm and the
    like, mv's sources)."""
    paths = command_words(name, args)
    if name == "dd":
        return [a[3:] for a in args if a.startswith("of=")], []
    if name in {"cp", "mv", "install", "ln", "rsync"} and len(paths) > 1:
        *sources, dest = paths
        into = dest.endswith("/") or resolve(dest, cwd, env).is_dir()
        return [os.path.join(dest, Path(p).name) for p in sources] if into else [dest], sources if name == "mv" else []
    if name in REMOVES:
        return [], paths
    if name in {">", "tee"} or name in {"sed", "perl"} and any(a.startswith("--in-place") or re.fullmatch(r"-[a-zA-Z]*i\S*", a) for a in command_options(args)):
        return paths, []
    return [], []


def claude_guarded():
    """What switches this guard off: the user's Claude settings
    ($CLAUDE_CONFIG_DIR's and ~/.claude's settings.json, settings.local.json)."""
    homes = {Path(os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")), HOME / ".claude"}
    return {form for home in homes for name in ("settings.json", "settings.local.json")
            for form in path_forms(str(home / name), "/", {})}


# ------------------------------------------------------- protected paths

# Files generated from a source (edit the source), as `fnmatchcase` globs (`*` crosses `/`)
# on the path relative to the root of the repo holding the file, and frozen ones (never edit)
GENERATED = {
    "qml/config/json/config.schema.json": "it's built from qml/config/schema/ (edit the YAML there; scripts/generate.sh rebuilds it)",
    "qml/config/themes/template/theme.json": "it's built by scripts/gen_theme_template.py (the pre-commit hook rebuilds it)",
    "qml/config/i18n/template/language.json": "it's kept by scripts/check_i18n.py (the pre-commit hook rebuilds it)",
    "qml/components/surfaces/wallpaper/shaders/stamps.txt": "it's written by scripts/check_shaders.py --build",
    "qml/components/surfaces/wallpaper/shaders/*.frag.qsb": "built from the .frag beside it (scripts/check_shaders.py --build)",
    "backend/internal/assets/data/*": "the binary's embedded copies (go generate writes them from the repo files)",
    "tests/fixtures/shared/*": "the shared fixtures, recorded from SchemaValidation.qml (scripts/dev/fixtures.py record)",
    "backend/internal/migrate/legacy/testdata/*": "the format-1 migration's frozen cases, recorded from the shell before its copy was removed",
    "docs/dev/generated/*": "the reference docs (scripts/gen_docs.py writes them; scripts/generate.sh rebuilds them)",
    "docs/dev/config/*": "the config reference (scripts/gen_docs.py writes it; scripts/generate.sh rebuilds it)",
}
FROZEN = {
    "backend/internal/migrate/legacy/legacy.js": "the format-1 migrations are frozen (docs/recipes/migration.md)",
    "backend/internal/migrate/legacy/schema-v75.json": "the format-1 schema is frozen with its migrations (docs/recipes/migration.md)",
}


def repo_root(path):
    """The nearest folder upward holding `.git` (a folder, or the file of a
    worktree); REPO when there is none."""
    return next((p for p in [path, *path.parents] if (p / ".git").exists()), REPO)


def check_generated_path(p):
    root = repo_root(p)
    if not p.is_relative_to(root):
        return
    rel = p.relative_to(root).as_posix()
    for glob, why in GENERATED.items():
        if fnmatchcase(rel, glob):
            deny("Never", f"`{rel}` is generated: {why}.")
    if rel in FROZEN:
        deny("Config", f"`{rel}` is frozen: {FROZEN[rel]}.")


# (kinds a path is touched by, test(p, kind), section, why): Bash writes and removals, Edit and Write ("edit")
PROTECTED_PATHS = [
    ({"write", "remove", "edit"}, lambda p, kind: any(p == g or kind == "remove" and p in g.parents for g in claude_guarded()),
     "Never", "don't edit the user's Claude settings (settings.json, settings.local.json): ask the user."),
    ({"write", "edit"}, lambda p, kind: p == LIVE_CONFIG,
     "Never", f"don't write the real config.json ({LIVE_CONFIG}) by hand: Bash, Edit and Write skip the daemon's x-takeover check; use `axiom config set <path> <value>`."),
    ({"remove"}, lambda p, kind: p in {LIVE_CONFIG, *LIVE_CONFIG.parents},
     "Never", f"don't delete or move the real config.json ({LIVE_CONFIG}) or a folder holding it; use `axiom ipc onboarding goTo <n>`."),
    ({"write", "remove", "edit"}, lambda p, kind: DEFAULT_APPS.fullmatch(p.name) and live_config_path(str(p.parent), "/", {}),
     "Never", "don't write the user's mimeapps.list / xdg-terminals.list; test default apps with a scratch XDG_CONFIG_HOME=<dir>."),
    ({"write", "remove", "edit"}, lambda p, kind: PORTAL_CONFIG.fullmatch(f"{p.parent.name}/{p.name}") and live_config_path(str(p.parent), "/", {}),
     "Never", "don't write the real screen-share portal configs (hypr/xdph.conf, xdg-desktop-portal-wlr/, xdg-desktop-portal/*portals.conf): only the Screen sharing card's Apply does; test with a scratch XDG_CONFIG_HOME=<dir>."),
]


def check_path(path, kind, cwd, env):
    """Denies with the first PROTECTED_PATHS row `kind` matches, on each form of the path."""
    for p in path_forms(path, cwd, env):
        for kinds, test, section, why in PROTECTED_PATHS:
            if kind in kinds and test(p, kind):
                deny(section, why)
        if kind != "remove":
            check_generated_path(p)


# ------------------------------------------------------------------ main

def check(call):
    tool, tool_input = call.get("tool_name", ""), call.get("tool_input") or {}
    if tool == "Bash":
        cwd = call.get("cwd") or str(REPO)
        commands = split_commands(tool_input.get("command", ""))
        for env, argv in commands:
            check_argv(env, argv, cwd)
            # A `cd` into an existing folder moves the commands after it (an
            # agent's cwd resets every call); `..` folds after `~`, before links, as in the shell
            if argv[0] == "cd" and len(argv) == 2:
                target = resolve(os.path.normpath(os.path.expanduser(expand_vars(argv[1], env))), cwd)
                cwd = str(target) if target.is_dir() else cwd
        # A pgrep/pidof lookup in a call that kills (`kill $(pgrep qs)`, `pgrep qs | xargs kill`) is a pkill
        if any(Path(argv[0]).name == "kill" and not HELP_OPTS & set(command_options(argv[1:])) for _, argv in commands):
            for env, argv in commands:
                if Path(argv[0]).name in LOOKUPS:
                    check_argv(env, ["pkill", *argv[1:]], cwd)
    elif tool in {"Edit", "Write"}:
        if tool_input.get("file_path"):
            check_path(tool_input["file_path"], "edit", "/", {})


def main():
    try:
        call = json.load(sys.stdin)
    except ValueError:
        return 0
    try:
        check(call)
    except Denied as refusal:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": str(refusal),
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
