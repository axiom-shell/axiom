#!/usr/bin/env python3
"""PreToolUse guard: refuses the tool calls AGENTS.md › "Never, while testing"
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
runs, and a `>`/`>>` redirection as a write to its target. Best effort: it
stops mistakes, not an adversary.
"""
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
HOME = Path(os.path.expanduser("~")).resolve()
# The live config.json (DataDirs.xdg)
LIVE_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config").resolve() / "axiom/config.json"
SCHEMA = REPO / "config/json/config.schema.json"
PUNCTUATION = ";&|()<>`"
# Words that start a command without being its name
KEYWORDS = {"if", "then", "else", "elif", "while", "until", "do", "!", "{", "}"}
# Wrappers and their options that take a value (`sudo -u me`); timeout and
# flock take one positional (the duration, the lock file) before the command
WRAPPERS = {
    "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "-T"}, "pkexec": {"--user"},
    "env": {"-u", "-C", "--unset", "--chdir"}, "nohup": set(), "exec": {"-a"}, "command": set(), "time": set(),
    "setsid": set(), "timeout": {"-s", "-k", "--signal", "--kill-after"}, "nice": {"-n", "--adjustment"},
    "ionice": {"-c", "-n", "-p", "--class", "--classdata"}, "flock": {"-w", "-E", "--timeout", "--conflict-exit-code"},
    "systemd-run": {"-u", "--unit", "-p", "--property", "-E", "--setenv", "--uid", "--gid", "--slice", "-M", "--machine",
                    "--description", "--working-directory"},
}
WRAPPER_POSITIONALS = {"timeout": 1, "flock": 1}
# A substitution a double-quoted word still runs: "$(…)", "`…`"; single-quoted
# text (a commit message, a grep pattern) runs nothing, so it's blanked first
SUBSTITUTION = re.compile(r"\$\((.*)\)|`([^`]*)`", re.S)
QUOTED = re.compile(r"""\\.|"(?:\\.|[^"\\])*"|'[^']*'""", re.S)
SHELLS = {"bash", "sh", "zsh"}
QS = {"qs", "quickshell"}
QS_VALUE_OPTS = {"-c", "--config", "-p", "--path", "-m", "--manifest", "-i", "--id", "--pid", "--log-rules", "-n", "--newest"}
SAFE_QS = {"ipc", "log", "list", "msg"}


class Denied(Exception):
    pass


def deny(rule, why):
    raise Denied(f"Blocked by AGENTS.md › {rule}: {why}")


# --------------------------------------------------------------- parsing

def lex(command):
    try:
        lexer = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=PUNCTUATION)
        lexer.whitespace_split = True
        return list(lexer)
    except ValueError:
        return command.split()


# `<<WORD`, `<<-WORD`, `<<'WORD'` (not a `<<<` here-string, nor a `<<` inside
# a quoted string, which the other branches consume)
HEREDOC = re.compile(r"""(?<!<)<<(?!<)(-?)[ \t]*(['"]?)([A-Za-z_][\w.-]*)\2(?![^\s;&|<>()])|\\.|"(?:\\.|[^"\\])*"|'[^']*'""")


def drop_heredoc_bodies(command):
    """A heredoc's body is text, not commands: it is dropped, unless the
    command runs text it's given (a shell, `source`, `.`, `eval` or a script run
    by its path anywhere outside the bodies: `bash <<EOF`, `cat <<EOF | sh`,
    `cat > x.sh <<EOF … bash x.sh` or `… ./x.sh`), the body is unquoted and substitutes (`$(…)`, backticks) or
    its delimiter never comes: then it is judged as written."""
    lines, out = command.replace("\\\n", "").split("\n"), []
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
    # `.` or a script run by its path (`./t.sh`, `sudo /tmp/t.sh`) where a command starts, not a redirection's target
    runs = any(Path(w).name in SHELLS | {"source", "eval"} or (w == "." or "/" in w)
               and (not i or words[i - 1] in KEYWORDS | WRAPPERS.keys() or set(words[i - 1]) <= set(";&|()`"))
               for i, w in enumerate(words))
    return command if runs else "\n".join(out)


