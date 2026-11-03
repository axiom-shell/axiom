//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=threaded

pragma ComponentBehavior: Bound
import Quickshell
import qs.shell

// The greeter's entrypoint (greetd's login screen; shell.qml is the
// session's): `qs -p <installed copy>/greeter.qml`, run by
// scripts/greeter/greeter-session.sh as greetd's user with
// AXIOM_GREETER=1, which puts ConfigManager, ThemeManager and Paths in
// their read-only greeter mode. Only the greeter is built: no bars,
// notification server, polkit agent or anything else of the session's.
ShellRoot {
  Greeter {}
}
