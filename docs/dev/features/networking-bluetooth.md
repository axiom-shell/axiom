# Networking and Bluetooth

> **Files:** `qml/services/system/NetworkingManager.qml`, `qml/services/system/BluetoothManager.qml`, `backend/internal/nmnet/`, `backend/internal/daemon/net.go`, `backend/internal/bluez/`, `backend/internal/daemon/bluetooth.go`, `qml/components/content/BluetoothDevices/BluetoothDevices.qml`, `qml/components/content/WifiNetworks/WifiNetworks.qml`, `qml/components/content/parts/WifiJoinForm.qml`, `qml/components/content/parts/ConnectionDetails.qml`
> **Config:** `Apps.networkEditor` (the Wi-Fi menu's Settings button), `Bluetooth.pairingAgent` (no reader: the daemon reads it)
> **Related:** [Services pattern](../core/services-pattern.md), [VPN](vpn.md), [Prompts](prompts.md)

Wi-Fi and wired state, built on Quickshell's Networking module, and Bluetooth, which axiom's daemon follows (`bluez`). Throughput is not here: it stays in SystemManager. VPNs are VpnManager's ([VPN](vpn.md)).

### NetworkingManager
- Wi-Fi over `Quickshell.Networking`: NetworkManager over D-Bus, event-driven. Nothing runs `nmcli`. What Quickshell doesn't show goes through axiom's `nmnet` (below).
- **Radio:** `wifiEnabled`, `setWifiEnabled`; IPC `wifi enable|disable|toggle` (the `wifi` keybind action). In `qml/shell.qml`'s `_services`, so it answers with no Wi-Fi widget shown.
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
- **Connection notes:** with `Notifications.quiet.connectivity`, the primary connection coming and going (by its name), and in BluetoothManager each device connecting and disconnecting (by address), are noted silently through a `ConnectionNotes` child ([Notifications](notifications.md) › What the shell sends).
- Not named `Networking`, which is Quickshell's singleton. (Rule: AGENTS.md › Services.)

### nmnet (axiom)
What the Wi-Fi menu asks NetworkManager beyond Quickshell.Networking, over the system bus (a new connection per call; nothing here is followed):
- **`net.details {device}`:** `HwAddress`; a wire's `Speed`, or Wi-Fi's `Bitrate` and the access point's `Frequency` (band and channel worked out by `band`); `Ip4Config`'s address with its prefix, `Gateway` and `NameserverData`; `Ip6Config`'s first address that isn't link-local.
- **`net.join {device, ssid, hidden, security, password, identity, anonymousIdentity, eap, phase2, caCert, systemCa}`** (from the shell only, as it carries a password; over the socket, never argv): `wifiSettings` builds the profile (pure, table-tested): `wpa-psk`; WEP (`key-mgmt none`, `wep-key-type` 1 for a 5/13-character or 10/26-hex key, else 2, a passphrase); PEAP or TTLS (`wpa-eap`, an `802-1x` setting with the inner method, identities, and the CA as a `file://` path or `system-ca-certs`); dynamic WEP (the same over `ieee8021x`); LEAP. A profile already saved for the name is updated in place and activated, so a second try with a corrected password replaces the first; else it's `AddAndActivateConnection`.
- **`net.savedWifi`, `net.setAutoconnect {uuid, on}`:** the update sends the profile's secrets back with it (`GetSecrets` for `802-11-wireless-security` and `802-1x`, as nmcli does), or NetworkManager would drop those it keeps.

### The Wi-Fi menu
`content/WifiNetworks`, the Network widget's popout:
- **Header:** the radio switch (none, and titled Network, without a Wi-Fi adapter), then icon buttons as high as it: Settings (`Apps.networkEditor`), Import VPN (red while `VpnManager.importError`) and airplane mode.
- **The connection:** a `FoldRow` folding open `ConnectionDetails`, folded until clicked.
- **VPN section:** folded to one row ([VPN](vpn.md)). Left out, with Import VPN, when the card's `showVpn` or the widget's `popoutVpn` is off (`showsVpn`; the popout's arrives through `extraData` after it's built, so VPN data is acquired as it changes).
- **Networks:** `NetworkRow`s; a secured one has a lock (`badge` for enterprise) on its signal icon (`DeviceRow.iconBadge`), so every row's name and buttons line up. A known one's hover shows autoconnect before forget (`DeviceRow.hoverActions`, over the end of the name), and one that doesn't join on its own says "manual" in its status. An unsaved secured one opens a password field (WPA) or a `WifiJoinForm`, Connect beside its last field.
- **Footer:** Hidden network (a `WifiJoinForm` with `hidden`, closed once NetworkManager takes it).
- **Room:** the window never grows while shown: `maxImplicitHeight` keeps, beside the list's growth, each folding part's most less what it shows now (details, the VPN rows, the hidden form). Focus lost to the file picker (a CA certificate) doesn't cancel the form.

### BluetoothManager
- Reads axiom's `bluetooth` topic (below), as DrivesManager reads `drives`: `bluetooth.get` after each hello, then every `bluetooth.state`. Nothing imports `Quickshell.Bluetooth` (`check_structure`): a pair, a connect and (later) the pairing agent must all be the daemon's BlueZ client.
- **State:** `adapter` (the default one, else null), `available`, `enabled`, `blocked`, `discovering`; `devices` sorted by name, `pairedDevices`, `discoveredDevices` (unpaired and named, in the order they turned up), `connectedDevices`. Lists keep their order (not connected first), so a row never jumps away from the pointer that just clicked it.
- **Devices** are plain objects, made anew on every push: `address`, `name` (the alias), `deviceName`, `icon`, `paired`, `bonded`, `trusted`, `blocked`, `connected`, `state` (`connecting`, `connected`, `disconnecting`, `disconnected`), `pairing`, `battery` (a 0–1 ratio) and `batteryAvailable`. Compare them by `address`; `deviceByAddress(address)` gives the current one, `busy(device)` says a call on it is running.
- **Actions:** `setEnabled` / `toggleEnabled` (`bluetooth.setPowered`); `toggleDevice`: connected disconnects, paired connects, new pairs (`bluetooth.pair`: trust, pair, connect, in the daemon); `forget` (`bluetooth.forget`). A failure only puts the row back as it was.
- **Discovery:** runs while something holds `acquireDiscovery(owner)` (a BluetoothDevices menu on its Discover tab) and the adapter is on, so two menus share one scan (`bluetooth.discovery {on}`, sent again after a hello). The scan is the daemon's own BlueZ session, so stopping it never ends another app's.
- **Connection notes:** the connected devices' labels feed a `ConnectionNotes` child, replaced only when they change (every push makes new objects).
- **Pairing requests:** each `bluetooth.agentRequest` becomes a `PromptManager.request` ([Prompts](prompts.md)), by kind: `confirm` "Does {device} show {code}?" with Pair / Cancel; `pin` and `passkey` a field (a passkey's digits only, at most 6; a PIN at most 16) with Pair / Cancel; `display` the code large, the digits typed lit, with Cancel, which also sends `bluetooth.cancelPair`; `authorize` and `authorizeService` Allow / Deny. An answer is `bluetooth.agentReply {id, accept, value}`; Escape and a click outside decline. A display pushed again updates its prompt (`PromptManager.update`); `bluetooth.agentDone` withdraws it; a hello withdraws them all (a new daemon asks nothing of the old one's).
- IPC `bluetooth enable|disable|toggle` (the `bluetooth` keybind action), the adapter's power. In `_services` too. Inert on the login screen (`Paths.greeter`), whose axiom serves no `bluetooth.*`.
- Not named `Bluetooth`: the name is the `Bluetooth` bar widget file's.

### bluez (axiom)
BlueZ on the system bus (`backend/internal/bluez`, wired in `daemon/bluetooth.go`), shaped like `udisks`:
- **Following:** `GetManagedObjects` once, then every `org.bluez` signal through one `Match{Sender}` subscription, so a device's property change is read after its `InterfacesAdded`; read again when BlueZ's owner changes and when the bus comes back. Signals are gathered for 50 ms into one state (as `nmvpn` does), pushed as `bluetooth.state` (latest-wins) only when it changed.
- **The default adapter** is the first by its path (hci0 before hci1), as Quickshell's `defaultAdapter` was the first adapter it knew. Only its devices are shown.
- **State:** `{available, adapter, devices}`. `adapter` is `{address, name (alias), powered, blocked, discovering, discoverable, pairable}` or null; `blocked` is `PowerState` `off-blocked`, else (powered off) an rfkill switch named after the adapter, soft or hard, in `/sys/class/rfkill`. Each device is `{address, name (alias), deviceName (its own Name, "" none), icon, paired, bonded, trusted, blocked, connected, state, pairing, battery (Battery1's 0–100, -1 none)}`, in the order they turned up. BlueZ has no connecting state: `state`'s `connecting` / `disconnecting` and `pairing` come from the daemon's own calls in flight, and the call's end is shown once its signals settled, so a connect never flashes disconnected.
- **Methods** (the shell only; BlueZ's errors become `axerr` kinds: `busy`, `unavailable` (powered off), `not_authorized`, `refused` (pairing cancelled or rejected, rfkill), `not_found`, else `failed` with BlueZ's message): `bluetooth.setPowered {on}`, `bluetooth.discovery {on}` (wanted again after BlueZ restarts), `bluetooth.connect` / `disconnect` / `pair` / `cancelPair` / `forget {address}` (`forget` is `Adapter1.RemoveDevice`). A device with a call running refuses another (`busy`). A pair or connect can take many seconds: each waits in its own RPC goroutine, nothing else does.
- **Tests:** a fake BlueZ on `dbustest` (`bluez_test.go`): the sync, each signal kind, BlueZ restarting, each method, the transitional states, discovery as a per-client session; the agent in `agent_test.go`.

### The pairing agent
BlueZ runs a `Device1.Pair` against the calling connection's agent, so the agent sits on the service's own bus connection, beside Pair and Connect (`backend/internal/bluez/agent.go`, modelled on `nmvpn`'s secret agent):
- **Registering:** `org.bluez.Agent1` is exported at `/org/axiom/bluetooth/agent` on every connection; while `Bluetooth.pairingAgent` is on (default; the daemon's `bluetoothPart` reads it at the start and on every config change, `SetAgent`) the run loop calls `AgentManager1.RegisterAgent` (capability `KeyboardDisplay`) and `RequestDefaultAgent`, so it's asked for pairs a device starts too. It registers again after every sync (BlueZ restarting, the bus coming back). Turned off, `UnregisterAgent`, and whatever was asked is rejected: another agent (blueman) answers then.
- **Requests that ask** hold their D-Bus reply (`Defer`): `RequestPinCode`, `RequestPasskey`, `RequestConfirmation`, `RequestAuthorization`, and `AuthorizeService` for a device that isn't trusted (a trusted one is answered at once). Each pushes `bluetooth.agentRequest {id, kind (pin|passkey|confirm|authorize|authorizeService|display), device {address, name, icon}, code (six digits for a passkey), entered (-1 unless a shown passkey), service (the UUID an authorizeService asks for)}`; the shell answers with the shell-only `bluetooth.agentReply {id, accept, value}` (a PIN 1–16 characters, a passkey 0–999999, else `bad_request` and it still waits); declined is `org.bluez.Error.Rejected`.
- **Codes shown:** `DisplayPinCode` and `DisplayPasskey` push a `display` request, and the same id again as `DisplayPasskey` counts the digits typed (`entered`). It ends when the device's `Paired` turns true, the daemon's `Pair` call returns or `cancelPair` runs.
- **Ending:** `Cancel` and `Release` end every open request (those waiting answer `org.bluez.Error.Canceled`), as does BlueZ going away; each ended or answered one pushes `bluetooth.agentDone {id}`.
- **Nobody to ask:** with no shell connected (subscribed to `bluetooth`) a request is rejected at once, so the pairing fails fast instead of timing out.
- Only BlueZ (the bus name's owner) may call it: anything else is rejected.
- **Testing:** never against the live BlueZ (AGENTS.md › Never): the fake in `bluez_test.go` exports `AgentManager1`, and `agent_test.go` calls each method as BlueZ would. The daemon's tests point `DBUS_SYSTEM_BUS_ADDRESS` at nothing, so they never reach the machine's BlueZ.
