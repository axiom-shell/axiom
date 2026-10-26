# Tailscale

> **Files:** `services/apps/TailscaleManager.qml`, `config/TailscaleConfig.qml`, `components/bar/widgets/Tailscale/Tailscale.qml`, `components/content/Tailscale/Tailscale.qml`, `backend/internal/tailscale/tailscale.go`, `backend/internal/daemon/topics.go`
> **Config:** `Tailscale.*` (reader `TailscaleConfig`); the bar widget's own settings are only about the bar
> **Related:** [Services pattern](../core/services-pattern.md) (polled topics), [Protocol](../backend/protocol.md), [Networking and Bluetooth](networking-bluetooth.md) (the Network card's Tailscale line)

Tailscale's state for the bar widget, its popout and the overlay module, shaped like Claude usage: the `Tailscale` section (Modules category) holds what every widget shares, the widget only its look and click command.

### State
- axiom polls `tailscale status --json` (the `tailscale` topic) every `TailscaleConfig.interval`, only while something acquires `TailscaleManager` (schema minimum 1 s, the only floor: `topics.MinInterval` is 1 ms). Consumers `acquire(owner)` with no request: they all share the interval.
- `tailscale.Parse` keeps what the shell shows: this machine (host and MagicDNS name, every address, version), the tailnet, the MagicDNS suffix, a pending login's `authURL`, the health warnings, the exit node in use, and the peers (name from the MagicDNS name, OS, addresses, online, active, direct or relayed, last seen, traffic), online first, then by name. Lists are never null.

### Actions
- `tailscale.up` / `tailscale.down` (`TailscaleManager.connect()` / `disconnect()`) run `tailscale up` / `down` with the node's saved settings, then refresh the topic. `up` waits at most 15 s: past that a login is pending, and its link shows in the state.
- Without operator rights tailscaled refuses (`access denied`): the method fails with kind `refused`, which the shell words as "run `sudo tailscale set --operator=$USER` once". The message is in `TailscaleManager.lastError` until the next success.
- The login link opens with `TailscaleManager.openLogin()` (`Qt.openUrlExternally`, never through a shell). Go tests stub the command: never run `tailscale up/down` for real while testing.

### Surfaces
- The bar widget: connected or not, the tailnet's name (or its label); left click runs `clickCommand`, right click refreshes. Its popout is its own (`popout: {variant: own}`, `content/Tailscale`).
- `content/Tailscale` is a `Panel`: the popout, and a module on pages, edge menus and the desktop (not the lock screen: it shows addresses and runs actions). Peers are a `DeviceList`, so the popout keeps one height; a click copies a peer's first address. Compact, it shows the devices online. `Tailscale.showOffline` hides offline peers, `Tailscale.actions` the Connect / Disconnect button.
- The v79 step moved each widget's old `interval` to `Tailscale.interval` (the shortest one) and dropped the old menu popout's default off-state, so the new popout shows.
