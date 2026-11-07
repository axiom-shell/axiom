# Prompts

> **Files:** `qml/services/ui/PromptManager.qml`, `qml/shell/Prompt.qml`, `qml/components/surfaces/prompt/PromptWindow.qml`, `qml/components/surfaces/prompt/PromptCard.qml`, `qml/components/surfaces/prompt/PolkitCard.qml`
> **Config:** none (its sources' own: `Polkit.enabled`, `Bluetooth.pairingAgent`)
> **Related:** [Polkit](polkit.md), [Networking and Bluetooth](networking-bluetooth.md) › The pairing agent, [VPN](vpn.md), [Removable drives](drives.md), [Shared UI pieces](../core/shared-ui-pieces.md)

One prompt for every password, PIN or confirmation the system asks for. **The rule:** a request the system starts goes here; a form the user opens by clicking in a menu stays in its row.

### Its sources
| Source | Service | Asks here | Stays in its row |
|---|---|---|---|
| polkit | `PolkitManager` | every authentication (`content: "polkit"`) | — |
| Bluetooth pairing | `BluetoothManager` | the pairing agent's requests (confirm, PIN, passkey, a code to type, authorize) | — |
| VPN secrets | `VpnManager` | every `vpn.secretRequest` (NetworkManager asking at connect time, whoever started it) | — |
| Wi-Fi passwords | `NetworkingManager` | a `NoSecrets` failure with no Wi-Fi menu holding the scan (an autoconnect, a join from elsewhere): WPA, WEP, LEAP; `waits` | a secured network clicked in the menu, or a failure while one is open; an enterprise network always (its form is the menu's) |
| Drive unlocks | `DrivesManager` | a Locked card's click or a notification's Unlock (`promptUnlock`); `waits` | a row's Unlock, opening a locked drive from its row or the Drives widget |

### The queue (`PromptManager`)
- **One request at a time.** Requests queue in the order they came; the first is `current`, the rest wait behind it. So two requests never fight over the screen: a pairing prompt asked while polkit's is open shows once polkit's ends.
- **`request(spec, onAnswer, onCancel)`** queues one and returns its id (`"prompt-<n>"`). `spec`, every key optional:
  - `source` (who asks, for logs and the doc), `icon` (a Material glyph), `title`, `message`;
  - `code` (shown large: a PIN or passkey) and `entered` (how many of its digits are typed, lit; -1 none);
  - `fields`: `[{key, label, secret (default true), digits, maxLength}]`, each a `PasswordEntry` (a digits field takes only digits);
  - `actions`: `[{id, label, primary, icon}]`, the buttons, in order; the primary one is accented, runs on Enter, and only once every field is filled. `cancelOr(id, label)` gives the usual pair: Cancel (id `cancel`), then the primary one;
  - `error`: shown under the last field (or alone with none);
  - `waits` (default false): answered, the request stays, busy, until its source `update`s it with an error (asked again) or `withdraw`s it; else it goes at once;
  - `outsideCancels` (default true): a click outside the card cancels it;
  - `content`: `"polkit"` draws `PolkitCard` (PolkitManager's flow) in place of the fields and actions.
- **`onAnswer(actionId, values)`**: a button was clicked or Enter pressed (`values` by field key). **`onCancel()`**: Escape, or a click outside. Every button goes to `onAnswer`, Cancel and Deny included: the source tells them apart by id.
- **`update(id, changes)`** changes a queued request's keys: the code as a keyboard types it, or an `error` after a wrong answer (which clears busy and counts an `attempt`: the card clears its fields and shakes the last).
- **`withdraw(id)`** removes one its source ended (BlueZ cancelled, polkit's flow ended), calling neither callback.
- **`screenName`**: the monitor the shown request is on, `CompositorManager.focusedOutput || General.primaryMonitor` when it came to the front (polkit's own pick before).
- Nothing survives a reload: the sources queue again (PolkitManager its open flow; the daemon's pairing requests end with their pairing, and a VPN's with NetworkManager's timeout; a Wi-Fi password or a drive unlock is asked again by trying again).

### The window (`PromptWindow`)
- One per screen (`qml/shell/Prompt`, `Variants` over `General.outputs`), lifted from polkit's: each dims its screen, the card on `screenName`'s only (`General.screensNamed`, the primary when that screen is gone).
- `WlrLayer.Overlay`, namespace `axiom-polkit` (named for the prompt it began as: the layer rules and their recorded test cases know it so; [layer stacking](../generated/layers.md)); exclusive keyboard only on the card's screen; registered with `SurfaceManager.registerModal`, so a prompt over the overlay closes no focus grab; the dim blurs where backdrops blur (`BlurManager.backdropRegionsOn`).
- It keeps the request drawn while the card fades out after it ends.
- The card is a `Loader`: `PolkitCard` for `content: "polkit"`, else `PromptCard`. The window asks the card for the keyboard (`focusWanted`) when a request comes to the front, the card loads or the screen becomes its.
- **`PromptCard`:** the icon, title and message; the code (each digit a monospace glyph, the typed ones in the accent); the fields; the error; key hints and the buttons. For 400 ms after a request shows it takes no keys and runs no action, so typing or an Enter meant for another window doesn't answer it.

### Adding a source
- Call `PromptManager.request` from the service that owns the request (never from UI), keep the id, and `withdraw` it when the request ends elsewhere. A source that checks the answer (a password that may be wrong) sets `waits` and `update`s an `error`.
- English text inline through `I18n.tr` with placeholders, as everywhere.

### Testing
- Never trigger a real polkit prompt or a real pairing on the live shell from an agent session (AGENTS.md › Never); the pairing agent's Go side is tested on the fake BlueZ (`go test ./internal/bluez`).
- On a nested shell, a request can be queued from a scratch QML file or a temporary `IpcTarget` calling `PromptManager.request`.
