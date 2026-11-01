# feature:tailscale
reviewed: 97dc86d 2026-11-01  (full)

The Tailscale system is sound: the Go side parses, bounds and refuses as documented, and every action refreshes both topics. Its problems are at its seams. VpnManager works out Tailscale's login and busy states for itself and gets both wrong, and the panel's relative times update only when the state changes.

## Open findings
- Major: [The panel's relative times go stale while Tailscale's state stays the same](../../docs/dev/issues.md#the-panels-relative-times-go-stale-while-tailscales-state-stays-the-same)
- Cleanup: [Tailscale carries two state fields and a guard nothing needs](../../docs/dev/issues.md#tailscale-carries-two-state-fields-and-a-guard-nothing-needs)
- Outside: [The VPN list's Tailscale row misreads Tailscale's errors, actions and login](../../docs/dev/issues.md#the-vpn-lists-tailscale-row-misreads-tailscales-errors-actions-and-login) (this audit's findings that the row does nothing while it needs a login with no link yet and shows any action as connecting or disconnecting, merged into the VPN audit's entry for the same row)
- Outside: [The Network card shows Tailscale's raw state, untranslated](../../docs/dev/issues.md#the-network-card-shows-tailscales-raw-state-untranslated)
- Known before: [Tailscale's PeerRow redraws DeviceRow without its buttons](../../docs/dev/issues.md#tailscales-peerrow-redraws-devicerow-without-its-buttons)

### TailscaleConfig.actions' comment names only Connect / Disconnect
- **Where:** `config/TailscaleConfig.qml:17` (`actions`)
- **What:** The comment says "Show the Connect / Disconnect buttons", but the setting also hides the account, exit node and option folds and Grant access. Fix: reword it.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the tailscale system

### NeedsMachineAuth reads "Needs login"
- **Where:** `components/content/Tailscale/Tailscale.qml:40` (`stateLabels`)
- **What:** The state means waiting for an admin's approval; logging in doesn't help, and `needsLogin` rightly excludes it. Fix: label it "Waiting for approval".
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the tailscale system

### The daemon's tailscaleMethods takes options no caller varies
- **Where:** `backend/internal/daemon/topics.go:47` (`tailscaleMethods`)
- **What:** Its one caller passes `tailscale.Options{}`, and no test stubs it. Fix: drop the parameter, or test the handlers through it.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the tailscale system

## Contract
Every statement in docs/dev/features/tailscale.md holds. The topic is polled only while acquired, at `Tailscale.interval` (schema minimum 1 s; `topics.MinInterval` is 1 ms). `Parse`'s lists are never null, with peers online first, then by name. The details topic's `known` and `profilesDenied` behave as described. `up`/`login` are bounded at 15 s, and the cut-off isn't a failure. `switch` and the operator grant refuse `-` values. `set` sends only the fields given, as `--flag=value`. Every action refreshes both topics. `refused`, `unauthorized` and `unavailable` are worded by the shell, and `openLogin` opens only http(s) links. The module isn't on the lock screen (its schema lists no `hosts`). Grant access comes first, and the folds show only their value while operator rights are missing.

## Coverage
Read deeply: backend/internal/tailscale/tailscale.go, backend/internal/daemon/topics.go, services/apps/TailscaleManager.qml, components/content/Tailscale/Tailscale.qml, components/bar/widgets/Tailscale/Tailscale.qml, config/TailscaleConfig.qml, both schemas · Outlined: tailscale_test.go, topics.Hub Refresh/push, BackendManager call/acquire/refresh, VpnManager's Tailscale row, Network.qml's Tailscale line · Skipped: none. Not exercised live (no action may run; tailscaled Stopped here): the 15 s login cut-off keeping `AuthURL`, refusal wording, stale relative times.

## History
- 2026-11-01 full: 8 findings (1 Major, 1 Cleanup, 3 Outside recorded; 3 Minor left open)
