# greeter
reviewed: c4866c0 2026-11-01  (full)

In good shape: greeter mode is gated everywhere it acts, the bundle is data only, the installer is tested on scratch roots. Open: an uninstall that can restore a greetd config from before an earlier install, and a keyboard-layout read racing the bundle's input setup.

## Open findings
- Major: [Uninstall keeps a stale greetd backup when greetd points elsewhere](../../docs/dev/issues.md#uninstall-keeps-a-stale-greetd-backup-when-greetd-points-elsewhere)
- Major: [The greeter reads its keyboard layouts before the bundle's are applied](../../docs/dev/issues.md#the-greeter-reads-its-keyboard-layouts-before-the-bundles-are-applied)
- Cleanup: "GreetdManager.available is never read" (fixed, row 20 platform-01)
- Minor: Stale names and claims in the greeter's docs and comments: `Greeter.monitor` for `Greeter.screen` (greeter-runtime.md:85, GreeterWindow.qml:10, GreeterSurface.qml:14); "greetd's Hyprland" (GreeterWindow.qml, shell/Greeter.qml:17) though sway comes first; the display modules list misses `Clock`; "owns no ... Wayland connection" though `greeterProfiles` runs an `outputs.Tracker`; `Greeter.source`'s description says main can't be installed though it installs the edge build.
- Minor: A failed status check's `_lastError` (GreeterManager.check) outlives the next good check and overwrites the last action's error; reachable only when greeter.status errors.

## Contract
Holds: the bundle's contents and its sh writer (temp + rename, stale copies removed, go+rX); export timing (1 s debounce while installed and writable, retried, rewritten after install/update, JSON-only staging); greeter-session.sh's sway → Hyprland → agreety order, failure marker, `--safe` retry; `axiom greeter`'s bundle → fallback → defaults load, runtime folder, `greeterKept`, exit status, SIGTERM; the greeter registry's own-qs-only hello and method list; ThemeManager's greeter theme path; CompositorConfigManager off in greeter mode; every greeter module gated on host.kind, !preview and Paths.greeter; `_applyCompositor` skipped windowed; installer's PKEXEC_UID check, refusals, backups, swap with rollback, settle, link-free snapshot; Elevate's first-program and marker rules.

## Coverage
Read deeply: GreeterManager, GreetdManager, daemon/greeter.go, cli/greeter.go, greeterinstall/install.go, elevate.go, greeter-session.sh and its compositor configs, the greeter surfaces and shells, LoginField, Power, KeyboardLayout, GreeterSetup, GreeterStatusCard, the three Greeter methods helpers, GreeterConfig, Greeter.yaml. Outlined: greeterinstall.go, rules.go, release.go, greeter/greeter.go, daemon/greeterinstall.go, Login, Session, compositorsocket.go's greeter part. Skipped: PAM/polkit security (the `security` audit), tests beyond grepping for cases.

## History
- 2026-11-01 full: 5 findings (2 Major, 1 Cleanup, 2 Minor); recorded