def split_commands(command):
    """[(env, argv)] for each simple command in a shell command line; a
    redirection `> f` is a command of its own, `[">", f]`."""
    command = drop_heredoc_bodies(command)
    tokens = lex(command)
    out, current, exported = [], [], {}
    for token in lex(QUOTED.sub(lambda m: "''" if m[0][0] == "'" else m[0], command)):
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
    # A script run through a shell (`bash scripts/greeter/greeter_install.sh …`): judge the script
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


def live_config_path(path, cwd, env):
    """Whether `path` is a live config folder or inside one (or HOME itself),
    as written and with its links followed; a scratch dir inside the repo isn't."""
    expanded = os.path.expanduser(expand_vars(path, env))
    written = Path(os.path.normpath(expanded if os.path.isabs(expanded) else os.path.join(cwd, expanded)))
    for target in {written, resolve(path, cwd, env)}:
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


def axiom_flag(args, flag):
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(flag + "="):
            return a.split("=", 1)[1]
    return ""


def axiom_live_display(env, args):
    """Whether an axiom command reaches the live session's daemon."""
    socket = axiom_flag(args, "--socket") or env.get("AXIOM_SOCKET", "")
    if socket:
        return not scratch(socket) or resolve(socket, "/").is_relative_to(Path(LIVE_RUNTIME))
    runtime = env.get("XDG_RUNTIME_DIR", "")
    return not runtime or resolve(runtime, "/") == Path(LIVE_RUNTIME)


def axiom_words(args):
    """The subcommand words of an axiom command line, flags left out."""
    words, skip = [], False
    for a in args:
        if skip:
            skip = False
            continue
        if a in AXIOM_VALUE_OPTS:
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
        deny("Running / reloading", f"`axiom {sub}` starts or stops the live shell; never from this session (test with a scratch XDG_RUNTIME_DIR, or nested.sh).")
    if live and sub == "daemon" and words[1:2] and words[1] in {"stop", "restart", "reexec"}:
        deny("Running / reloading", f"`axiom daemon {words[1]}` stops or replaces the live daemon; never from this session.")
    if live and sub == "dev" and words[1:2] and words[1] in {"on", "off", "rebuild"}:
        deny("Running / reloading", f"`axiom dev {words[1]}` switches dev mode or re-execs the live daemon; ask the user (`axiom dev status` reads it).")
    if live and (sub == "lock" or sub == "ipc" and words[1:2] == ["lockscreen"]):
        deny("Never, while testing", "don't lock the session; only the user can type the password (lock a scratch instance: XDG_RUNTIME_DIR=<scratch>).")
    if live and sub == "ipc" and words[1:3] in (["monitors", "keep"], ["selfUpdate", "update"]):
        deny("Never, while testing", f"`{' '.join(words[1:3])}` changes the live system; ask the user.")
    if sub == "greeter":
        gdir = axiom_flag(args, "--dir") or env.get("AXIOM_GREETER_DIR", "")
        installed = gdir and "$" not in gdir and resolve(gdir, "/") == Path("/var/lib/axiom-greeter")
        shown = env.get("AXIOM_GREETER_WINDOWED") == "1" or "--no-shell" in args
        if not shown or not scratch(gdir) or installed:
            deny("Never, while testing", "run the greeter only windowed on a scratch folder: AXIOM_GREETER_WINDOWED=1 AXIOM_COMPOSITOR=none axiom greeter --dir <scratch> (or --no-shell).")
    # The greeter installer's root side, which greeter_install.sh runs
    if sub == "greeter-install" and words[1:2] and words[1] in {"install", "update", "uninstall"}:
        if not scratch(env.get("AXIOM_GREETER_ROOT", "")):
            deny("Never, while testing", "axiom greeter-install install/update/uninstall only with a scratch AXIOM_GREETER_ROOT=<dir>.")
    # A compositor claim (managed mode) on the live config, or moving binds
    # out of its files (the bind merge's remove)
    if sub == "compositor" and words[1:2] and words[1] in {"claim", "release"} and words[2:3]:
        if live_config_path(words[2], cwd, env):
            deny("Never, while testing", f"`axiom compositor {words[1]}` only on a scratch dir, never the live compositor config.")
    if sub == "compositor" and words[1:3] == ["binds", "remove"] and words[3:4]:
        if live_config_path(words[3], cwd, env):
            deny("Never, while testing", "`axiom compositor binds remove` only on a scratch dir, never the live compositor config.")
    if sub == "config" and "--takeover" in args:
        config_dir = axiom_flag(args, "--config-dir") or env.get("XDG_CONFIG_HOME", "")
        if not scratch(config_dir) or live:
            deny("Never, while testing", "`--takeover` changes a setting that takes something over on this PC (compositor mode, locker, idle, polkit, greeter); ask the user.")


