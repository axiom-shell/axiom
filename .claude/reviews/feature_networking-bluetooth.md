# feature:networking-bluetooth
reviewed: 97dc86d 2026-11-01  (full)

A small, well-layered system with true docs; Bluetooth discovery is started and stopped per menu instead of through a consumer registry, and the join form's CA check outlives the security that shows it.

## Open findings
- Major: [Two Bluetooth menus share one discovery scan, and one closing stops the other's](../../docs/dev/issues.md#two-bluetooth-menus-share-one-discovery-scan-and-one-closing-stops-the-others)
- Major: [The join form stays incomplete when CA file is picked without a file and the security changed](../../docs/dev/issues.md#the-join-form-stays-incomplete-when-ca-file-is-picked-without-a-file-and-the-security-changed)
- Cleanup: [net.join's first-Wi-Fi fallback is never reached](../../docs/dev/issues.md#netjoins-first-wi-fi-fallback-is-never-reached)

### NetworkingManager's IP comment still says `ip`
- **Where:** `services/system/NetworkingManager.qml:51` (`primaryIp`)
- **What:** "it's looked up once with `ip` whenever the primary connection changes": it's axiom's `net.addresses` now (and `refreshIp`). Fix: say so.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the networking-bluetooth system

### setAirplane's comment promises Wi-Fi always comes back
- **Where:** `services/system/NetworkingManager.qml:112` (`setAirplane`)
- **What:** "restores them (Wi-Fi at least, so leaving it always reconnects)", but with Wi-Fi off and Bluetooth on before, `setWifiEnabled((was.wifi ?? true) || !bluetooth)` leaves Wi-Fi off. The code is right (at least one radio comes back); the comment and the doc's "(Wi-Fi at least)" say otherwise. Fix: "restores them (Wi-Fi when neither was on)".
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the networking-bluetooth system

### An unknown security type reads as needing a client certificate
- **Where:** `services/system/NetworkingManager.qml:151` (`securityKind`)
- **What:** `WifiSecurityType.Unknown` falls to `return "unsupported"`, so clicking such a network shows "Needs a client certificate", which is said for WPA3 192-bit only (the doc's list). PLAUSIBLE: depends on when Quickshell reports Unknown. Fix: a separate failure text ("Unsupported security") for Unknown.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the networking-bluetooth system

### nmnet treats a failed ListConnections as no saved networks
- **Where:** `backend/internal/nmnet/nmnet.go:253` (`wifiProfiles`)
- **What:** An error from `ListConnections` returns nil, so `SavedWifi` answers an empty list (the shell then shows every network as autoconnecting and its toggle does nothing) and `Join` adds a second profile instead of updating the saved one. Rare (NetworkManager's settings service failing). Fix: return the error and pass it on.
- **Size:** small
- **Found:** 2026-11-01, while reviewing the networking-bluetooth system

## Contract
Holds: nothing runs nmcli; radio, airplane (`airplane` only while turned on here and both radios off; either back on ends it), `networks` order, connect/disconnect/forget, `securityKind`'s kinds, psk through `connectWithPsk` and the rest through `net.join` with `joinError` for a network in range and `done` for a hidden one, asked again after `NoSecrets`, `saved` re-read as the known set changes while scanning, `details` read on open and on connection changes once asked, `connectivity`, `primaryDevice` preferring wired, `netInfo` bindings, `net.addresses` with stale answers dropped, scanning only while acquired. nmnet: `net.details` fields, `wifiSettings`' profiles (all kinds table-tested), update-in-place join, `GetSecrets` kept on autoconnect updates, `net.join` shell-only. The Wi-Fi menu: header, FoldRow details, VPN section and `showsVpn`, badges, hover autoconnect, Hidden network, `maxImplicitHeight` room, the file picker not cancelling. BluetoothManager's members and naming hold; its scanning is the Major above.

## Coverage
Read deeply: services/system/NetworkingManager.qml, services/system/BluetoothManager.qml, backend/internal/nmnet/nmnet.go, backend/internal/nmnet/join.go, backend/internal/daemon/net.go, components/content/WifiNetworks/WifiNetworks.qml, components/content/parts/ConnectionDetails.qml, WifiJoinForm.qml (lines 1–130, the rest by grep) · Outlined: components/content/BluetoothDevices/BluetoothDevices.qml (lines 1–100, the seam), QuickActions, LauncherCommands, the Network and Bluetooth bar widgets (their uses of the managers), nmnet_test.go (cases by grep; `go test` passes) · Skipped: none. Not run live: the two-menu discovery scenario and the WPA3/Unknown security cases need real hardware or a second menu open.

## History
- 2026-11-01 full: 7 findings (2 Major, 1 Cleanup, 4 Minor); recorded
