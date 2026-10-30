# VPN

> **Files:** `backend/internal/nmvpn/`, `backend/internal/daemon/vpn.go`, `services/system/VpnManager.qml`, `components/content/parts/VpnRow.qml`, `components/content/VpnConnections/VpnConnections.qml`, `components/bar/widgets/Vpn/Vpn.qml`, `components/bar/widgets/Network/Network.qml`, `components/content/WifiNetworks/WifiNetworks.qml`, `scripts/dev/vpn-fixtures.sh`
> **Config:** `Vpn` (`VpnConfig`); the Network widget's `showVpn` / `vpnColor`
> **Related:** [Networking and Bluetooth](networking-bluetooth.md), [Protocol](../backend/protocol.md), [D-Bus](../backend/dbus.md)

NetworkManager's VPNs (WireGuard, OpenVPN and every other plugin), with Tailscale beside them, as one list to switch from the bar, the Wi-Fi menu, an overlay card or the launcher.

### Why the daemon
Quickshell's `Networking` has no VPN or active-connection types (`DeviceType` is `None`/`Wifi`/`Wired`). So `nmvpn` talks to NetworkManager over the system bus instead:
- **State:** `Settings.ListConnections` and `GetSettings` for each profile, keeping types `vpn` and `wireguard`. Profiles are cached until NetworkManager sends `Updated` or `ConnectionRemoved`. The state is joined with `Manager.ActiveConnections` for each VPN's state, its address (`Ip4Config.AddressData`) and its device (WireGuard only: a plugin VPN's tunnel isn't named on the bus).
- **Event-driven:** the manager's `PropertiesChanged`, Settings' signals, `Connection.Active.StateChanged` and `VPN.Connection.VpnStateChanged` trigger a reload, with signals gathered over `Settle`. Nothing polls. NetworkManager restarting re-registers the agent (`NameOwnerChanged`).
- **Errors:** a connection going down records its reason (`reasonError`: `no-secrets`, `login-failed`, `timeout`, `service-failed`, `failed`), kept until it's tried again. A disconnect someone asked for (reason 2) records none, so `error` on an off VPN means it failed or dropped.
- **Plugins:** a VPN whose plugin has no `.name` file in `/usr/lib/NetworkManager/VPN` or `/etc/NetworkManager/VPN` is `plugin: false` (`error: plugin-missing`), and `Up` refuses it instead of letting NetworkManager fail.

### Protocol
- **Methods:** `vpn.get`, `vpn.up {uuid}`, `vpn.down {uuid}`, and `vpn.secret {id, secrets | cancel}` (from the shell only).
- **Pushes:** `vpn.state` (latest wins), `vpn.secretRequest` and `vpn.secretDone`, on the hello topic `vpn`.

### The secret agent
- axiom registers as `org.axiom.shell` with NetworkManager's AgentManager.
- `GetSecrets` for a `vpn` or `wireguard` setting, with interaction allowed, pushes a `SecretRequest`. Its fields come from NetworkManager's hints, else from the setting's `*-flags` (agent-owned or not saved, and required). The answer waits, using `dbus.Method.Defer`, until `vpn.secret` replies.
- Anything else, no interaction, or no shell connected gets `NoSecrets` at once, so NetworkManager goes on to another agent (nm-applet) if there is one.
- `CancelGetSecrets` or NetworkManager leaving ends the request and pushes `vpn.secretDone`.
- Secrets aren't stored: `SaveSecrets` and `DeleteSecrets` do nothing.
- The request shows only in a VPN row that's on screen. A VPN started from elsewhere (nmcli, autoconnect) with nothing open waits until NetworkManager times out.

### Shell
- **VpnManager:**
  - `rows` merges the profiles with a Tailscale row (id `tailscale`, through `TailscaleManager`) while something holds `acquire()` and `VpnConfig.showTailscale` is on. Tailscale is polled; NetworkManager's state isn't.
  - Rows stay in name order, so nothing moves under the pointer.
  - `toggle`, `toggleLast` (the VPN used last, kept in `StateManager` as `vpn`), `statusText` and `kindIcon`.
  - An on → off change with an error sends a "VPN disconnected" notification (`VpnConfig.notifyOnDrop`).
- **VpnRow:** a `DeviceRow`. Clicking toggles it; while it's asked for secrets, a password field per field appears under it.
- **Where VPNs show:**
  - The `VpnConnections` popout and card (`DeviceList` of `VpnRow`s; Edit connections runs `VpnConfig.editorCommand`).
  - The `Vpn` bar widget: click toggles the last VPN, hover opens the popout, `hideWhenOff`.
  - The Network widget: a lock on its icon, and the VPN's name in ticker and stacked styles.
  - The Wi-Fi menu: a VPN section showing those up, the last used and the one asking, with Show all. Hidden with no VPNs.
  - The Network card's "VPN ·" line.
  - `/vpn [name]` in the launcher.

### Testing
`scripts/dev/vpn-fixtures.sh up` adds two profiles owned by the user, so no admin rights are needed:
- A WireGuard profile that really comes up: a peer at TEST-NET 192.0.2.1, routing only 10.99.0.0/24.
- An OpenVPN profile that asks for a password each time and then times out. Without `networkmanager-openvpn` it is added as a profile whose plugin is missing.

`down` removes them. The Go side is tested against a fake NetworkManager on `dbustest` (`nmvpn_test.go`).