def gh_api_opens_issue(args):
    """`gh api` creating an issue: GraphQL's createIssue, or a POST to a repo's
    issues (gh posts when given a field, -f/-F/--input, unless told GET)."""
    if any("createIssue" in a for a in args):
        return True
    if not any(re.fullmatch(r"/?repos/[^/]+/[^/]+/issues/?", a) for a in args):
        return False
    method = next((m.group(1) for m in (re.fullmatch(r"(?:-X|--method)=?(\w+)", a) for a in args) if m), None)
    method = method or next((b for a, b in zip(args, args[1:]) if a in {"-X", "--method"}), None)
    if method:
        return method.upper() == "POST"
    return any(re.match(r"(-[fF]|--field|--raw-field|--input)", a) for a in args)


# ----------------------------------------------------------------- rules

GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
PROTECTED_BRANCHES = {"main", "master"}


def current_branch(cwd):
    out = subprocess.run(["git", "-C", cwd, "symbolic-ref", "--quiet", "--short", "HEAD"], capture_output=True, text=True)
    return out.stdout.strip()


def check_git(args, cwd):
    """`git push` that force-pushes, deletes or mirrors, or lands on main: every
    change reaches main through a reviewed PR (docs/dev/roadmap.md ›
    Running it unattended). `git clean -x`, which deletes the ignored files."""
    i = 0
    while i < len(args) and args[i].startswith("-"):
        if args[i] == "-C" and i + 1 < len(args):
            cwd = str(resolve(args[i + 1], cwd))
        i += 2 if args[i] in GIT_VALUE_OPTS else 1
    rule = "Never, while testing"
    if args[i:i + 1] == ["clean"] and any(re.fullmatch(r"-[a-zA-Z]*[xX][a-zA-Z]*", a) for a in args[i + 1:]):
        deny(rule, "`git clean -x`/`-X` deletes the generated files and local state; remove the files you mean by name (`git clean -fd` is fine).")
    if args[i:i + 1] != ["push"]:
        return
    push = args[i + 1:]
    if any(a in {"-f", "--force", "--mirror", "--delete", "-d", "--force-if-includes"} or a.startswith("--force-with-lease")
           or re.fullmatch(r"-[a-zA-Z]*f[a-zA-Z]*", a) for a in push):
        deny(rule, "don't force-push, delete or mirror remote branches; push a new commit instead.")
    refspecs = [a for a in push if not a.startswith("-")][1:]
    for spec in refspecs:
        dest = spec.split(":", 1)[-1]
        if spec.startswith("+") or spec.startswith(":"):
            deny(rule, "don't force-push or delete a remote branch.")
        if dest.removeprefix("refs/heads/") in PROTECTED_BRANCHES or dest == "HEAD" and current_branch(cwd) in PROTECTED_BRANCHES:
            deny(rule, "don't push to main; open a PR from a branch.")
    if not refspecs and current_branch(cwd) in PROTECTED_BRANCHES:
        deny(rule, "don't push to main; open a PR from a branch.")


