# Polkit agent

> **Files:** `services/session/PolkitManager.qml`, `components/methods/PolkitAgents.qml`, `config/PolkitConfig.qml`, `shell/PolkitPrompt.qml`, `components/surfaces/polkit/PolkitWindow.qml`, `components/views/Settings/PolkitStatusCard.qml`
> **Config:** `Polkit.*` (reader `PolkitConfig`)
> **Related:** [Lockscreen](lockscreen.md) (shared password field), [Shell manager and targeting](../core/shell-manager-targeting.md), [Greeter install](greeter-install.md)

Axiom as the session's polkit agent: it takes over registration from other agents and draws a modal password prompt.

### Enabling
- Off by default; the onboarder's Integrations page recommends it.
- `Polkit.enabled` is `x-takeover`.
- While it's on, a `LazyLoader` holds a `PolkitAgent`.
- **`flow`:** the open request (an `AuthFlow`).
- **`status`:** `off` | `starting` | `running` | `blocked`.

### Taking over from other agents
A session has one agent, and Quickshell never retries a failed registration. So:
- **After 2 s:** if the agent is still unregistered, it looks for the agents `components/methods/PolkitAgents` knows.
  - `PolkitAgents` is pure: process names, systemd user units, `isAgentCommand`, `processPattern`.
  - Matches are anchored to the executable, so a command whose argument names an agent is never killed.
- **Stopping them:** `systemctl --user stop` for the active units, `pkill -f` for the rest.
- **Remaking:** it remakes the agent once, after a 300 ms pause. The old agent is deleted later, and a new one made before then doesn't register.
- **After 15 s:** it looks again and stops any agent started after qs (`replaced`).
- **Turned off:** the units it stopped start again.
  - Those units and `replaced` are kept in a `PersistentProperties`, so a reload keeps them.
- **Reloads:** a hot reload keeps the registration and the open request, because Quickshell hands the listener to the new generation.
- The managed mode's autostart (`Session.autostart`) skips agent commands while this is on.

### Handling a request
- It picks the monitor (the focused one).
- It selects the user's own identity when that's listed.
- It reads the action's description and vendor from `pkaction`, one at a time. A result for a different action is dropped.
- **Answering:** `submit` / `cancel` / `selectIdentity` are the only ways. There is no IPC.

### The prompt
- Drawn by `shell/PolkitPrompt` → `surfaces/polkit/PolkitWindow`, on every screen.
- **Layer:** Overlay, with the `axiom-polkit` layer rule, which stacks it over every other axiom surface.
- **Modal:** it dims everything, bars included.
- **`ShellManager.modalWindows`:** it is registered there while shown, so a prompt over the overlay clears no focus grab. One case is the greeter's install started from Settings. Without a native grab (sway, niri) the grabbing surface stops asking for exclusive keyboard meanwhile (`ShellManager.modalShown`), or it would keep the keyboard from the prompt.
- **The card:** with exclusive keyboard, on the picked screen (`General.screensNamed`).
- **The field:** `reusable/PasswordEntry`, shared with the lock screen's `PasswordField`. It takes no keys for 400 ms after it opens.
- Settings → Authentication prompts starts with `PolkitStatusCard`.
- Created from `shell.qml`'s `_services`.

### Testing
- Trigger a prompt with `sh -c 'pkexec true' &`. pkexec refuses when its parent has exited, hence the `sh -c`.
- Cancel it with `pkill -x pkexec`.
