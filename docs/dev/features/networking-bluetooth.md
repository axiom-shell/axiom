# Networking and Bluetooth

> **Files:** `services/NetworkingManager.qml`, `services/BluetoothManager.qml`
> **Config:** none
> **Related:** [Services pattern](../core/services-pattern.md)

Wi-Fi, wired and Bluetooth state, built on Quickshell's D-Bus modules. Throughput is not here: it stays in SystemManager.

### NetworkingManager
- Wi-Fi over `Quickshell.Networking`: NetworkManager over D-Bus, event-driven. Nothing runs `nmcli`.
- **Radio:** `wifiEnabled`, `setWifiEnabled`.
- **`networks`:** sorted connected first, then saved, then by name. The order is fixed.
- **Actions:** connect, disconnect, forget.
- **Password prompt:**
  - `passwordFor` and `connectWithPsk`;
  - asked again after a `NoSecrets` failure.
- **Primary connection:**
  - `primaryDevice` prefers wired over Wi-Fi.
  - `netInfo` is `{ kind, name, device, signal, ip }`, all bindings.
  - The one exception is the IPv4 address, which Quickshell.Networking lacks. It comes from axiom (`net.addresses`, the interface's addresses read in Go; in the greeter, which has no daemon, `axiom net address`, the same answer from the CLI) whenever the connection changes, or on `refreshIp()`; an answer for a lookup since replaced is dropped.
- **Scanning:** the scanner runs only while something holds `acquireScan(owner)`.
- Not named `Networking`, which is Quickshell's singleton. (Rule: AGENTS.md › Services.)

### BluetoothManager
- Over `Quickshell.Bluetooth`: adapter power, scanning, sorted device lists, and connect / pair / forget.
- Not named `Bluetooth`: that would shadow Quickshell's singleton, and the name is also taken by the `Bluetooth` bar widget file.