def check_argv(env, argv, cwd):
    name = Path(argv[0]).name
    args = argv[1:]

    # Lock the built-in locker
    if name == "loginctl" and any(a.startswith("lock-session") for a in args):
        deny("Never, while testing", "don't lock the session; only the user can type the password. Test LockSurface in a hidden window.")
    if name == "hyprlock":
        deny("Never, while testing", "don't lock the screen; only the user can type the password.")

    # Simulate cursor movement
    if name in {"ydotool", "dotool", "dotoolc", "wlrctl"} or any("movecursor" in a or "cursor.move" in a for a in argv):
        deny("Never, while testing", "don't simulate cursor movement; check logs and reason through bindings, or ask the user to look.")

    # The shell itself, and its IPC
    if name in QS:
        check_qs(env, args)

    # The axiom binary: it is the shell's parent and its command line
    if name == "axiom":
        check_axiom(env, args, cwd)

    # Opening a GitHub issue: problems go in docs/dev/issues.md
    opens = any(args[i:i + 2] == ["issue", "create"] for i in range(len(args)))
    if name == "gh" and (opens or args[:1] == ["api"] and gh_api_opens_issue(args[1:])):
        deny("Never, while testing", "don't open GitHub issues; record the problem in docs/dev/issues.md and tell the user.")

    # Rewriting history on the remote, pushing to main past a PR, or git clean -x
    if name == "git":
        check_git(args, cwd)

    # Greetd
    if name in {"systemctl", "service", "pkill", "killall"} and any("greetd" in a for a in args):
        if name in {"pkill", "killall"} or any(a in {"restart", "stop", "start", "reload", "kill", "disable", "enable", "mask", "try-restart", "reload-or-restart"} for a in args):
            deny("Never, while testing", "don't restart or stop greetd: it ends the session.")

    # Greeter install / update / uninstall
    if name == "greeter_install.sh" and args and args[0] in {"install", "update", "uninstall"}:
        if not scratch(env.get("AXIOM_GREETER_ROOT", "")):
            deny("Never, while testing", "greeter_install.sh install/update/uninstall only with a scratch AXIOM_GREETER_ROOT=<dir>.")

    # Ending, reconfiguring or swapping the config of the niri session
    # itself: only a nested niri (NIRI_SOCKET aimed at another one than the
    # session's own) may be told to
    if name == "niri" and args[:1] == ["msg"]:
        rest = [a for a in args[1:] if a not in {"-j", "--json"}]
        changes = rest[:1] == ["output"] or (rest[:1] == ["action"] and rest[1:2] in (["quit"], ["load-config-file"]))
        socket = env.get("NIRI_SOCKET", os.environ.get("NIRI_SOCKET", ""))
        if changes and (not socket or socket == os.environ.get("NIRI_SOCKET", "")):
            deny("Never, while testing", "niri msg output / action quit / load-config-file only on a nested niri (NIRI_SOCKET=<its socket>), never the live session.")

    # A hookup's Apply (the daemon's hookup.apply, which edits the configs
    # of the HOME the daemon runs with) sent to the live daemon by hand:
    # only to a scratch one (XDG_RUNTIME_DIR / AXIOM_SOCKET)
    sends = name in {"socat", "nc", "ncat", "websocat", "echo", "printf", "axiom"} or name.startswith("python")
    if sends and any("hookup.apply" in a for a in args) and axiom_live_display(env, args):
        deny("Never, while testing", "hookup.apply only to a scratch daemon (XDG_RUNTIME_DIR=<scratch>), never the live one: it edits the real configs (test it with go test ./internal/compositor/edit).")

    # A self-update (the daemon's selfupdate.apply, which updates the tree
    # the daemon runs from: the live repo) sent to the live daemon by hand
    if sends and any("selfupdate.apply" in a for a in args) and axiom_live_display(env, args):
        deny("Never, while testing", "selfupdate.apply only to a scratch daemon (XDG_RUNTIME_DIR=<scratch>), never the live one: it updates the live repo (test it with go test ./internal/selfupdate).")

    # The login screen's install, update or uninstall (the daemon's
    # greeter.apply, which runs the installer as root through pkexec) sent
    # to the live daemon by hand
    if sends and any("greeter.apply" in a for a in args) and axiom_live_display(env, args):
        deny("Never, while testing", "greeter.apply only to a scratch daemon (XDG_RUNTIME_DIR=<scratch>), never the live one: it installs the greeter for real (test it with go test ./internal/greeterinstall).")

    # The real config.json: deleted or moved (the file or a folder above it)
    paths = [a for a in args if not a.startswith("-")]
    holding = {LIVE_CONFIG, *LIVE_CONFIG.parents}
    deletes = name in {"rm", "unlink", "trash", "trash-put", "shred", "mv"}
    if name == "find" and any(a == "-delete" or a in {"-exec", "-execdir"} and Path(b).name in {"rm", "shred", "unlink"}
                              for a, b in zip(args, args[1:] + [""])):
        deletes, paths = True, args[:next((i for i, a in enumerate(args) if a[:1] in {"-", "(", "!"}), len(args))]
    for a in (paths[:-1] if name == "mv" else paths) if deletes else []:
        if resolve(a, cwd, env) in holding:
            deny("Never, while testing", f"don't delete or move the real config.json ({LIVE_CONFIG}) or a folder holding it; use `axiom ipc onboarding goTo <n>`.")
    # ... or written by Bash, which skips the x-takeover check Edit and Write get
    if name in {"cp", "mv", "install"} and len(paths) > 1:
        written = [paths[-1]]
    elif name == ">" or name == "tee":
        written = paths
    elif name == "sed" and any(a.startswith("--in-place") or re.fullmatch(r"-[a-zA-Z]*i\S*", a) for a in args):
        written = paths
    else:
        written = []
    for a in written:
        target = resolve(a, cwd, env)
        if target == LIVE_CONFIG or target == LIVE_CONFIG.parent and any(Path(p).name == LIVE_CONFIG.name for p in paths[:-1]):
            deny("Never, while testing", f"don't write the real config.json ({LIVE_CONFIG}) from Bash, which skips the x-takeover check; use Edit/Write or `axiom config set`.")

    # qmlformat -i replaces the inode
    if name == "qmlformat" and any(a in {"-i", "--inplace"} for a in args):
        deny("Formatting", "qmlformat -i replaces the file's inode, so qs stops reloading it; verify.sh formats in place.")



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
        deny("Running / reloading", "the shell runs detached; never stop it from this session (`qs kill` only the greeter instance you started: `qs kill -p <…>/greeter.qml` or `-i <id>`).")
    if sub is None:
        if greeter:
            return
        deny("Running / reloading", "the shell runs detached; never start another from this session (the windowed greeter: AXIOM_GREETER_WINDOWED=1 axiom greeter --dir <scratch>).")


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
            deny("Never, while testing", f"`{'.'.join(path)}` takes something over on this PC (x-takeover: compositor mode, locker, idle, polkit, greeter). Ask the user before changing it in the live config.")


# ------------------------------------------- Edit/Write generated or frozen

# Files built from a source (edit the source) and frozen ones (never edit)
GENERATED = {
    REPO / "config/json/config.schema.json": "it's built from config/schema/ (edit the YAML there; scripts/generate.sh rebuilds it)",
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
        deny("Checks", f"`{resolved.relative_to(REPO)}` is generated: {GENERATED[resolved]}.")
    if resolved in FROZEN:
        deny("Checks", f"`{resolved.relative_to(REPO)}` is frozen: {FROZEN[resolved]}.")
    for generated, why in GENERATED_DIRS.items():
        if resolved.is_relative_to(generated):
            deny("Checks", f"`{resolved.relative_to(REPO)}` is generated: {why}.")


# ------------------------------------------------------------------ main

def check(call):
    tool, tool_input = call.get("tool_name", ""), call.get("tool_input") or {}
    if tool == "Bash":
        for env, argv in split_commands(tool_input.get("command", "")):
            check_argv(env, argv, call.get("cwd") or str(REPO))
    elif tool in {"Edit", "Write"}:
        check_generated_edit(tool_input)
        check_config_edit(tool, tool_input)


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
