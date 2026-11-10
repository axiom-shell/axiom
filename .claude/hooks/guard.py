#!/usr/bin/env python3
"""PreToolUse guard: refuses the tool calls CLAUDE.md › "Never"
forbids, so they're enforced rather than only written down.

Claude Code runs it before every Bash, Edit and Write call (.claude/settings.json
› hooks) with the call as JSON on stdin; a refusal is printed as a `deny`
decision with the rule it breaks. The rules with an exception (scratch dirs,
the windowed greeter) live here; .claude/settings.json › permissions.deny
repeats the plain ones. Tests: tests/scripts/test_guard.py.

Bash commands are split into simple commands (on ; && || | & and newlines,
( ) { } $( ) and backticks (inside double quotes too), the keywords starting a
command such as `then`, into `bash -c`/`sh -c` strings; heredoc bodies only when
something could run them: drop_heredoc_bodies) and each is judged on its argv, with leading
VAR=value assignments (and `export VAR=…` earlier in the same command) as its
environment; a wrapper (sudo, nice, flock, …) is judged by the command it
runs, and a `>`/`>>` redirection as a write to its target. It guards itself:
writes to .claude/ where the session runs or Claude's settings, and another
`claude`, are refused too. Best effort: it stops mistakes, not an adversary.
"""
import itertools
import json
import os
import re
import shlex
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
HOME = Path(os.path.expanduser("~")).resolve()
# The live config.json (DataDirs.xdg)
LIVE_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config").resolve() / "axiom/config.json"
SCHEMA = REPO / "qml/config/json/config.schema.json"
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
QS = {"qs", "quickshell"}
QS_VALUE_OPTS = {"-c", "--config", "-p", "--path", "-m", "--manifest", "-i", "--id", "--pid", "--log-rules", "-n", "--newest"}
SAFE_QS = {"ipc", "log", "list", "msg"}


class Denied(Exception):
    pass


def deny(rule, why):
    raise Denied(f"Blocked by CLAUDE.md › {rule}: {why}")


# --------------------------------------------------------------- parsing

# A quoted string or escape (kept), or a `#` comment (dropped): one starts a
# word and ends at its newline, so `a#b`, `"#x"` and `${#var}` aren't comments
COMMENT = re.compile(QUOTED.pattern + r"|(?<![^\s;&|()<>])#[^\n]*", re.S)


