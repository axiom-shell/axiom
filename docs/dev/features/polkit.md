# Polkit agent

> **Files:** `qml/services/session/PolkitManager.qml`, `qml/components/methods/PolkitAgents.qml`, `qml/config/PolkitConfig.qml`, `qml/components/surfaces/prompt/PolkitCard.qml`, `qml/components/views/Settings/PolkitStatus.qml`
> **Config:** `Polkit.*` (reader `PolkitConfig`)
> **Related:** [Prompts](prompts.md), [Lockscreen](lockscreen.md) (shared password field), [Shell manager and targeting](../core/shell-manager-targeting.md), [Greeter install](greeter-install.md)

Axiom as the session's polkit agent: it takes over registration from other agents and draws a modal password prompt.

### Enabling
- Off by default; the onboarder's System page recommends it.
- `Polkit.enabled` is `x-takeover`.
- While it's on, a `LazyLoader` holds a `PolkitAgent`.
- **`flow`:** the open request (an `AuthFlow`).
- **`status`:** `off` | `starting` | `running` | `blocked`.

### Taking over from other agents
A session has one agent, and Quickshell never retries a failed registration. So:
- **After 2 s:** if the agent is still unregistered, it looks for the agents `qml/components/methods/PolkitAgents` knows.
  - `PolkitAgents` is pure: process names, systemd user units, `processPattern`. The managed mode's autostart matches agent commands in Go against the same table (`Tables.IsAgentCommand`).
  - Matches are anchored to the executable, so a command whose argument names an agent is never killed.
- **Stopping them:** `systemctl --user stop` for the active units, `pkill -f` for the rest.
- **Remaking:** it then remakes the agent after a 300 ms pause, even when it found no agent to stop (a stopped agent can hold the session for a moment after its kill). The old agent is deleted later, and a new one made before then doesn't register.
  - Deleting the agent deletes its listener, so the new one registers afresh.
  - At most 3 remakes; still unregistered, `status` is `blocked` and it warns `Could not register as the polkit agent`.
- **After 15 s:** it looks again and stops any agent started after qs (`replaced`).
- **Turned off:** the units it stopped start again.
  - Those units and `replaced` are kept in a `PersistentProperties`, so a reload keeps them.
- **Reloads:** a hot reload keeps the registration and the open request, because Quickshell hands the listener to the new generation.
  - It hands it over as it is: one that never registered stays unregistered and never retries, so the 2 s check remakes it in the new generation too.
- The managed mode's autostart (`Session.autostart`) skips agent commands while this is on.

### Handling a request
- **The queue:** each request (a new `flow`) goes through the shared prompt's queue (`PromptManager.request` with `content: "polkit"` and `outsideCancels: false`), and is withdrawn when the flow ends; a reload queues the open flow again. So a Bluetooth pairing prompt asked meanwhile waits behind it, and the other way round. The prompt picks the monitor (the focused one) when the request comes to the front ([Prompts](prompts.md)).
- It selects the user's own identity when that's listed.
- It reads the action's description and vendor from `pkaction`, one at a time. A result for a different action is dropped.
- **Answering:** `submit` / `cancel` / `selectIdentity` are the only ways. There is no IPC.

### The prompt
- Drawn by the shared prompt's window (`qml/shell/Prompt` → `surfaces/prompt/PromptWindow`, on every screen), which loads `surfaces/prompt/PolkitCard` as its card ([Prompts](prompts.md)).
- **Layer:** Overlay, with the `axiom-polkit` layer rule (the shared prompt kept the name), which stacks it over every other axiom surface.
- **Modal:** it dims everything, bars included; a click outside the card does nothing (`outsideCancels: false`), Escape cancels.
- **`SurfaceManager.modalWindows`:** it is registered there while shown, so a prompt over the overlay clears no focus grab. One case is the greeter's install started from Settings. Without a native grab (sway, niri) the grabbing surface stops asking for exclusive keyboard meanwhile (`SurfaceManager.modalShown`), or it would keep the keyboard from the prompt.
- **The card:** with exclusive keyboard, on the picked screen (`General.screensNamed`).
- **The field:** `reusable/PasswordEntry`, shared with the lock screen's `PasswordField`. It takes no keys for 400 ms after it opens.
- Settings → Authentication prompts is one card: `PolkitStatus` on top (its status chip in the header) over the switch.
- Created from `qml/shell.qml`'s `_services`.

### Testing
- Trigger a prompt with `sh -c 'pkexec true' &`. pkexec refuses when its parent has exited, hence the `sh -c`.
- Cancel it with `pkill -x pkexec`.
