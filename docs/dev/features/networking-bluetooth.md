# Networking and Bluetooth

> **Files:** `services/system/NetworkingManager.qml`, `services/system/BluetoothManager.qml`, `backend/internal/nmnet/`, `backend/internal/daemon/net.go`, `components/content/WifiNetworks/WifiNetworks.qml`, `components/content/parts/WifiJoinForm.qml`, `components/content/parts/ConnectionDetails.qml`
> **Config:** `Apps.networkEditor` (the Wi-Fi menu's Settings button)
> **Related:** [Services pattern](../core/services-pattern.md), [VPN](vpn.md)

Wi-Fi, wired and Bluetooth state, built on Quickshell's D-Bus modules. Throughput is not here: it stays in SystemManager. VPNs are VpnManager's ([VPN](vpn.md)).

### NetworkingManager
- Wi-Fi over `Quickshell.Networking`: NetworkManager over D-Bus, event-driven. Nothing runs `nmcli`. What Quickshell doesn't show goes through axiom's `nmnet` (below).
- **Radio:** `wifiEnabled`, `setWifiEnabled`.
- **Airplane mode:** `setAirplane(on)` remembers both radios' states (`StateManager`, `airplane`) and turns Wi-Fi and Bluetooth off; off restores them (Wi-Fi at least). `airplane` is true only when turned on here and both radios are still off: either coming back on ends it, and radios that are merely both off aren't airplane mode.
- **`networks`:** sorted connected first, then saved, then by name. The order is fixed.
- **Actions:** connect, disconnect, forget.
- **Password prompt:**
  - `passwordFor`, and what it takes by `securityKind(network)` (`psk`, `wep`, `eap`, `dynamic-wep`, `leap`, `open`, or `unsupported`: WPA3 192-bit, which needs a client certificate).
  - A WPA password goes through Quickshell (`connectWithPsk`); anything else through `join(network, fields, done)` (axiom's `net.join`, below), whose refusal for a network in range is `joinError` and asks again (a hidden network's goes to `done` only).
  - Asked again after a `NoSecrets` failure.
- **Saved networks:** `saved` (name → `{ uuid, autoconnect }`, `net.savedWifi`), read again as one is saved or forgotten while something scans; `autoconnects(network)` and `setAutoconnect(network, on)`.
- **Details:** `details` is `net.details` for the primary device, read on `refreshDetails()` (when the Wi-Fi menu's details open) and again as the connection changes once asked for (a connection going away clears them). `connectivity` is NetworkManager's check: `portal` (a sign-in page in the way), `limited`, else "".
- **Primary connection:**
  - `primaryDevice` prefers wired over Wi-Fi.
  - `netInfo` is `{ kind, name, device, signal, ip }`, all bindings.
  - The one exception is the IPv4 address, which Quickshell.Networking lacks. It comes from axiom (`net.addresses`, the interface's addresses read in Go; the greeter's `axiom greeter` answers it too) whenever the connection changes, or on `refreshIp()`; an answer for a lookup since replaced is dropped.
- **Scanning:** the scanner runs only while something holds `acquireScan(owner)`.
- Not named `Networking`, which is Quickshell's singleton. (Rule: AGENTS.md › Services.)

### nmnet (axiom)
What the Wi-Fi menu asks NetworkManager beyond Quickshell.Networking, over the system bus (a new connection per call; nothing here is followed):
- **`net.details {device}`:** `HwAddress`; a wire's `Speed`, or Wi-Fi's `Bitrate` and the access point's `Frequency` (band and channel worked out by `band`); `Ip4Config`'s address with its prefix, `Gateway` and `NameserverData`; `Ip6Config`'s first address that isn't link-local.
- **`net.join {device, ssid, hidden, security, password, identity, anonymousIdentity, eap, phase2, caCert, systemCa}`** (from the shell only, as it carries a password; over the socket, never argv): `wifiSettings` builds the profile (pure, table-tested): `wpa-psk`; WEP (`key-mgmt none`, `wep-key-type` 1 for a 5/13-character or 10/26-hex key, else 2, a passphrase); PEAP or TTLS (`wpa-eap`, an `802-1x` setting with the inner method, identities, and the CA as a `file://` path or `system-ca-certs`); dynamic WEP (the same over `ieee8021x`); LEAP. A profile already saved for the name is updated in place and activated, so a second try with a corrected password replaces the first; else it's `AddAndActivateConnection`.
- **`net.savedWifi`, `net.setAutoconnect {uuid, on}`:** the update sends the profile's secrets back with it (`GetSecrets` for `802-11-wireless-security` and `802-1x`, as nmcli does), or NetworkManager would drop those it keeps.

### The Wi-Fi menu
`content/WifiNetworks`, the Network widget's popout:
- **Header:** the radio switch (none, and titled Network, without a Wi-Fi adapter) and airplane mode.
- **The connection:** a `FoldRow` folding open `ConnectionDetails`, folded until clicked.
- **VPN section:** folded to one row ([VPN](vpn.md)). Left out, with Import VPN, when the card's `showVpn` or the widget's `popoutVpn` is off (`showsVpn`; the popout's arrives through `extraData` after it's built, so VPN data is acquired as it changes).
- **Networks:** `NetworkRow`s; a secured one has a lock (`badge` for enterprise) on its signal icon (`DeviceRow.iconBadge`), so every row's name and buttons line up. A known one's hover shows autoconnect before forget (`DeviceRow.hoverActions`, over the end of the name), and one that doesn't join on its own says "manual" in its status. An unsaved secured one opens a password field (WPA) or a `WifiJoinForm`, Connect beside its last field.
- **Footer:** Settings (`Apps.networkEditor`), Hidden network (a `WifiJoinForm` with `hidden`, closed once NetworkManager takes it), Import VPN.
- **Room:** the window never grows while shown: `maxImplicitHeight` keeps, beside the list's growth, each folding part's most less what it shows now (details, the VPN rows, the hidden form). Focus lost to the file picker (a CA certificate) doesn't cancel the form.

### BluetoothManager
- Over `Quickshell.Bluetooth`: adapter power, scanning, sorted device lists, and connect / pair / forget.
- Not named `Bluetooth`: that would shadow Quickshell's singleton, and the name is also taken by the `Bluetooth` bar widget file.