def uncomment(m):
    text = m[0]
    if text[0] == "#":
        # A comment holding a quote is judged as a command of its own: a quote
        # read differently from the shell (`"$(echo ")"`) may end inside it
        return " ; " + text if set(text) & set("'\"") else ""
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
    """A heredoc's body is text, not commands: it is dropped, unless the
    command runs text it's given (a shell, `source`, `.`, `eval` or a script run
    by a path the command names elsewhere too: `bash <<EOF`, `cat <<EOF | sh`,
    `cat > x.sh <<EOF … bash x.sh` or `… ./x.sh`), the body is unquoted and substitutes (`$(…)`, backticks) or
    its delimiter never comes: then it is judged as written. Line continuations
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
            if not quote and SUBSTITUTION.search("\n".join(body)):
                out.extend(body)
    words = lex("\n".join(out))
    named = [os.path.normpath(w) for w in words]
    # `.`, or a script run by a path the command names elsewhere too, as the file it writes
    # (`./t.sh`, `sudo /tmp/t.sh`; not `/usr/bin/grep`), where a command starts, not a redirection's target
    runs = any(Path(w).name in SHELLS | {"source", "eval"} or (w == "." or "/" in w and named.count(named[i]) > 1)
               and (not i or words[i - 1] in KEYWORDS | WRAPPERS.keys() or set(words[i - 1]) <= set(";&|()`"))
               for i, w in enumerate(words))
    return command if runs else "\n".join(out)


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
        name, value = ASSIGN.match(tokens[i]).groups()
        env[name] = value
        i += 1
    argv = tokens[i:]
    if not argv:
        exported.update(env)
        return []
    if argv[0] == "export":
        for token in argv[1:]:
            if ASSIGN.match(token):
                name, value = ASSIGN.match(token).groups()
                exported[name] = value
        return []
    # Wrappers: judge the command they run
    while argv and Path(argv[0]).name in WRAPPERS:
        wrapper = Path(argv[0]).name
        argv = argv[1:]
        while argv and (argv[0].startswith("-") or ASSIGN.match(argv[0])):
            if ASSIGN.match(argv[0]):
                name, value = ASSIGN.match(argv[0]).groups()
                env[name] = value
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
    # A script run through a shell (`bash data/greeter/greeter_install.sh …`): judge the script
    if Path(argv[0]).name in SHELLS:
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
# names a scratch socket, runtime dir or config dir
AXIOM_VALUE_OPTS = {"--socket", "--config-dir", "--tree", "--qs", "-o", "--kind"}
LIVE_RUNTIME = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")


def long_flag(a):
    """Go's flag package takes a long option with one dash too
    (`-config-dir`): its two-dash spelling."""
    return "-" + a if a.startswith("-") and not a.startswith("--") and len(a.split("=", 1)[0]) > 2 else a


def axiom_flag(args, flag):
    for i, a in enumerate(map(long_flag, args)):
        if a == flag and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(flag + "="):
            return a.split("=", 1)[1]
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


def axiom_live_display(env, args):
    """Whether an axiom command reaches the live session's daemon: the CLI's
    order (cli/client.go socketPath) is --socket, $AXIOM_SOCKET (maybe
    inherited), then $XDG_RUNTIME_DIR/axiom/$WAYLAND_DISPLAY."""
    socket = axiom_flag(args, "--socket") or (env["AXIOM_SOCKET"] if "AXIOM_SOCKET" in env else os.environ.get("AXIOM_SOCKET", ""))
    if socket:
        return not scratch(socket) or live_socket(socket, env)
    runtime = env.get("XDG_RUNTIME_DIR", "")
    if runtime and resolve(runtime, "/", env) != Path(LIVE_RUNTIME):
        return False
    # WAYLAND_DISPLAY=$WAYLAND_DISPLAY is the live one: expand it without itself
    display = expand_vars(env.get("WAYLAND_DISPLAY", ""), {k: v for k, v in env.items() if k != "WAYLAND_DISPLAY"})
    if display and ("$" in display or LIVE_DISPLAY and display_name(display) != LIVE_DISPLAY):
        return False  # another display's daemon (or a variable the agent made: trust it)
    return True


# fcitx5's Controller1 methods that change or end the running fcitx5
FCITX_WRITES = ("SetInputMethodGroupInfo", "SetConfig", "Save", "Restart", "Exit", "AddInputMethodGroup", "RemoveInputMethodGroup")


def live_bus(env, args):
    """Whether a D-Bus client reaches the live session bus: no --address (or
    busctl's/dbus-send's/gdbus's spellings of a bus of its own) and the
    session's DBUS_SESSION_BUS_ADDRESS (unset: the live one)."""
    if any(a == "--address" or a.startswith("--address=") or a == "--system" for a in args):
        return False
    address = env.get("DBUS_SESSION_BUS_ADDRESS")
    return address is None or address == os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")


def axiom_words(args):
    """The subcommand words of an axiom command line, flags left out."""
    words, skip = [], False
    for a in args:
        if skip:
            skip = False
            continue
        if long_flag(a) in AXIOM_VALUE_OPTS:
            skip = True
            continue
        if not a.startswith("-"):
            words.append(a)
    return words


def check_axiom(env, args, cwd):
    words = axiom_words(args)
    if not words:
        return
    live = axiom_live_display(env, args)
    sub = words[0]
    if live and sub in {"run", "quit", "restart"}:
        deny("Never", f"`axiom {sub}` starts or stops the live shell; never from this session (test with a scratch XDG_RUNTIME_DIR, or nested.sh).")
    # A scratch daemon on the machine's system bus is BlueZ's pairing agent
    # beside the live one (Bluetooth.pairingAgent defaults on): it takes the
    # pairings a device starts and rejects them with no shell to ask
    if not live and sub == "run" and not scratch_system_bus(env) and env.get("AXIOM_BLUETOOTH_AGENT") != "off":
        deny("Never", "a scratch `axiom run` on the machine's system bus registers a second Bluetooth pairing agent with the live BlueZ; run it with AXIOM_BLUETOOTH_AGENT=off, or on a scratch system bus (DBUS_SYSTEM_BUS_ADDRESS=<a dbus-run-session's>), or use nested.sh.")
    if live and sub == "daemon" and words[1:2] and words[1] in {"stop", "restart", "reexec"}:
        deny("Never", f"`axiom daemon {words[1]}` stops or replaces the live daemon; never from this session.")
    # Dev mode: switching it, its tree or options, or copying the dev config
    # over the live one (status and `dev config diff` only read)
    if live and sub == "dev" and (words[1:2] and words[1] in {"on", "off", "rebuild", "set", "options"}
                                  or words[1:3] in (["config", "copy"], ["config", "pull"])):
        verb = " ".join(words[1:3] if words[1] == "config" else words[1:2])
        deny("Never", f"`axiom dev {verb}` changes the live daemon's dev mode or config; ask the user, or drive a nested daemon (--socket $XDG_RUNTIME_DIR/axiom/<nested display>/axiom.sock). `axiom dev status` and `dev config diff` read it.")
    if live and (sub == "lock" or sub == "ipc" and words[1:2] == ["lockscreen"]):
        deny("Never", "don't lock the session; only the user can type the password (lock a scratch instance: XDG_RUNTIME_DIR=<scratch>).")
    if live and sub == "ipc" and words[1:3] in (["monitors", "keep"], ["selfUpdate", "update"]):
        deny("Never", f"`{' '.join(words[1:3])}` changes the live system; ask the user.")
    if sub == "greeter":
        gdir = axiom_flag(args, "--dir") or env.get("AXIOM_GREETER_DIR", "")
        installed = gdir and "$" not in gdir and resolve(gdir, "/") == Path("/var/lib/axiom-greeter")
        shown = env.get("AXIOM_GREETER_WINDOWED") == "1" or "--no-shell" in args
        if not shown or not scratch(gdir) or installed:
            deny("Never", "run the greeter only windowed on a scratch folder: AXIOM_GREETER_WINDOWED=1 AXIOM_COMPOSITOR=none axiom greeter --dir <scratch> (or --no-shell).")
    # The greeter installer's root side, which greeter_install.sh runs
    if sub == "greeter-install" and words[1:2] and words[1] in {"install", "update", "uninstall"}:
        if not scratch(env.get("AXIOM_GREETER_ROOT", "")):
            deny("Never", "axiom greeter-install install/update/uninstall only with a scratch AXIOM_GREETER_ROOT=<dir>.")
    # A compositor claim (managed mode) on the live config, or moving binds
    # out of its files (the bind merge's remove)
    if sub == "compositor" and words[1:2] and words[1] in {"claim", "release"} and words[2:3]:
        if live_config_path(words[2], cwd, env):
            deny("Never", f"`axiom compositor {words[1]}` only on a scratch dir, never the live compositor config.")
    if sub == "compositor" and words[1:3] == ["binds", "remove"] and words[3:4]:
        if live_config_path(words[3], cwd, env):
            deny("Never", "`axiom compositor binds remove` only on a scratch dir, never the live compositor config.")
    if sub == "config" and "--takeover" in args:
        config_dir = axiom_flag(args, "--config-dir") or env.get("XDG_CONFIG_HOME", "")
        if not scratch(config_dir) or live:
            deny("Never", "`--takeover` changes a setting that takes something over on this PC (compositor mode, locker, idle, polkit, greeter); ask the user.")


# The gh commands an agent may run: every read, and these writes. Anything else is refused,
# `gh api` in every form. A group named alone allows all its subcommands.
GH_ALLOWED = {
    # Reads (not `browse`, which opens a browser)
    "pr list", "pr view", "pr diff", "pr checks", "pr status", "run list", "run view", "run watch", "run download",
    "issue list", "issue view", "issue status", "repo list", "repo view", "repo clone", "repo read-dir", "repo read-file",
    "repo gitignore", "repo license", "release list", "release view", "release download", "release verify",
    "release verify-asset", "workflow list", "workflow view", "label list", "ruleset list", "ruleset view",
    "ruleset check", "search", "status", "auth status", "cache list", "variable list", "variable get", "secret list",
    "gist list", "gist view", "project list", "project view", "project field-list", "project item-list", "org list",
    "discussion list", "discussion view", "agent-task list", "agent-task view", "codespace list", "codespace view",
    "attestation verify", "attestation trusted-root", "extension list", "extension search", "alias list",
    "config get", "config list", "gpg-key list", "ssh-key list", "skill list", "skill search", "skill preview", "version",
    # Issue management (`issue create` only when the maintainer asks for an issue)
    "issue create", "issue edit", "issue comment", "issue close", "issue reopen", "issue lock", "issue unlock",
    # Re-running and starting actions
    "run rerun", "run cancel", "workflow run",
    # PRs: merging (not `--admin`, past main's protection), opening and labelling
    "pr merge", "pr create", "pr comment", "pr edit", "pr close", "pr ready", "pr checkout",
}


def gh_allowed(args):
    """Help, or a command on GH_ALLOWED; -R/--repo (anywhere) doesn't hide it.
    The command is the leading words only (`gh repo --description view edit` runs
    edit), and a flag's value (`-H --help`) isn't help"""
    args = args[:args.index("--")] if "--" in args else args
    args = [a for k, a in enumerate(args) if not a.startswith(("-R", "--repo")) and args[k - 1:k] not in (["-R"], ["--repo"])]
    if any(a in {"-h", "--help"} and not re.fullmatch(r"--?[\w-]+", args[k - 1] if k else "") for k, a in enumerate(args)):
        return True
    words = list(itertools.takewhile(lambda a: not a.startswith("-"), args))
    words[:1] = [{"rs": "ruleset"}.get(w, w) for w in words[:1]]
    if all(a.startswith("-") for a in args) or words[:1] == ["help"]:
        return True
    if words[:2] == ["pr", "merge"] and any(a == "--admin" or a.startswith("--admin=") for a in args):
        return False
    return bool(words) and (words[0] in GH_ALLOWED or " ".join(words[:2]) in GH_ALLOWED)


# ----------------------------------------------------------------- rules

GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
# The pushes an agent may run: `git push [these] origin <branch>` (or
# `<src>:<branch>`), named, never main, a `v*` tag, HEAD, a force (+) or a delete (:)
PUSH_OPTS = {"-u", "--set-upstream", "-q", "--quiet", "-n", "--dry-run"}


def push_allowed(args):
    words = [a for a in args if a not in PUSH_OPTS]
    # Spelled out: no `$br` / `$(git branch --show-current)`, which may be main
    if len(words) != 2 or words[0] != "origin" or not re.fullmatch(r"\w[\w./-]*(:\w[\w./-]*)?", words[1]) or "HEAD" in words[1]:
        return False
    # git completes `heads/main` to refs/heads/main; a `v*` tag is a release (.github/workflows/release.yml)
    dest = words[1].split(":")[-1].removeprefix("refs/").removeprefix("heads/")
    return dest not in {"main", "master"} and not re.match(r"tags/|v\d", dest)


def check_git(args):
    """`git push` beyond PUSH_OPTS' shape: every change reaches main through a
    reviewed PR. `git clean -x`,
    which deletes the ignored files."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in GIT_VALUE_OPTS else 1
    rule = "Never"
    if args[i:i + 1] == ["clean"] and any(re.fullmatch(r"-[a-zA-Z]*[xX][a-zA-Z]*", a) for a in args[i + 1:]):
        deny(rule, "`git clean -x`/`-X` deletes the generated files and local state; remove the files you mean by name (`git clean -fd` is fine).")
    if args[i:i + 1] == ["push"] and not push_allowed(args[i + 1:]):
        deny(rule, "push only `git push [-u] origin <branch>`, a named branch that isn't main: no force, delete, HEAD or bare push.")


def check_argv(env, argv, cwd, guarded):
    name = Path(argv[0]).name
    args = argv[1:]

    # Lock the built-in locker
    if name == "loginctl" and any(a.startswith("lock-session") for a in args):
        deny("Never", "don't lock the session; only the user can type the password. Test LockSurface in a hidden window.")
    if name == "hyprlock":
        deny("Never", "don't lock the screen; only the user can type the password.")

    # Simulate cursor movement
    if name in {"ydotool", "dotool", "dotoolc", "wlrctl"} or any("movecursor" in a or "cursor.move" in a for a in argv):
        deny("Never", "don't simulate cursor movement; check logs and reason through bindings, or ask the user to look.")

    # The shell itself, and its IPC
    if name in QS:
        check_qs(env, args)

    # The axiom binary: it is the shell's parent and its command line
    if name == "axiom":
        check_axiom(env, args, cwd)

    # gh beyond its allowlist
    if name == "gh" and not gh_allowed(args):
        deny("Never", f"`gh {' '.join(args[:2])}` isn't on guard.py's GH_ALLOWED (no `gh api`); ask the user.")

    # Rewriting history on the remote, pushing to main past a PR, or git clean -x
    if name == "git":
        check_git(args)

    # Greetd
    if name in {"systemctl", "service", "pkill", "killall"} and any("greetd" in a for a in args):
        if name in {"pkill", "killall"} or any(a in {"restart", "stop", "start", "reload", "kill", "disable", "enable", "mask", "try-restart", "reload-or-restart"} for a in args):
            deny("Never", "don't restart or stop greetd: it ends the session.")

    # Greeter install / update / uninstall
    if name == "greeter_install.sh" and args and args[0] in {"install", "update", "uninstall"}:
        if not scratch(env.get("AXIOM_GREETER_ROOT", "")):
            deny("Never", "greeter_install.sh install/update/uninstall only with a scratch AXIOM_GREETER_ROOT=<dir>.")

    # Ending, reconfiguring or swapping the config of the niri session
    # itself: only a nested niri (NIRI_SOCKET aimed at another one than the
    # session's own) may be told to
    if name == "niri" and args[:1] == ["msg"]:
        rest = [a for a in args[1:] if a not in {"-j", "--json"}]
        changes = rest[:1] == ["output"] or (rest[:1] == ["action"] and rest[1:2] in (["quit"], ["load-config-file"]))
        socket = env.get("NIRI_SOCKET", os.environ.get("NIRI_SOCKET", ""))
        if changes and (not socket or socket == os.environ.get("NIRI_SOCKET", "")):
            deny("Never", "niri msg output / action quit / load-config-file only on a nested niri (NIRI_SOCKET=<its socket>), never the live session.")

    # A hookup's Apply (the daemon's hookup.apply, which edits the configs
    # of the HOME the daemon runs with) sent to the live daemon by hand:
    # only to a scratch one (XDG_RUNTIME_DIR / AXIOM_SOCKET)
    sends = name in {"socat", "nc", "ncat", "websocat", "echo", "printf", "axiom"} or name.startswith("python")
    if sends and any("hookup.apply" in a for a in args) and axiom_live_display(env, args):
        deny("Never", "hookup.apply only to a scratch daemon (XDG_RUNTIME_DIR=<scratch>), never the live one: it edits the real configs (test it with go test ./internal/compositor/edit).")

    # A self-update (the daemon's selfupdate.apply, which updates the tree
    # the daemon runs from: the live repo) sent to the live daemon by hand
    if sends and any("selfupdate.apply" in a for a in args) and axiom_live_display(env, args):
        deny("Never", "selfupdate.apply only to a scratch daemon (XDG_RUNTIME_DIR=<scratch>), never the live one: it updates the live repo (test it with go test ./internal/selfupdate).")

    # The login screen's install, update or uninstall (the daemon's
    # greeter.apply, which runs the installer as root through pkexec) sent
    # to the live daemon by hand
    if sends and any("greeter.apply" in a for a in args) and axiom_live_display(env, args):
        deny("Never", "greeter.apply only to a scratch daemon (XDG_RUNTIME_DIR=<scratch>), never the live one: it installs the greeter for real (test it with go test ./internal/greeterinstall).")

    # Dev mode's writes (the daemon's dev.set, dev.rebuild, dev.config.copy
    # and dev.config.pull: switching its image or tree, or writing a config)
    # sent to the live daemon by hand, past the axiom dev verbs' rule
    dev_writes = ("dev.set", "dev.rebuild", "dev.config.copy", "dev.config.pull")
    if sends and any(m in a for a in args for m in dev_writes) and axiom_live_display(env, args):
        deny("Never", "dev.set / dev.rebuild / dev.config.copy|pull only to a nested or scratch daemon (XDG_RUNTIME_DIR=<scratch>, --socket), never the live one.")

    # The live input method's settings: fcitx5's Controller1 writes and
    # restarts, ibus's gsettings / dconf keys, and the daemon's inputMethod
    # writes; only on a scratch session bus (--address, another
    # DBUS_SESSION_BUS_ADDRESS) or a scratch daemon
    if name in {"busctl", "dbus-send", "gdbus"} and any("org.fcitx.Fcitx" in a for a in args) \
            and any(re.search(rf"(^|[.\s]){m}($|[\s(])", a) for a in args for m in FCITX_WRITES) and live_bus(env, args):
        deny("Never", "don't change the live fcitx5 (SetInputMethodGroupInfo, SetConfig, Save, Restart, Exit, …); use a scratch session bus (dbus-run-session) or go test ./internal/inputmethod.")
    ibus_keys = any(a.startswith(("org.freedesktop.ibus", "/desktop/ibus")) for a in args)
    writes_setting = name == "gsettings" and args[:1] and args[0] in {"set", "reset", "reset-recursively"} or \
        name == "dconf" and args[:1] and args[0] in {"write", "reset", "load"}
    if writes_setting and ibus_keys and env.get("GSETTINGS_BACKEND", "") != "memory" and live_bus(env, args):
        deny("Never", "don't change the live ibus settings (gsettings set org.freedesktop.ibus.*); use GSETTINGS_BACKEND=memory or a scratch session bus.")
    im_writes = ("inputMethod.push", "inputMethod.options", "inputMethod.framework")
    words = [a for a in args if not a.startswith("-")]
    by_ipc = name == "axiom" and any(words[i:i + 2] == ["inputMethod", w] for i in range(len(words)) for w in ("push", "options", "framework"))
    if sends and (by_ipc or any(m in a for a in args for m in im_writes)) and axiom_live_display(env, args):
        deny("Never", "inputMethod.push / options / framework only to a nested or scratch daemon (XDG_RUNTIME_DIR=<scratch>, --socket): they rewrite the live IME's settings.")

    # The machine's own settings: its clock and time zone, hostname, the
    # user's account (password, picture, name) and default apps. Only
    # against a scratch system bus (dbus-run-session) or a scratch daemon
    written, removed = touched_paths(name, args, cwd, env)
    check_system_settings(env, name, args, cwd, sends, written + removed)
    check_bluetooth(env, name, args, sends)
    check_portal(name, args, written + removed, cwd, env)
    # find deletes what matches under its folders, not the folders: refused only inside
    check_guard_paths(*((written + removed, []) if name == "find" else (written, removed)), cwd, env, guarded)

    # Another claude loads the settings of the folder it starts in: without this guard
    if name == "claude" or name in {"npx", "bunx"} and any(a.startswith("@anthropic-ai/claude-code") for a in args):
        deny("Never", "don't start another `claude` from Bash: it runs without this guard; ask the user (or use a subagent, which runs this session's).")

    # The real config.json: deleted or moved (the file or a folder above it)
    if any(resolve(a, cwd, env) in {LIVE_CONFIG, *LIVE_CONFIG.parents} for a in removed):
        deny("Never", f"don't delete or move the real config.json ({LIVE_CONFIG}) or a folder holding it; use `axiom ipc onboarding goTo <n>`.")
    # ... or written by Bash, which skips the x-takeover check Edit and Write get
    if any(resolve(a, cwd, env) == LIVE_CONFIG for a in written):
        deny("Never", f"don't write the real config.json ({LIVE_CONFIG}) from Bash, which skips the x-takeover check; use Edit/Write or `axiom config set`.")

    # qmlformat -i replaces the inode
    if name == "qmlformat" and any(a in {"-i", "--inplace"} for a in args):
        deny("Formatting and layout", "qmlformat -i replaces the file's inode, so qs stops reloading it; verify.sh formats in place.")



# The daemon's methods that change the machine's settings (Settings ›
# Account, Date & time, Default apps, System info)
SYSTEM_WRITES = ("datetime.setTimezone", "datetime.setNtp", "datetime.setTime", "system.setHostname",
                 "account.setIcon", "account.setRealName", "account.changePassword", "apps.setDefault")
# Their system-bus services, and the programs that change the same settings
SYSTEM_BUS_SERVICES = ("org.freedesktop.timedate1", "org.freedesktop.hostname1", "org.freedesktop.Accounts")
BUS_CALLERS = {"busctl", "gdbus", "dbus-send", "qdbus", "qdbus6"}
ACCOUNT_PROGRAMS = {"passwd", "chpasswd", "chfn", "usermod", "chsh"}
# The default-apps files, under the live XDG_CONFIG_HOME
DEFAULT_APPS_FILES = {"mimeapps.list", "xdg-terminals.list"}


def scratch_system_bus(env):
    """A system bus address the command names itself (a dbus-run-session
    or test bus), not the machine's."""
    address = env.get("DBUS_SYSTEM_BUS_ADDRESS", "")
    return bool(address) and "/run/dbus/system_bus_socket" not in address


def default_apps_name(name):
    return name in DEFAULT_APPS_FILES or name.endswith("-mimeapps.list") or name.endswith("-xdg-terminals.list")


def live_default_apps_file(path, cwd, env):
    """Whether path is mimeapps.list, a desktop-specific one
    (hyprland-mimeapps.list) or xdg-terminals.list in a live config folder."""
    p = Path(path)
    return default_apps_name(p.name) and live_config_path(str(p.parent), cwd, env)


def check_system_settings(env, name, args, cwd, sends, touched):
    if name == "timedatectl" and any(a.startswith("set-") for a in args):
        deny("Never", "don't change the machine's clock or time zone; test datetime against a scratch system bus (tests in backend/internal/timedate).")
    if name == "hostnamectl" and len([a for a in args if not a.startswith("-")]) > 1:
        deny("Never", "don't rename the machine or change its hostname1 settings; test against a scratch system bus.")
    if name in ACCOUNT_PROGRAMS:
        deny("Never", f"`{name}` changes the user's account; only the user changes their password or account (test with the fakes in backend/internal/account).")
    if name in BUS_CALLERS and any(s in a for a in args for s in SYSTEM_BUS_SERVICES):
        writes = any(re.match(r"Set[A-Z]", a) or ".Set" in a for a in args) or "set-property" in args
        if writes and not scratch_system_bus(env):
            deny("Never", "don't call timedate1 / hostname1 / Accounts setters on the machine's bus; use a scratch one (DBUS_SYSTEM_BUS_ADDRESS=<it>).")
    if sends and any(m in a for a in args for m in SYSTEM_WRITES) and axiom_live_display(env, args):
        deny("Never", "datetime.set* / system.setHostname / account.* / apps.setDefault only to a scratch daemon (XDG_RUNTIME_DIR=<scratch>), never the live one: they change the machine's settings.")
    if (name == "xdg-mime" and args[:1] == ["default"] or name == "xdg-settings" and args[:1] == ["set"]) and not scratch(env.get("XDG_CONFIG_HOME", "")):
        deny("Never", f"`{name} {args[0]}` changes the user's default apps; only with a scratch XDG_CONFIG_HOME=<dir>.")
    if any(live_default_apps_file(a, cwd, env) for a in touched):
        deny("Never", "don't write the user's mimeapps.list / xdg-terminals.list; test default apps with a scratch XDG_CONFIG_HOME=<dir>.")


# bluetoothctl's commands that drop, block or pair a real device, turn the
# adapter off, or register an agent beside the daemon's
BLUETOOTHCTL_WRITES = {"remove", "block", "disconnect", "pair", "cancel-pairing", "agent", "default-agent"}
# bluetoothctl's options that take a value (skipped to find its command)
BLUETOOTHCTL_VALUED = {"-t", "--timeout", "-a", "--agent", "-i", "--init-script"}
# ... and those that register an agent or run a file's commands
BLUETOOTHCTL_REFUSED = ("-a", "--agent", "-i", "--init-script")
# BlueZ's methods that do the same over D-Bus
BLUEZ_WRITES = ("RemoveDevice", "Disconnect", "DisconnectProfile", "Pair", "CancelPairing", "RegisterAgent", "RequestDefaultAgent", "UnregisterAgent")
# The daemon's Bluetooth methods that do the same
BLUETOOTH_RPC_WRITES = ("bluetooth.forget", "bluetooth.setPowered", "bluetooth.setBlocked", "bluetooth.disconnect", "bluetooth.pair", "bluetooth.agentReply")


def check_bluetooth(env, name, args, sends):
    """A real Bluetooth device forgotten, unpaired, blocked or disconnected,
    the live adapter turned off, or a second agent registered with the live
    BlueZ: a mouse or keyboard could drop out. Only against a scratch system
    bus (DBUS_SYSTEM_BUS_ADDRESS) for what talks to D-Bus itself; rfkill
    never; the daemon's calls only to a scratch daemon, the call carrying a
    scratch system bus too (one on the machine's bus reaches the real
    devices all the same)."""
    scratch = scratch_system_bus(env)
    words = [a for a in args if not a.startswith("-")]
    if name == "bluetoothctl" and not scratch and not set(args) & {"-v", "--version", "-h", "--help"}:
        command = [a for i, a in enumerate(args) if not a.startswith("-") and (not i or args[i - 1] not in BLUETOOTHCTL_VALUED)]
        if any(a.split("=")[0] in BLUETOOTHCTL_REFUSED for a in args):
            deny("Never", "bluetoothctl's --agent registers a second agent and --init-script runs a file's commands against the live BlueZ; use the fake BlueZ (go test ./internal/bluez).")
        if not command:
            deny("Never", "bluetoothctl with no command reads its commands from stdin (a pipe, a here-string), which can't be checked; give it one command as arguments (`bluetoothctl show`).")
        # power takes on / off / yes / no …: only on passes
        if command[0] in BLUETOOTHCTL_WRITES or command[0] == "power" and command[1:2] != ["on"]:
            deny("Never", f"`bluetoothctl {' '.join(command[:2])}` changes a real Bluetooth device or the live adapter; test with the fake BlueZ (go test ./internal/bluez).")
    if name == "rfkill" and ("block" in words or "toggle" in words):
        deny("Never", "don't rfkill-block the live radios: a Bluetooth mouse or keyboard could drop out.")
    if name in BUS_CALLERS and not scratch and any("org.bluez" in a for a in args):
        # Powered off turns the adapter off, Blocked disconnects a device
        powered = any("Powered" in a or "Blocked" in a for a in args) and ("set-property" in args or any(a.endswith("Properties.Set") or a == "Set" for a in args))
        if powered or any(re.search(rf"(^|[.\s]){m}($|[\s(])", a) for a in args for m in BLUEZ_WRITES):
            deny("Never", "don't call BlueZ's RemoveDevice / Disconnect / Pair / RegisterAgent or set Powered / Blocked on the machine's bus; use the fake BlueZ (go test ./internal/bluez) or a scratch bus (DBUS_SYSTEM_BUS_ADDRESS=<it>).")
    # `axiom bluetooth off` is the named form of `ipc bluetooth disable`;
    # airplane mode powers the adapter off too
    by_ipc = name == "axiom" and any(words[i:i + 2] in (["bluetooth", "disable"], ["bluetooth", "off"], ["bluetooth", "toggle"], ["airplane", "enable"], ["airplane", "toggle"]) for i in range(len(words)))
    if sends and (by_ipc or any(m in a for a in args for m in BLUETOOTH_RPC_WRITES)) and (not scratch or axiom_live_display(env, args)):
        deny("Never", "bluetooth.forget / setPowered / setBlocked / disconnect / pair / agentReply (and `axiom ipc bluetooth disable|toggle`, `axiom bluetooth off|toggle`, `airplane enable|toggle`) reach the machine's BlueZ from any daemon on its system bus, a scratch one too: only to a daemon started on a scratch system bus, the call made with that DBUS_SYSTEM_BUS_ADDRESS.")


REMOVES = {"rm", "unlink", "trash", "trash-put", "shred"}
MODE = re.compile(r"[0-7]+|([ugoa]*[-+=][rwxXst]*,?)+")


def touched_paths(name, args, cwd, env):
    """(written, removed): the paths a command writes (cp / mv / install / ln's
    destination, a file copied into a folder as its own path there, the files
    of > / tee / truncate / sed -i / chmod / chown) and the ones it deletes or
    moves away (rm and the like, mv's sources, find -delete)."""
    paths = [a for a in args if not a.startswith("-")]
    if name == "find" and any(a == "-delete" or a in {"-exec", "-execdir"} and Path(b).name in REMOVES
                              for a, b in zip(args, args[1:] + [""])):
        return [], args[:next((i for i, a in enumerate(args) if a[:1] in {"-", "(", "!"}), len(args))]
    if name in {"cp", "mv", "install", "ln"} and len(paths) > 1:
        *sources, dest = paths
        into = dest.endswith("/") or resolve(dest, cwd, env).is_dir()
        return [os.path.join(dest, Path(p).name) for p in sources] if into else [dest], sources if name == "mv" else []
    if name in REMOVES:
        return [], paths
    if name in {">", "tee", "truncate"} or name == "sed" and any(a.startswith("--in-place") or re.fullmatch(r"-[a-zA-Z]*i\S*", a) for a in args):
        return paths, []
    if name == "chmod":  # its mode may look like an option (-x), so files are what isn't one
        return [p for p in paths if not MODE.fullmatch(p)], []
    if name == "chown":
        return paths[1:], []
    return [], []


# Under .claude/ but not the guard's: the worktrees Claude Code makes for
# isolated agents
UNGUARDED = ("worktrees",)


def claude_guarded(cwd):
    """What switches this guard off: the .claude/ folder where the session runs
    ($CLAUDE_PROJECT_DIR, else its cwd: this hook, settings.json, skills, agents)
    and the user's Claude settings ($CLAUDE_CONFIG_DIR's and ~/.claude's); and
    the folders in it UNGUARDED frees."""
    homes = {Path(os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude")), HOME / ".claude"}
    project = Path(os.environ.get("CLAUDE_PROJECT_DIR") or cwd) / ".claude"
    guarded = [project, *(home / name for home in homes for name in ("settings.json", "settings.local.json"))]
    forms = lambda paths: {form for path in paths for form in path_forms(str(path), "/", {})}
    return forms(guarded), forms(project / name for name in UNGUARDED)


def check_guard_paths(written, removed, cwd, env, guarded):
    """A write into what claude_guarded names, or a removal of it or a folder holding it."""
    guarded, free = guarded
    for path, removes in [(a, False) for a in written] + [(a, True) for a in removed]:
        forms = [t for t in path_forms(path, cwd, env) if not any(t == f or f in t.parents for f in free)]
        if any(t == g or g in t.parents or removes and t in g.parents for t in forms for g in guarded):
            deny("Never", "don't edit the running guard or Claude's settings (.claude/ where the session runs, the user's settings.json): ask the user; the guard changes through a PR.")


def portal_config_name(path):
    """Whether path names a screen-share portal's config: xdph.conf under
    hypr/, xdg-desktop-portal-wlr's, or a portals.conf of xdg-desktop-portal."""
    p = Path(path)
    return (p.name == "xdph.conf" and p.parent.name == "hypr"
            or p.parent.name == "xdg-desktop-portal-wlr"
            or p.parent.name == "xdg-desktop-portal" and p.name.endswith("portals.conf"))


def live_portal_config(path, cwd, env):
    return portal_config_name(path) and live_config_path(str(Path(path).parent), cwd, env)


def check_portal(name, args, touched, cwd, env):
    # Restarting or stopping the portal ends every share running
    if name in {"systemctl", "service", "pkill", "killall", "kill"} and any("xdg-desktop-portal" in a for a in args):
        if name in {"pkill", "killall", "kill"} or any(a in {"restart", "stop", "kill", "reload", "try-restart", "reload-or-restart", "mask", "disable"} for a in args):
            deny("Never", "don't restart or stop the live xdg-desktop-portal (or its backends): it ends the shares running; ask the user (the Screen sharing card's Restart does it on a click).")
    for a in touched:
        if live_portal_config(a, cwd, env):
            deny("Never", "don't write the real screen-share portal configs (hypr/xdph.conf, xdg-desktop-portal-wlr/, xdg-desktop-portal/*portals.conf): only the Screen sharing card's Apply does; test with a scratch XDG_CONFIG_HOME=<dir>.")


def check_portal_config_edit(tool_input):
    path = tool_input.get("file_path", "")
    if path and live_portal_config(path, "/", {}):
        deny("Never", "don't edit the real screen-share portal configs; only the Screen sharing card's Apply does (test with a scratch XDG_CONFIG_HOME=<dir>).")


def check_default_apps_edit(tool_input):
    path = tool_input.get("file_path", "")
    if path and live_default_apps_file(path, "/", {}):
        deny("Never", "don't edit the user's mimeapps.list / xdg-terminals.list; test default apps with a scratch XDG_CONFIG_HOME=<dir>.")


def check_qs(env, args):
    i, sub, rest = 0, None, []
    while i < len(args):
        a = args[i]
        if a in QS_VALUE_OPTS:
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        sub, rest = a, args[i + 1:]
        break
    options = args[:i]
    if sub in SAFE_QS:
        return
    greeter = env.get("AXIOM_GREETER") == "1" and any(o.endswith("greeter.qml") for o in options)
    if sub == "kill":
        flags = options + rest
        if any(o in {"-i", "--id", "--pid"} for o in flags) or any(o.endswith("greeter.qml") for o in flags):
            return
        deny("Never", "the shell runs detached; never stop it from this session (`qs kill` only the greeter instance you started: `qs kill -p <…>/greeter.qml` or `-i <id>`).")
    if sub is None:
        if greeter:
            return
        deny("Never", "the shell runs detached; never start another from this session (the windowed greeter: AXIOM_GREETER_WINDOWED=1 AXIOM_COMPOSITOR=none axiom greeter --dir <scratch>).")


# ---------------------------------------------------- Edit/Write config.json

def takeover_paths(schema):
    out = []

    def walk(node, path):
        if not isinstance(node, dict):
            return
        if node.get("x-takeover") is True:
            out.append(path)
        for key, child in (node.get("properties") or {}).items():
            walk(child, path + [key])

    walk(schema, [])
    return out


def value_at(config, path):
    for key in path:
        if not isinstance(config, dict) or key not in config:
            return None
        config = config[key]
    return config


def check_config_edit(tool, tool_input):
    path = tool_input.get("file_path", "")
    if not path or Path(path).resolve() != LIVE_CONFIG:
        return
    try:
        before_text = Path(path).resolve().read_text()
    except OSError:
        return
    if tool == "Write":
        after_text = tool_input.get("content", "")
    else:
        old, new = tool_input.get("old_string", ""), tool_input.get("new_string", "")
        after_text = before_text.replace(old, new) if tool_input.get("replace_all") else before_text.replace(old, new, 1)
    try:
        before, after = json.loads(before_text), json.loads(after_text)
        schema = json.loads(SCHEMA.read_text())
    except (ValueError, OSError):
        return  # an invalid file never replaces the running config: nothing to guard
    for path in takeover_paths(schema):
        if value_at(before, path) != value_at(after, path):
            deny("Never", f"`{'.'.join(path)}` takes something over on this PC (x-takeover: compositor mode, locker, idle, polkit, greeter). Ask the user before changing it in the live config.")


# ------------------------------------------- Edit/Write generated or frozen

# Files built from a source (edit the source) and frozen ones (never edit)
GENERATED = {
    REPO / "qml/config/json/config.schema.json": "it's built from qml/config/schema/ (edit the YAML there; scripts/generate.sh rebuilds it)",
}
# Generated directories (scripts/generate.sh), never committed
GENERATED_DIRS = {
    REPO / "backend/internal/assets/data": "the binary's embedded copies (go generate writes them from the repo files)",
    REPO / "tests/fixtures/shared": "the shared fixtures, recorded from SchemaValidation.qml (scripts/dev/fixtures.py record)",
    REPO / "backend/internal/migrate/legacy/testdata": "the format-1 migration's frozen cases, recorded from the shell before its copy was removed",
}
FROZEN = {
    REPO / "backend/internal/migrate/legacy/legacy.js": "the format-1 migrations are frozen (docs/recipes/migration.md)",
    REPO / "backend/internal/migrate/legacy/schema-v75.json": "the format-1 schema is frozen with its migrations (docs/recipes/migration.md)",
}


def check_generated_edit(tool_input):
    path = tool_input.get("file_path", "")
    if not path:
        return
    resolved = Path(path).resolve()
    if resolved in GENERATED:
        deny("Never", f"`{resolved.relative_to(REPO)}` is generated: {GENERATED[resolved]}.")
    if resolved in FROZEN:
        deny("Config", f"`{resolved.relative_to(REPO)}` is frozen: {FROZEN[resolved]}.")
    for generated, why in GENERATED_DIRS.items():
        if resolved.is_relative_to(generated):
            deny("Never", f"`{resolved.relative_to(REPO)}` is generated: {why}.")


# ------------------------------------------------------------------ main

# `cd /dir && …` (or `;`, a newline; several such cds): `&&`-joined pipelines
# with redirections after them, and no `;`, `||`, lone `&`, `\&`, newline,
# subshell, substitution, variable or relative folder (CDPATH) that could run a
# command somewhere else than the folder; every later command a program on PATH
# (a function, alias or builtin like `noglob cd`, `repeat 1 cd`, `__zoxide_cd`
# may move the shell) that doesn't move (MOVES)
LEADING_CD = re.compile(r"(?:\s*cd[ \t]+[/~][^\s\\;&|()<>`$]*[ \t]*(?:&&|;|\n))+(?:[^\n\\;&|()<>`$]|&&|\|(?![|&])|\d*>&\d+|[<>]{1,2}(?![&|(]))+")
MOVES = {"cd", "chdir", "pushd", "popd", "eval", "builtin", "source", "."}


def check(call):
    tool, tool_input = call.get("tool_name", ""), call.get("tool_input") or {}
    guarded = claude_guarded(call.get("cwd") or str(REPO))
    if tool == "Bash":
        command = tool_input.get("command", "")
        commands = split_commands(command)
        cwd = call.get("cwd") or str(REPO)
        # Leading cds into folders move the relative paths after them (an
        # agent's cwd resets every call): the path rules' writes; any other
        # shape is judged both where the session is and in every folder a cd
        # names. cd takes `..` after `~` and before symlinks (normpath), as the
        # shell does; a cd into no folder fails, and the shell stays where it was
        is_cd = lambda c: len(c[1]) == 2 and c[1][0] == "cd" and c[1][1].startswith(("/", "~"))
        cds = list(itertools.takewhile(is_cd, commands))
        targets = [str(t) for _, argv in filter(is_cd, commands)
                   if (t := resolve(os.path.normpath(os.path.expanduser(argv[1])), cwd)).is_dir()]
        cwds = [cwd, *targets]
        if (cds and LEADING_CD.fullmatch(command)
                and all(argv[0] == ">" or argv[0] not in MOVES and shutil.which(argv[0]) for _, argv in commands[len(cds):])):
            cwds = [targets[-1]] if targets else [cwd]
            commands = commands[len(cds):]
        for env, argv in commands:
            for where in cwds:
                check_argv(env, argv, where, guarded)
    elif tool in {"Edit", "Write"}:
        if tool_input.get("file_path"):
            check_guard_paths([tool_input["file_path"]], [], "/", {}, guarded)
        check_generated_edit(tool_input)
        check_config_edit(tool, tool_input)
        check_default_apps_edit(tool_input)
        check_portal_config_edit(tool_input)


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
