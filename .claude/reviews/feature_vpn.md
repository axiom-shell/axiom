# feature:vpn
reviewed: 97dc86d 2026-11-01  (full)

Small, event-driven and documented truthfully; the doc's statements all hold. Open: the Tailscale row (one entry with the Tailscale audit's two findings on it) words every Tailscale refusal as "Couldn't connect" (red even while connected), two state fields nothing reads, and the known unseen-password-request entry.

## Open findings
- Major: [The VPN list's Tailscale row misreads Tailscale's errors, actions and login](../../docs/dev/issues.md#the-vpn-lists-tailscale-row-misreads-tailscales-errors-actions-and-login) (filed with the Tailscale audit's two findings on the same row: one cause, `rows` building the row by its own rules)
- Cleanup: [The VPN state's device and autoconnect fields nothing reads](../../docs/dev/issues.md#the-vpn-states-device-and-autoconnect-fields-nothing-reads)
- Known before: [A VPN's password request can go unseen](../../docs/dev/issues.md#a-vpns-password-request-can-go-unseen)

### A secret request doesn't survive a shell reload or a daemon re-exec (Minor)
- **Where:** `services/system/VpnManager.qml` (`secretRequest`, `_backend`), `backend/internal/daemon/vpn.go` (`vpn.get`)
- **What:** `vpn.get` returns no waiting request, so a QML reload loses the field until NetworkManager times out; after a re-exec `onGreeted` keeps the stale field. Fix: clear `secretRequest` in `onGreeted`; optionally `vpn.get` carries pending requests.

### nmvpn's tests don't cover a renamed profile or NetworkManager restarting (Minor)
- **Where:** `backend/internal/nmvpn/nmvpn_test.go`
- **What:** no `Updated` / `ConnectionRemoved` / `NameOwnerChanged` case.

## Contract
Holds: the profile cache and its invalidation, the ActiveConnections join, signal-driven reloads with a 50 ms settle, agent re-registration on NameOwnerChanged, `reasonError` (a user disconnect is reason 2 for WireGuard too, per NetworkManager's `device_state_changed`), errors kept until retried, Import (extension, plugin check, absolute path, nmcli), Down over every recorded path pruning `ConnectionNotActive`, plugin-missing refused, the agent's scope, hints/flags, Defer, NoSecrets cases, replacement, cancel and shell-only answers; VpnManager's rows, acquire-gated Tailscale, remembered last/folded, picker ownership, click-only public IP, drop notification; every surface the doc lists.

## Coverage
Read deeply: nmvpn.go, agent.go, daemon/vpn.go, VpnManager.qml, VpnRow.qml, VpnConnections.qml, Vpn.qml, VpnConfig.qml, vpn-fixtures.sh, the VPN parts of WifiNetworks.qml and Network.qml · Outlined: nmvpn_test.go, DeviceList/DeviceRow, BarPopouts' declared room, TailscaleManager `_run`, LauncherCommands `/vpn` · Unsettled live: whether WifiNetworks' `vpnRoom` leaves room for an asking row's fields.

## History
- 2026-11-01 full: 4 findings (1 Major, 1 Cleanup, 2 Minor); recorded
