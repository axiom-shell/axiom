#!/usr/bin/env python3
"""Tests for .claude/hooks/guard.py, the PreToolUse guard enforcing
AGENTS.md › "Never, while testing". Run: python3 tests/scripts/test_guard.py"""
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parent.parent.parent
spec = importlib.util.spec_from_file_location("guard", REPO / ".claude/hooks/guard.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

HOME = str(guard.HOME)


def denied(command, cwd=str(REPO)):
    try:
        guard.check({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": cwd})
    except guard.Denied:
        return True
    return False


class LiveSession:
    """Pins the session the guard sees, whatever the one running the tests exports"""

    def setUp(self):
        # The live session: wayland-1's daemon in /run/user/1000, no inherited $AXIOM_SOCKET
        self.patches = [mock.patch.object(guard, "LIVE_RUNTIME", "/run/user/1000"),
                        mock.patch.object(guard, "LIVE_DISPLAY", "wayland-1"),
                        mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/1000", "WAYLAND_DISPLAY": "wayland-1"})]
        for p in self.patches:
            p.start()
        os.environ.pop("AXIOM_SOCKET", None)

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()


class Bash(LiveSession, unittest.TestCase):
    def blocks(self, *commands):
        for command in commands:
            self.assertTrue(denied(command), command)

    def allows(self, *commands):
        for command in commands:
            self.assertFalse(denied(command), command)

    def test_ordinary_commands_pass(self):
        self.allows("scripts/dev/verify.sh", "git status && git diff HEAD", "axiom ipc overlay toggle",
                    "scripts/log.sh -g lock", "axiom log -f", "grep -rn 'lockscreen lock' docs", "echo 'qs kill'", "qs log -f")

    def test_compound_commands(self):
        self.blocks("(qs kill)", "{ qs kill; }", "echo $(qs kill)", "x=`qs kill`", "if true; then qs kill; fi",
                    "while true; do axiom lock; done", "! axiom lock", "true && (cd /tmp; axiom lock) > /dev/null 2>&1",
                    'x="$(axiom lock)"', 'echo "`qs kill`"', 'x="$(axiom ipc lockscreen "lock")"',
                    """bash -c 'echo "$(axiom lock)"'""")
        self.allows("(cd docs && ls)", "echo $(date)", "if true; then echo ok; fi", "{ git status; git log -1; } | head",
                    'x="$(git rev-parse HEAD)"', "git commit -m 'never run `axiom lock`'", "grep -n '$(qs kill)' docs",
                    'git commit -m "never run \\`axiom lock\\`"', """echo "don't" '`axiom lock`'""",
                    "go test ./... 2>&1 | tail -3")

    def test_every_rule_holds_in_compound_forms(self):
        """Each AGENTS.md › Never rule's plain form, inside a group, after &&,
        in a substitution or an if, behind a wrapper or an assignment."""
        call = """'{"jsonrpc":"2.0","id":1,"method":"%s","params":{}}'"""
        rules = ["loginctl lock-session", "hyprlock", "ydotool mousemove 1 1", "hyprctl dispatch movecursor 1 1",
                 "axiom compositor claim --kind sway ~/.config/sway h", "axiom compositor binds remove --kind sway ~/.config/sway x",
                 "axiom config set Idle.enabled on --takeover", "axiom ipc monitors keep", "axiom ipc selfUpdate update",
                 f"rm {guard.LIVE_CONFIG}", f"cp /tmp/x.json {guard.LIVE_CONFIG}", "niri msg action quit",
                 f"python3 -c {call % 'hookup.apply'}", f"python3 -c {call % 'selfupdate.apply'}",
                 f"python3 -c {call % 'greeter.apply'}", f"python3 -c {call % 'inputMethod.push'}",
                 "busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Restart", f"python3 -c {call % 'dev.config.copy'}", "axiom greeter-install install . me", "axiom greeter --dir /tmp/g",
                 "systemctl restart greetd", "axiom quit", "axiom daemon stop", "axiom dev on", "axiom lock",
                 "axiom ipc lockscreen lock", "qs kill", "gh api repos/o/r", "git push --force", "git push origin main",
                 "git clean -fdx", "qmlformat -i shell.qml"]
        forms = ["( {} )", "true && {}", "{{ {}; }}", "echo $({})", "if true; then {}; fi", "sudo -u me {}",
                 "nice -n 5 {}", "FOO=1 {}"]
        with mock.patch.dict(os.environ, {"NIRI_SOCKET": "/run/user/1000/niri.wayland-1.100.sock"}):
            for rule in rules:
                self.blocks(rule, *(form.format(rule) for form in forms))

    def test_wrapper_options(self):
        self.blocks("sudo -u me axiom lock", "nice axiom lock", "nice -n 5 axiom lock", "flock /tmp/l axiom lock",
                    "flock -w 5 /tmp/l axiom lock", "flock /tmp/l -c 'axiom lock'", "systemd-run --user axiom quit", "systemd-run --user -u x axiom quit",
                    "ionice -c 3 qs kill", "timeout -s INT 5 axiom lock", "env -u FOO axiom lock")
        self.allows("nice -n 5 go test ./...", "flock /tmp/l scripts/dev/verify.sh", "timeout 5 axiom ping")

    def test_locking(self):
        self.blocks("loginctl lock-session", "sleep 1 && hyprlock", "bash -c 'axiom ipc lockscreen lock'")

    def test_cursor(self):
        self.blocks("ydotool mousemove 10 10", "hyprctl dispatch movecursor 10 10", "wlrctl pointer move 5 5",
                    "hyprctl eval 'hl.dsp.cursor.move(1, 1)'")

    def test_shell_lifecycle(self):
        self.blocks("qs kill", "qs -c axiom kill", "qs -c axiom", "qs -c axiom -d", "quickshell -p qml/shell.qml &")
        self.allows('AXIOM_GREETER=1 AXIOM_GREETER_WINDOWED=1 AXIOM_GREETER_DIR=/tmp/g qs -p "$PWD/qml/greeter.qml"',
                    'qs kill -p "$PWD/qml/greeter.qml"', "qs kill -i abc123", "qs list")

    def test_gh_allowlist(self):
        self.blocks("gh api repos/o/r", "gh api -X GET repos/o/r/issues", "gh api graphql -f query='{ viewer { login } }'",
                    "gh repo edit --default-branch dev", "gh release create v1", "gh workflow disable ci.yml",
                    "gh secret set X", "gh label create x", "gh issue delete 3", "gh run delete 5", "gh frobnicate", "gh co 12", "gh pr merge 3 --admin",
                    "cd /tmp && gh api repos/o/r", "true; env GH_TOKEN=x gh repo edit --default-branch dev",
                    "git status && gh api -X DELETE repos/a/b/branches/main/protection", "echo x | gh api graphql --input -", "gh pr merge 3 --admin=true",
                    "echo 1 | xargs gh api", "echo 1 | xargs -I {} -n 1 gh api repos/o/r/issues/{}",
                    "gh api repos/o/r -X DELETE -H --help", "gh repo --description view edit", "gh --method DELETE api repos/o/r")
        self.allows("gh pr create --fill --label roadmap", "gh pr view 3 --json comments", "gh pr list --label roadmap",
                    "gh pr checks 1 --watch | tail -3", "gh pr merge 3 --squash --delete-branch", "gh pr edit 3 --add-label x",
                    "gh pr comment 3 -b ok", "gh pr close 3", "gh pr ready 3", "gh pr checkout 3", "gh version", "gh run view --log-failed | tail -60", "gh run rerun 9 --failed",
                    "gh run cancel 9", "gh issue list", "gh issue view 16", "gh issue comment 16 -b x", "gh issue close 16",
                    "gh issue edit 16 --add-label x", "gh repo view", "gh release list", "gh label list", "gh rs check main",
                    "gh ruleset view 42", "gh search prs x", "gh status", "gh auth status", "gh variable get X",
                    "gh issue create --title x --body y", "gh -R a/b issue create -t x -b y", "gh -R x/y pr view 1", "gh pr view 1 --repo x/y", "gh --repo=x/y run list",
                    "cd /tmp && gh pr view 1", "env GH_TOKEN=x gh pr list", "echo 1 | xargs -I {} gh pr view {}",
                    "gh repo clone o/r", "gh workflow run checks.yml --ref roadmap/x", "gh", "gh help repo edit", "gh repo edit --help", "gh api -h", "gh api --help")

    def test_leading_cd(self):
        """A leading `cd` moves the relative paths after it"""
        with tempfile.TemporaryDirectory() as tmp, tempfile.TemporaryDirectory() as other:
            cfg = Path(tmp) / "axiom"
            (cfg / "sub").mkdir(parents=True)
            with mock.patch.object(guard, "LIVE_CONFIG", cfg / "config.json"):
                self.blocks(f"cd {cfg} && cp /tmp/x config.json", f"cd {cfg} && rm config.json",
                            f"cd {cfg}/sub/.. && cat x > config.json 2>&1 | tail -1", f"cd {tmp} && rm -r axiom")
                self.allows(f"cd {other} && cp /tmp/x config.json")

    def test_leading_cd_then_semicolon_or_more_cds(self):
        """`cd /dir;`, a newline or several leading cds move them the same as `&&`"""
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "axiom"
            cfg.mkdir()
            with mock.patch.object(guard, "LIVE_CONFIG", cfg / "config.json"):
                self.blocks(f"cd {cfg}; rm config.json", f"cd {cfg}\nrm config.json", f"cd /tmp && cd {cfg} && rm config.json",
                            f"cd {cfg}; cd {tmp}/none; rm config.json")
                self.allows(f"cd {cfg}; cd /tmp; rm config.json", f"cd {cfg} && cd /tmp && rm config.json")

    def test_git_push_and_clean(self):
        self.blocks("git push", "git push origin", "git push -u origin HEAD", "git push origin HEAD:roadmap/1-x", "git push origin @",
                    "git push --force", "git push -f origin x", "git push -uf origin x", "git push --force-with-lease origin x",
                    "git push --force-if-includes origin x", "git push origin +x", "git push origin :x", "git push --delete origin x",
                    "git push -d origin x", "git push --mirror origin", "git push --all origin", "git push --prune origin x",
                    "git push --tags origin x", "git push upstream x", "git push -v origin x", "git push origin x y",
                    "git push origin main", "git push origin master", "git push origin x:main", "git push origin x:refs/heads/main",
                    "git push origin x:heads/main", "git push origin refs/heads/main", "git push origin v1.0", "git push origin x:refs/tags/y",
                    "git -C . push --force origin x", "git -C /tmp push", "env -C /tmp git push",
                    'git push -u origin "$(git branch --show-current)"', 'b=main; git push origin "$b"', "git push origin x@{u}",
                    "cd /tmp && git push -u origin HEAD 2>&1 | tail -2",
                    # a switch, rebase or rename onto main, then a bare push
                    "git switch main && git push", "git rebase roadmap/1-x main && git push", "git branch -M main && git push",
                    "git clean -fdx", "git clean -X", "git -C . clean -x -f")
        self.allows("git push -u origin roadmap/1-x", "git push --set-upstream origin x", "git push -q -n origin x",
                    "git push --dry-run origin x", "git push origin x:roadmap/1-x", "git push origin main:x",
                    "git -C /tmp/w push -u origin roadmap/1-x", "cd /tmp && git push -u origin roadmap/1-x 2>&1 | tail -2",
                    "git switch main && git push origin roadmap/1-x", "env -C /tmp git push origin x",
                    "git status", "git pull --ff-only", "git clean -fd", "git clean -n")

    def test_greetd_and_greeter(self):
        self.blocks("sudo systemctl restart greetd", "systemctl stop greetd.service", "pkill greetd",
                    "data/greeter/greeter_install.sh install . me")
        self.allows("systemctl status greetd", "data/greeter/greeter_install.sh check .",
                    "AXIOM_GREETER_ROOT=/tmp/x data/greeter/greeter_install.sh install . me",
                    'export AXIOM_GREETER_ROOT="$tmp"; data/greeter/greeter_install.sh uninstall . me')

    def test_compositor_claim(self):
        self.blocks(f"axiom compositor claim --kind sway -- {HOME}/.config/sway '# axiom'",
                    "axiom compositor release --kind hyprland -- ~/.config/hypr '-- h' f",
                    "axiom compositor claim ~/.config/niri h --kind niri", "axiom --json compositor release --kind=sway ~/.config/sway h f")
        self.allows("axiom compositor claim --kind sway -- /tmp/scratch/sway '# axiom'",
                    "axiom compositor check --kind hyprland -- ~/.config/hypr '-- axiom'")

    def test_merge_binds(self):
        self.blocks("axiom compositor binds remove --kind sway ~/.config/sway '[]'",
                    f"axiom compositor binds remove --kind=hyprland {HOME}/.config/hypr '[]'")
        self.allows("axiom compositor binds extract --kind sway ~/.config/sway",
                    "axiom compositor binds remove --kind sway /tmp/scratch/sway '[]'")

    def test_niri_session(self):
        with mock.patch.dict(os.environ, {"NIRI_SOCKET": "/run/user/1000/niri.wayland-1.100.sock"}):
            self.blocks("niri msg action quit", "niri msg action load-config-file --path /tmp/x.kdl",
                        "niri msg output DP-1 off", "niri msg -j action quit")
            self.allows("niri msg -j windows", "niri msg action focus-workspace 2",
                        "NIRI_SOCKET=/run/user/1000/niri.wayland-2.200.sock niri msg action quit",
                        "export NIRI_SOCKET=/run/user/1000/niri.wayland-2.200.sock; niri msg output winit scale 1")

    def test_scripts_run_through_a_shell_and_variables(self):
        self.blocks("bash data/greeter/greeter_install.sh install . me")
        self.assertTrue(denied("axiom compositor claim --kind sway $HOME/.config/sway axiom", cwd="/tmp"))
        self.assertTrue(denied("axiom compositor claim --kind sway ${HOME}/.config/sway axiom", cwd="/tmp"))
        self.assertTrue(denied("export D=~/.config/hypr; axiom compositor binds remove --kind hyprland $D '[]'", cwd="/tmp"))
        self.blocks("bash -lc 'qs -c axiom kill'")
        self.allows("axiom compositor claim --kind sway scratch/sway axiom", "bash data/greeter/greeter_install.sh check .")

    def test_heredoc_bodies(self):
        """A heredoc's body is judged only when the command could run it (a shell, source, ., eval) or it substitutes."""
        self.allows("python3 - <<'PY'\nprint('axiom lock')\naxiom lock\nPY", "cat > notes <<EOF\naxiom lock\nqs kill\nEOF",
                    "cd /tmp && python3 - <<'PY'\naxiom lock\nPY\ngit status", "cat <<-EOF\n\taxiom lock\n\tEOF",
                    "cat <<EOF\n$(git rev-parse HEAD)\nEOF")
        self.blocks("bash <<EOF\naxiom lock\nEOF", "sh <<'EOF'\nqs kill\nEOF", "zsh <<-\"X\"\n\taxiom lock\n\tX",
                    "cd /tmp && bash -s <<'EOF'\naxiom lock\nEOF", "cat <<'EOF' | sh\naxiom lock\nEOF",
                    "python3 - <<'PY'\nx = 1\nPY\naxiom lock", "cat <<EOF\n$(axiom lock)\nEOF",
                    "cat <<A; bash <<B\ntext\nA\naxiom lock\nB")
        # A command that runs text it's given anywhere, a body that substitutes, a `<<` that isn't a heredoc
        self.blocks("eval \"$(cat)\" <<EOF\naxiom lock\nEOF", "cat <<EOF |\naxiom lock\nEOF\nsh", "cat <<EOF \\\n| sh\naxiom lock\nEOF",
                    "cat > x.sh <<'EOF'\naxiom lock\nEOF\nbash x.sh", "cat > x.sh <<'EOF'\naxiom lock\nEOF\n. ./x.sh",
                    "cat > x.sh <<'EOF'\naxiom lock\nEOF\nchmod +x x.sh && ./x.sh", "cat > /tmp/x <<'EOF'\naxiom lock\nEOF\nsudo /tmp/x",
                    "cat <<EOF\n$(\naxiom lock\n)\nEOF", "git commit -m \"a <<b\"\naxiom lock\nb", "echo 'x <<EOF'\naxiom lock\nEOF",
                    "echo $((1<<2))\naxiom lock\n2", "cat <<E'OF'\nx\nEOF\naxiom lock", "cat <<EOF\naxiom lock",
                    "bash <<< 'axiom lock'", "sh <<<\"qs kill\"")
        self.allows("git add . && git commit -F - <<'EOF'\naxiom lock\nEOF", "cat <<A <<B\naxiom lock\nA\nqs kill\nB",
                    "cat > /tmp/p.py <<'EOF'\naxiom lock\nEOF\npython3 /tmp/p.py", "cd /tmp && cat > out/n <<'EOF'\naxiom lock\nEOF",
                    # a path run that isn't the file the command writes
                    "cat > /tmp/p.py <<'EOF'\naxiom lock\nEOF\n/usr/bin/grep -n x /tmp/p.py",
                    "scripts/dev/verify.sh && git commit -F - <<'EOF'\naxiom lock\nEOF")

    def test_comments(self):
        """A `#` comment ends at its newline; `#` inside a word or quotes isn't one; an unbalanced quote keeps separators."""
        self.blocks("echo hi # note\naxiom lock", "# step 2\nqs kill", "git status # don't\naxiom lock",
                    "echo a#b; axiom lock", "echo \"#x\" && qs kill", "echo ${#v} && axiom lock",
                    "echo \"unbalanced; axiom lock", "echo it's && qs kill", "echo hi # a \\\naxiom lock")
        self.allows("echo hi # axiom lock", "# qs kill\ngit status", "git status  # then axiom lock; qs kill",
                    "echo '# x'\n# axiom lock")

    def test_comments_the_shell_may_read_differently(self):
        """A `<<` in a comment starts no heredoc; a quote this reads unlike the shell
        (`$'…'`, quotes nested in `"$(…)"`) can't hide what follows behind a comment."""
        self.blocks("echo # <<EOF\naxiom lock\nEOF", "echo $'\\' #'; axiom lock", "echo $'\\' #\n'; axiom lock\n'",
                    'echo "$(echo " #")"; axiom lock', f'cp /tmp/x "{guard.LIVE_CONFIG}" # don\'t',
                    "cat > /tmp/x.sh <<'EOF'\ndon't\nEOF\nbash /tmp/x.sh; echo ' #'; axiom lock")
        self.allows("git commit -F - <<'EOF'\nFix #12: don't lock\n\n# it's text\nEOF", "printf $'a\\tb'", "printf $'$(axiom lock)'",
                    "gh pr create --body \"$(cat <<'EOF'\n## Summary\n- don't break #241\nEOF\n)\"",
                    'git status # see "x"\ngit diff')

    def test_a_custom_xdg_config_home_is_live(self):
        with mock.patch.object(guard, "CONFIG_HOMES", guard.CONFIG_HOMES | {Path("/srv/conf")}):
            self.assertTrue(denied("axiom compositor claim --kind sway /srv/conf/sway axiom"))

    def test_hookup_apply(self):
        call = """'{"jsonrpc":"2.0","id":1,"method":"hookup.apply","params":{"key":"kitty"}}'"""
        self.blocks(f"python3 -c {call}", f"printf %s {call}", f"HOME=/tmp/h python3 -c {call}")
        self.allows(f"XDG_RUNTIME_DIR=/tmp/run python3 -c {call}", f"AXIOM_SOCKET=/tmp/run/axiom.sock printf %s {call}",
                    "grep -rn hookup.apply backend", "python3 -c 'hookup.status'")

    def test_self_update(self):
        call = """'{"jsonrpc":"2.0","id":1,"method":"selfupdate.apply","params":{"channel":"tags","target":"v1.2"}}'"""
        self.blocks(f"python3 -c {call}", f"printf %s {call}", "axiom ipc selfUpdate update")
        self.allows(f"XDG_RUNTIME_DIR=/tmp/run python3 -c {call}", "python3 -c 'selfupdate.check'",
                    "grep -rn selfupdate.apply backend", "go test ./internal/selfupdate")

    def test_dev_writes_sent_by_hand(self):
        call = """'{"jsonrpc":"2.0","id":1,"method":"%s","params":{}}'"""
        for method in ("dev.set", "dev.rebuild", "dev.config.copy", "dev.config.pull"):
            self.blocks(f"python3 -c {call % method}", f"printf %s {call % method}")
            self.allows(f"XDG_RUNTIME_DIR=/tmp/run python3 -c {call % method}", f"grep -rn {method} backend")
        self.allows(f"python3 -c {call % 'dev.config.diff'}", f"python3 -c {call % 'dev.get'}")

    def test_live_input_method(self):
        fcitx = "org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1"
        call = """'{"jsonrpc":"2.0","id":1,"method":"%s","params":{}}'"""
        self.blocks(f"busctl --user call {fcitx} SetConfig sv fcitx://config/global x",
                    f"busctl --user call {fcitx} Restart", f"busctl --user call {fcitx} SetInputMethodGroupInfo ssa(ss) Default us 0",
                    "dbus-send --session --dest=org.fcitx.Fcitx5 --type=method_call /controller org.fcitx.Fcitx.Controller1.Save",
                    "gdbus call --session -d org.fcitx.Fcitx5 -o /controller -m org.fcitx.Fcitx.Controller1.Exit",
                    f"busctl --user call {fcitx} AddInputMethodGroup s G", f"busctl --user call {fcitx} RemoveInputMethodGroup s G",
                    "gsettings set org.freedesktop.ibus.general preload-engines \"['mozc-jp']\"",
                    "gsettings reset org.freedesktop.ibus.panel custom-font", "dconf write /desktop/ibus/general/use-system-keyboard-layout true",
                    "axiom ipc inputMethod push x", f"python3 -c {call % 'inputMethod.push'}",
                    f"printf %s {call % 'inputMethod.options'}", f"python3 -c {call % 'inputMethod.framework'}")
        self.allows(f"busctl --user call {fcitx} CurrentInputMethod", f"busctl --user call {fcitx} FullInputMethodGroupInfo s Default",
                    f"busctl --user introspect {fcitx}", f"busctl --address=unix:path=/tmp/bus call {fcitx} SetConfig sv x y",
                    f"DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/bus busctl --user call {fcitx} Save",
                    "gsettings get org.freedesktop.ibus.general preload-engines",
                    "GSETTINGS_BACKEND=memory gsettings set org.freedesktop.ibus.general preload-engines \"[]\"",
                    "gsettings set org.gnome.desktop.interface color-scheme prefer-dark",
                    f"XDG_RUNTIME_DIR=/tmp/run python3 -c {call % 'inputMethod.push'}", f"python3 -c {call % 'inputMethod.get'}",
                    "grep -rn inputMethod.push backend", "go test ./internal/inputmethod")

    def test_greeter_install_command(self):
        self.blocks("axiom greeter-install install . me", "sudo axiom greeter-install uninstall . me",
                    "pkexec ~/.local/bin/axiom greeter-install update . me")
        self.allows("AXIOM_GREETER_ROOT=/tmp/x axiom greeter-install install . me", "axiom greeter-install --help",
                    "go test ./internal/greeterinstall")

    def test_greeter_apply(self):
        call = """'{"jsonrpc":"2.0","id":1,"method":"greeter.apply","params":{"action":"install"}}'"""
        self.blocks(f"python3 -c {call}", f"printf %s {call}")
        self.allows(f"XDG_RUNTIME_DIR=/tmp/run python3 -c {call}", "python3 -c 'greeter.status'",
                    "grep -rn greeter.apply backend", "go test ./internal/greeterinstall")

    def test_live_config_file(self):
        self.blocks(f"rm {guard.LIVE_CONFIG}", f"rm -rf {guard.LIVE_CONFIG.parent}", f"mv {guard.LIVE_CONFIG} /tmp/x",
                    "rm ~/.config/axiom/config.json" if not os.environ.get("XDG_CONFIG_HOME") else f"rm {guard.LIVE_CONFIG}",
                    )
        self.allows("rm /tmp/config.json", f"cp {guard.LIVE_CONFIG} /tmp/backup.json",
                    f"rm {guard.LIVE_CONFIG.parent}/saved/old.json", "git clean -fd", "mv /tmp/new.json /tmp/other.json")

    def test_bash_writes_onto_live_config(self):
        live = "~/.config/axiom/config.json" if not os.environ.get("XDG_CONFIG_HOME") else str(guard.LIVE_CONFIG)
        self.blocks(f"cp /tmp/x.json {live}", f"cp /tmp/config.json {guard.LIVE_CONFIG.parent}/", f"mv /tmp/x.json {live}",
                    f"install -m 644 /tmp/x.json {live}", f"echo '{{}}' > {live}", f"jq . /tmp/x >>{live}",
                    f"jq . /tmp/x | tee {live}", f"sed -i 's/a/b/' {live}", f"sed -Ei.bak 's/a/b/' {live}",
                    f"sed --in-place 's/a/b/' {live}", "rm -r ~/.config", f"rm -rf {guard.HOME}",
                    "find ~/.config/axiom -name config.json -delete", "find ~/.config -name '*.json' -exec rm {} +")
        self.allows(f"cat {live}", f"jq . {live}", f"jq .Bar {live} > /tmp/out.json", f"cp {live} /tmp/backup.json",
                    "cp /tmp/x.json /tmp/y.json", f"sed -n 1p {live}", f"diff {live} /tmp/x 2>/dev/null",
                    "find . -name '*.pyc' -delete", "find ~/.config -name '*.json' -exec grep -l Bar {} +")

    def test_machine_settings(self):
        """The clock, time zone, hostname, account and default apps change
        only on a scratch bus, a scratch daemon or a scratch config home."""
        call = """'{"jsonrpc":"2.0","id":1,"method":"%s","params":{}}'"""
        for method in guard.SYSTEM_WRITES:
            self.blocks(f"python3 -c {call % method}", f"printf %s {call % method}")
            self.allows(f"XDG_RUNTIME_DIR=/tmp/run python3 -c {call % method}", f"grep -rn {method} backend")
        self.allows(f"python3 -c {call % 'datetime.get'}", f"python3 -c {call % 'account.get'}",
                    f"python3 -c {call % 'apps.handlers'}", f"python3 -c {call % 'system.info'}")
        self.blocks("timedatectl set-timezone Europe/Berlin", "sudo timedatectl set-ntp false",
                    "hostnamectl set-hostname box", "hostnamectl hostname box", "passwd", "echo x | passwd --stdin",
                    "sudo usermod -c Name me", "chfn -f Name",
                    "busctl call org.freedesktop.timedate1 /org/freedesktop/timedate1 org.freedesktop.timedate1 SetNTP bb false false",
                    "gdbus call --system -d org.freedesktop.Accounts -o /org/freedesktop/Accounts/User1000 -m org.freedesktop.Accounts.User.SetIconFile /tmp/a.png",
                    "busctl set-property org.freedesktop.hostname1 /org/freedesktop/hostname1 org.freedesktop.hostname1 X s y")
        self.allows("timedatectl", "timedatectl status", "timedatectl list-timezones", "hostnamectl", "hostnamectl status",
                    "busctl introspect org.freedesktop.timedate1 /org/freedesktop/timedate1",
                    "busctl get-property org.freedesktop.timedate1 /org/freedesktop/timedate1 org.freedesktop.timedate1 Timezone",
                    "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/bus busctl call org.freedesktop.timedate1 / x SetNTP bb false false",
                    "go test ./internal/timedate", "grep -rn passwd backend")

    def test_default_apps_files(self):
        self.blocks("xdg-mime default firefox.desktop x-scheme-handler/http", "xdg-settings set default-web-browser firefox.desktop",
                    "cp /tmp/m ~/.config/mimeapps.list", "rm ~/.config/mimeapps.list", "sed -i s/a/b/ ~/.config/hyprland-mimeapps.list",
                    "echo x > ~/.config/xdg-terminals.list", "cp /tmp/mimeapps.list ~/.config/")
        self.allows("xdg-mime query default text/plain", "xdg-settings get default-web-browser", "cat ~/.config/mimeapps.list",
                    "XDG_CONFIG_HOME=/tmp/cfg xdg-mime default firefox.desktop text/html", "cp /tmp/m /tmp/cfg/mimeapps.list",
                    "cp ~/.config/mimeapps.list /tmp/backup.list")
        for path in (f"{HOME}/.config/mimeapps.list", f"{HOME}/.config/xdg-terminals.list"):
            with self.assertRaises(guard.Denied):
                guard.check({"tool_name": "Write", "tool_input": {"file_path": path, "content": "x"}})
        guard.check({"tool_name": "Write", "tool_input": {"file_path": "/tmp/cfg/mimeapps.list", "content": "x"}})

    def test_screen_share_portal(self):
        self.blocks("systemctl --user restart xdg-desktop-portal", "systemctl --user stop xdg-desktop-portal-hyprland.service",
                    "pkill xdg-desktop-portal", "killall xdg-desktop-portal-wlr",
                    "echo x >> ~/.config/hypr/xdph.conf", "cp /tmp/c ~/.config/xdg-desktop-portal-wlr/config",
                    "sed -i s/a/b/ ~/.config/xdg-desktop-portal/niri-portals.conf", "tee ~/.config/xdg-desktop-portal/portals.conf",
                    "cp /tmp/xdph.conf ~/.config/hypr/", "cp /tmp/niri-portals.conf ~/.config/xdg-desktop-portal/")
        self.allows("systemctl --user status xdg-desktop-portal", "cat ~/.config/hypr/xdph.conf",
                    "cp /tmp/c /tmp/cfg/hypr/xdph.conf", "cp ~/.config/hypr/xdph.conf /tmp/backup.conf",
                    "echo x > /tmp/cfg/xdg-desktop-portal/niri-portals.conf")
        for path in (f"{HOME}/.config/hypr/xdph.conf", f"{HOME}/.config/xdg-desktop-portal-wlr/config", f"{HOME}/.config/xdg-desktop-portal/niri-portals.conf"):
            with self.assertRaises(guard.Denied):
                guard.check({"tool_name": "Write", "tool_input": {"file_path": path, "content": "x"}})
        guard.check({"tool_name": "Write", "tool_input": {"file_path": "/tmp/cfg/hypr/xdph.conf", "content": "x"}})

    def test_qmlformat_inplace(self):
        self.blocks("qmlformat -i shell.qml", "/usr/lib/qt6/bin/qmlformat --inplace shell.qml")
        self.allows("/usr/lib/qt6/bin/qmlformat shell.qml")


class GuardItself(unittest.TestCase):
    """The guard's folder where the session runs and Claude's settings stay as
    they are; everything else (a worktree's .claude/, memory, reads) doesn't."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.project, self.config, self.worktree = root / "project", root / "claude-config", root / "worktree"
        for folder in (self.project / ".claude/hooks", self.config / "projects", self.worktree / ".claude/hooks"):
            folder.mkdir(parents=True)
        self.patch = mock.patch.dict(os.environ, {"CLAUDE_PROJECT_DIR": str(self.project), "CLAUDE_CONFIG_DIR": str(self.config)})
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.tmp.cleanup()

    def denied(self, tool, value, cwd=None):
        tool_input = {"command": value} if tool == "Bash" else {"file_path": value, "content": "x"}
        try:
            guard.check({"tool_name": tool, "tool_input": tool_input, "cwd": cwd or str(self.project)})
        except guard.Denied:
            return True
        return False

    def test_project_claude_folder_and_settings_refused(self):
        p, c = self.project, self.config
        for path in (p / ".claude/hooks/guard.py", p / ".claude/settings.json", p / ".claude/settings.local.json",
                     p / ".claude/skills/x/SKILL.md", p / ".claude/agents/a.md", c / "settings.json",
                     c / "settings.local.json", f"{HOME}/.claude/settings.json", p / "sub/../.claude/settings.json"):
            self.assertTrue(self.denied("Write", str(path)), path)
        for command in ("echo x > .claude/settings.json", "echo x >> .claude/hooks/guard.py", "cp /tmp/x .claude/settings.json",
                        "cp /tmp/settings.json .claude/", "mv /tmp/x .claude/hooks/guard.py", "rm .claude/hooks/guard.py",
                        "rm -rf .claude", f"rm -rf {p}", "mv .claude /tmp/old", "sed -i s/a/b/ .claude/hooks/guard.py",
                        "tee .claude/settings.local.json", "ln -sf /tmp/x .claude/settings.json", "chmod -x .claude/hooks/guard.py",
                        "truncate -s 0 .claude/hooks/guard.py", "install -m 644 /tmp/x .claude/settings.json",
                        f"cp /tmp/x {c}/settings.json", f"echo '{{}}' > {c}/settings.local.json", "rm ~/.claude/settings.json",
                        f"rm -rf {c}", "find .claude -name '*.py' -delete", f"cd {p}/.claude && rm settings.json",
                        "sudo cp /tmp/x .claude/settings.json", "bash -c 'echo x > .claude/settings.json'",
                        f"cd /tmp; cd {p}; rm .claude/settings.json"):
            self.assertTrue(self.denied("Bash", command), command)
        # A cd the guard doesn't follow, from a session elsewhere: judged in the folder it names too
        for command in (f"cd {p} && sed -i s/a/b/ .claude/settings.json || true", f"cd {p} && cp /tmp/x .claude/hooks/guard.py; echo ok",
                        f"true; cd {p}; rm -rf .claude"):
            self.assertTrue(self.denied("Bash", command, cwd=str(self.worktree)), command)

    def test_project_dir_falls_back_to_cwd(self):
        os.environ.pop("CLAUDE_PROJECT_DIR")
        self.assertTrue(self.denied("Write", str(self.worktree / ".claude/settings.json"), cwd=str(self.worktree)))
        self.assertFalse(self.denied("Write", str(self.worktree / ".claude/settings.json")))

    def test_elsewhere_and_reads_pass(self):
        w, c, p = self.worktree, self.config, self.project
        for path in (w / ".claude/hooks/guard.py", w / ".claude/skills/x/SKILL.md", w / ".claude/settings.json",
                     c / "projects/-x/memory/MEMORY.md", f"{HOME}/.claude/projects/x/memory.md", "/tmp/claude-1000/x/y",
                     self.project / "AGENTS.md", self.project / "CLAUDE.md", self.project / "qml/shell.qml",
                     # an isolated agent's worktree, review-system's notes
                     self.project / ".claude/worktrees/agent-a/qml/shell.qml",
                     self.project / ".claude/worktrees/agent-a/.claude/settings.json", self.project / ".claude/reviews/bar.md"):
            self.assertFalse(self.denied("Write", str(path)), path)
        for command in (f"cd {w} && sed -i s/a/b/ .claude/hooks/guard.py", f"cp /tmp/x {w}/.claude/hooks/guard.py",
                        f"echo x > {c}/projects/-x/memory/note.md", f"rm -rf {c}/projects/-x/old", "rm -rf /tmp/claude-1000/x",
                        "cat .claude/settings.json", "grep -rn deny .claude", f"ls {c}", "find . -name '*.pyc' -delete",
                        "cp .claude/settings.json /tmp/backup.json", "echo x > AGENTS.md", "git switch main", "git checkout x -- .claude",
                        "git merge origin/main", "git pull --ff-only", "git push -u origin roadmap/x",
                        f"git -C {w} push -u origin roadmap/x 2>&1 | tail -2", "gh pr create --fill", "gh pr checks 3",
                        "gh pr merge 3 --squash", "scripts/dev/verify.sh", "python3 tests/scripts/test_guard.py",
                        "rm -rf .claude/worktrees/agent-a", f"echo x > {p}/.claude/worktrees/agent-a/qml/a.qml"):
            self.assertFalse(self.denied("Bash", command), command)

    def test_no_second_claude(self):
        for command in ("claude", "claude -p hi", "/usr/bin/claude --dangerously-skip-permissions", "env -C /tmp claude",
                        "timeout 60 claude -p x", "nohup claude &", "setsid claude", "echo x | xargs claude -p",
                        "cd /tmp && claude", "npx @anthropic-ai/claude-code", "npx -y @anthropic-ai/claude-code@latest -p x",
                        "bash -c 'claude -p x'", "x=$(claude -p hi)"):
            self.assertTrue(self.denied("Bash", command), command)
        for command in ("grep claude docs", "cat .claude/settings.json", "ls ~/.claude-personal", "git log --grep claude",
                        "echo claude", "npx prettier x", "which claude"):
            self.assertFalse(self.denied("Bash", command), command)


class Axiom(LiveSession, unittest.TestCase):

    def denied(self, cmd):
        try:
            guard.check({"tool_name": "Bash", "tool_input": {"command": cmd}})
        except guard.Denied:
            return True
        return False

    def test_live_shell_lifecycle_refused(self):
        for cmd in ("axiom run", "axiom run --dev --tree .", "axiom quit", "axiom restart", "./axiom daemon reexec",
                    "/usr/bin/axiom --json quit", "axiom dev on", "axiom dev off", "axiom --json dev rebuild"):
            self.assertTrue(self.denied(cmd), cmd)

    def test_scratch_instances_pass(self):
        for cmd in ("XDG_RUNTIME_DIR=$R axiom run --no-shell --tree .", "XDG_RUNTIME_DIR=/tmp/x axiom quit",
                    "axiom --socket /tmp/x/axiom.sock restart", "XDG_RUNTIME_DIR=/tmp/x axiom lock",
                    "XDG_RUNTIME_DIR=/tmp/x axiom dev on"):
            self.assertFalse(self.denied(cmd), cmd)

    def test_live_lock_refused(self):
        for cmd in ("axiom lock", "axiom ipc lockscreen lock", "axiom --json ipc lockscreen lock",
                    "env -i bash -c 'axiom lock'", "axiom ipc monitors keep", "axiom ipc selfUpdate update"):
            self.assertTrue(self.denied(cmd), cmd)

    def test_takeover_refused_on_live_config(self):
        self.assertTrue(self.denied("axiom config set Idle.enabled on --takeover"))
        self.assertTrue(self.denied("axiom config set Compositor.mode managed --takeover --offline"))
        self.assertFalse(self.denied("XDG_RUNTIME_DIR=/tmp/r XDG_CONFIG_HOME=/tmp/c axiom config set Idle.enabled on --takeover"))

    def test_greeter_only_windowed_on_scratch(self):
        for cmd in ("axiom greeter", "axiom greeter --dir /tmp/g", "AXIOM_GREETER_WINDOWED=1 axiom greeter",
                    "AXIOM_GREETER_WINDOWED=1 axiom greeter --dir /var/lib/axiom-greeter",
                    "AXIOM_GREETER_WINDOWED=1 AXIOM_GREETER_DIR=/var/lib/axiom-greeter/ axiom greeter"):
            self.assertTrue(self.denied(cmd), cmd)
        for cmd in ("AXIOM_GREETER_WINDOWED=1 axiom greeter --dir /tmp/g", "axiom greeter --dir $G --no-shell",
                    "AXIOM_GREETER_WINDOWED=1 AXIOM_GREETER_DIR=/tmp/g axiom greeter --tree ."):
            self.assertFalse(self.denied(cmd), cmd)

    def test_reads_pass(self):
        for cmd in ("axiom ping", "axiom config get Bars", "axiom ipc list", "axiom launcher toggle",
                    "axiom config set Battery.notify off", "axiom debug wayland-globals", "axiom schema build",
                    "axiom dev status", "axiom dev", "axiom dev config diff", "axiom --json dev config diff"):
            self.assertFalse(self.denied(cmd), cmd)

    def test_live_dev_verbs_refused(self):
        for cmd in ("axiom dev set ~/src/axiom-2", "axiom dev options --no-build", "axiom dev options",
                    "axiom dev config copy --to live Bar.height", "axiom dev config pull --merge",
                    "axiom --json dev config copy --to dev General", "env -i bash -c 'axiom dev set .'"):
            self.assertTrue(self.denied(cmd), cmd)

    def test_nested_daemon_socket_passes(self):
        nested = "/run/user/1000/axiom/wayland-2/axiom.sock"
        for cmd in (f"axiom --socket {nested} dev on", f"axiom --socket={nested} dev set ~/src/axiom-2",
                    f"axiom --socket {nested} dev config copy --to live Bar.height",
                    f"axiom --socket {nested} dev config pull", f"axiom --socket {nested} dev options --no-build",
                    f"AXIOM_SOCKET={nested} axiom dev rebuild", f"axiom --socket {nested} quit",
                    "axiom --socket $XDG_RUNTIME_DIR/axiom/wayland-2/axiom.sock dev off",
                    f"/tmp/n/axiom --socket {nested} ipc lockscreen lock",
                    "WAYLAND_DISPLAY=wayland-2 axiom dev on", "WAYLAND_DISPLAY=/tmp/n/wayland-2 axiom dev set ."):
            self.assertFalse(self.denied(cmd), cmd)

    def test_live_socket_still_refused(self):
        live = "/run/user/1000/axiom/wayland-1/axiom.sock"
        for cmd in (f"axiom --socket {live} dev on", f"axiom --socket={live} dev set .", f"AXIOM_SOCKET={live} axiom quit",
                    "axiom --socket $XDG_RUNTIME_DIR/axiom/$WAYLAND_DISPLAY/axiom.sock dev on",
                    "axiom --socket /run/user/1000/axiom/wayland-2/../wayland-1/axiom.sock dev off",
                    "axiom --socket /run/user/1000/other.sock dev on", "WAYLAND_DISPLAY=wayland-1 axiom dev on",
                    "WAYLAND_DISPLAY=$WAYLAND_DISPLAY axiom lock", "XDG_RUNTIME_DIR=/run/user/1000 axiom dev set ."):
            self.assertTrue(self.denied(cmd), cmd)

    def test_inherited_socket_counts(self):
        # A session started from the shell inherits its $AXIOM_SOCKET, which the CLI prefers over $WAYLAND_DISPLAY
        with mock.patch.dict(os.environ, {"AXIOM_SOCKET": "/run/user/1000/axiom/wayland-1/axiom.sock"}):
            self.assertTrue(self.denied("WAYLAND_DISPLAY=wayland-2 axiom dev on"))
            self.assertTrue(self.denied("axiom dev set ."))
            self.assertFalse(self.denied("AXIOM_SOCKET=/run/user/1000/axiom/wayland-2/axiom.sock axiom dev on"))

    def test_unknown_live_display_refuses_the_runtime_dir(self):
        with mock.patch.object(guard, "LIVE_DISPLAY", ""):
            self.assertTrue(self.denied("axiom --socket /run/user/1000/axiom/wayland-2/axiom.sock dev on"))
            self.assertTrue(self.denied("WAYLAND_DISPLAY=wayland-2 axiom dev on"))


class ConfigEdits(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.config = Path(self.dir.name) / "config.json"
        self.config.write_text(json.dumps({"Idle": {"enabled": False}, "Bar": {"x": 1}}, indent=2))
        self.patch = mock.patch.object(guard, "LIVE_CONFIG", self.config.resolve())
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.dir.cleanup()

    def edit(self, old, new):
        try:
            guard.check({"tool_name": "Edit", "tool_input": {"file_path": str(self.config), "old_string": old, "new_string": new}})
        except guard.Denied:
            return True
        return False

    def test_takeover_paths_come_from_the_schema(self):
        paths = guard.takeover_paths(json.loads(guard.SCHEMA.read_text()))
        self.assertIn(["Idle", "enabled"], paths)
        self.assertGreaterEqual(len(paths), 5)

    def test_takeover_change_refused(self):
        self.assertTrue(self.edit('"enabled": false', '"enabled": true'))

    def test_other_changes_pass(self):
        self.assertFalse(self.edit('"x": 1', '"x": 2'))

    def test_other_files_pass(self):
        guard.check({"tool_name": "Write", "tool_input": {"file_path": os.devnull, "content": "{}"}})


class GeneratedEdits(unittest.TestCase):
    def denied(self, path):
        try:
            guard.check({"tool_name": "Edit", "tool_input": {"file_path": str(REPO / path), "old_string": "a", "new_string": "b"}})
        except guard.Denied:
            return True
        return False

    def test_generated_and_frozen_refused(self):
        for path in ("qml/config/json/config.schema.json", "backend/internal/migrate/legacy/schema-v75.json",
                     "backend/internal/migrate/legacy/legacy.js", "tests/fixtures/shared/schema/Config/x.0.json",
                     "backend/internal/migrate/legacy/testdata/frozen.jsonl.gz",
                     "tests/fixtures/shared/blobs/abc.json", "backend/internal/assets/data/config/json/backend.json"):
            self.assertTrue(self.denied(path), path)

    def test_sources_pass(self):
        for path in ("qml/config/schema/sections/Bars.yaml", "qml/components/methods/SchemaValidation.qml", "data/examples/basic.json"):
            self.assertFalse(self.denied(path), path)


class Hook(unittest.TestCase):
    def test_deny_json(self):
        import subprocess
        out = subprocess.run(["python3", str(REPO / ".claude/hooks/guard.py")], capture_output=True, text=True,
                             input=json.dumps({"tool_name": "Bash", "tool_input": {"command": "qs kill"}}))
        decision = json.loads(out.stdout)["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "deny")
        self.assertIn("AGENTS.md", decision["permissionDecisionReason"])
        allowed = subprocess.run(["python3", str(REPO / ".claude/hooks/guard.py")], capture_output=True, text=True,
                                 input=json.dumps({"tool_name": "Bash", "tool_input": {"command": "ls"}}))
        self.assertEqual(allowed.stdout, "")


if __name__ == "__main__":
    unittest.main()
