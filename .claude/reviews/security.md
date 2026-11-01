# security
reviewed: c4866c0 2026-11-01  (full)

The lock's core holds: only `LockManager.lock()` locks, only PAM's success (or the compositor ending a lock it refused) clears it, there is no IPC unlock, and secrets stay out of argv, config and logs. Two rarer paths are wrong: a shell relaunched locked relocks on every later QML reload, and Idle with the user's own locker left at `loginctl lock-session` locks nothing, silently.

## Open findings
- Major: [A shell started locked locks again on every reload](../../docs/dev/issues.md#a-shell-started-locked-locks-again-on-every-reload)
- Major: [With Idle on and the user's own locker left at loginctl lock-session, nothing locks](../../docs/dev/issues.md#with-idle-on-and-the-users-own-locker-left-at-loginctl-lock-session-nothing-locks)
- Cleanup: [PolkitAgents.isAgentCommand is dead since the autostart moved to Go](../../docs/dev/issues.md#polkitagentsisagentcommand-is-dead-since-the-autostart-moved-to-go)
- Cleanup: [Power repeats the session actions' icons, labels and confirm](../../docs/dev/issues.md#power-repeats-the-session-actions-icons-labels-and-confirm)

### secrets.md names an OnSecrets that doesn't exist
- **Where:** `docs/dev/core/secrets.md:37`
- **What:** No `OnSecrets` exists in `backend/`; the sentence should say no migration step pulls secrets out of config.json any more.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the security system

### lockscreen.md's Files header leaves out the Go locker it describes
- **Where:** `docs/dev/features/lockscreen.md:3`
- **What:** "Under axiom (`axiom lock`)" describes `backend/internal/lockscreen`, which the header doesn't list (only protocol.md's does), so this system's scope misses it. Add it.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the security system

## Contract
- Only `LockManager.lock()` locks; `lockState.locked` clears only on `AuthManager.authenticationSucceeded` or the compositor ending the lock (`OnlyPamUnlocks` guards it). `lockscreen` IPC has only `lock`, only outside mode `none`.
- `lock.state` and `idle.caffeine` are shell-only (`fromShell`).
- No QML reload under the lock (`watchFiles` off, `LockManager.reload()` waits; nothing else calls `Quickshell.reload`).
- Lock screen modules: actions only in Power, NowPlaying, VolumeDials; CustomWidget actions off while locked.
- Secrets: stdin to secret-tool; secrets.json atomic, 600, never over an unparsable file; no RPC params logged; `Chat.providers` machine-scoped; typed secrets and `AuthManager._password` cleared after use.
- Polkit: one request at a time, pkaction matched to the action, 400 ms read-only, no IPC, executable-anchored kill pattern.
- Idle: logind `Lock` honoured only with `Idle.enabled`; sleep inhibitor let go after the lock or its deadline.

## Coverage
Read deeply: LockManager, AuthManager, shell/Lockscreen.qml, LockSurface, PasswordField, Password, PolkitManager, PolkitAgents, PolkitWindow, SecretsManager, backend secrets.go, daemon/secrets.go, chat/keys.go, backend/internal/lockscreen/lockscreen.go, SessionManager, PowerMenuWindow, Power, IdleManager, idle.go (sleep, logind, action paths).
Outlined: idle/plan.go, IdleStatusCard, ChatProvidersCard, CalendarAccountsCard, the lockscreen-hosted modules, LockscreenConfig, PowerMenuConfig.
Skipped: ScreenLayoutView, ScreenLayoutEditor, PasswordEntry, FocusKeeper, backend logind, screensaver, wayland/idlenotify, IdleInhibit, Caffeine, IdleInhibitor, PolkitStatusCard, Greeting's greeter side.

## History
- 2026-11-01 full: 6 findings (2 Major, 2 Cleanups, 2 Minor); recorded
