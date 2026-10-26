# D-Bus

> **Files:** `backend/internal/dbus/`, `backend/internal/dbus/dbustest/`, `backend/internal/unixmsg/`
> **Related:** [The axiom binary](README.md), [Wayland protocols](wayland.md), [Roadmap](roadmap.md)

The daemon's own D-Bus client: pure Go, no library, written for what axiom asks of a local bus. Idle (roadmap stage 2) is its first user: logind on the system bus, `org.freedesktop.ScreenSaver` on the session bus. The services Scope lists as planned (notifications, tray, UPower, Mpris, …) build on it.

### The connection
- `dbus.Dial(ctx, address, Options)`:
  - The address comes from `SessionAddress(getenv)` (`$DBUS_SESSION_BUS_ADDRESS`, else `$XDG_RUNTIME_DIR/bus`) or `SystemAddress(getenv)`.
  - Only unix sockets, `path=` and `abstract=`, are used.
  - It authenticates with SASL `EXTERNAL`, asks for descriptor passing (`NEGOTIATE_UNIX_FD`), says `Hello` and keeps its `UniqueName()`.
- **Its goroutines:**
  - One reads.
  - One runs incoming method calls, in order.
  - Both end with `Close`, or when the bus closes the connection (`Done()` closes, `Err()` says why).
  - Don't call `Close` from a method handler: it waits for the handler.
- **Calls:**
  - `Call(ctx, dest, path, iface, member, sig, args…)` waits for the reply.
  - An error reply is an `axerr` error wrapping `*dbus.Error`:
    - `dbus.ErrorName(err)` tells which.
    - The kind comes from the name: ServiceUnknown and NoReply are `unavailable`, AccessDenied is `refused`, and UnknownMethod and InvalidArgs are `bad_request`.
- **Signals:** `Subscribe(ctx, Match)` sends `AddMatch` and filters locally.
  - A well-known `Sender` is matched only by the bus: signals carry the sender's unique name.
  - A subscriber more than 64 signals behind loses the newest (logged); the reader never blocks.
  - Helpers: `NameOwnerChanged(name)` and `PropertiesChangedMatch` / `PropertiesChanged(msg)`.
- **Exporting:** `Export(path, Interface{Name, Methods, Signals})` answers calls until the returned func unexports.
  - Each `Method` declares `In` and `Out` signatures. A call with another signature gets `InvalidArgs`; an unknown object, interface or method gets its own error.
  - `Introspectable.Introspect` (children included) and `Peer.Ping` / `GetMachineId` are answered for you.
  - At most 64 calls wait for the handler goroutine; past that, callers get `LimitsExceeded`.
  - Exported properties aren't there yet: the first service needing them adds `Properties` to `Interface`.
- Names: `RequestName` (with `NameDoNotQueue`, …), `ReleaseName`, `NameOwner`, `ConnectionPID`.

### Values
Every value is encoded from a signature, never guessed. `MakeVariant` and `SignatureOf` infer one only where a variant needs it.

| Signature | Go |
|---|---|
| `y b n q i u x t d` | `uint8 bool int16 uint16 int32 uint32 int64 uint64 float64` (encoding takes any Go integer in range) |
| `s o g` | `string`, `ObjectPath`, `Signature` |
| `h` | `UnixFD`: sent, the descriptor's number; received, an index: `msg.File(fd)` takes it |
| `v` | `Variant{Sig, Value}` |
| `(…)` | `[]any` |
| `ay as ao` | `[]byte []string []ObjectPath` |
| `a{sv}` | `map[string]Variant`; other dicts `map[any]any` (encoding takes any map) |
| other arrays | `[]any` (encoding takes any slice) |

- `msg.Store(&a, &b, …)` copies a body into typed variables.
- Messages are sent little-endian; both byte orders are read.
- The spec's limits are enforced:
  - signatures up to 255 characters
  - arrays and structs nested up to 32 each
  - values nested up to 64
  - arrays up to 64 MiB, messages up to 128 MiB

### Descriptors
- `unixmsg.Conn` carries them (D-Bus here, and the Wayland connection the same way):
  - Every descriptor received is close-on-exec on arrival (`MSG_CMSG_CLOEXEC`).
  - Descriptors queue in arrival order; each message takes as many as its header names.
  - Closing the connection closes any that nobody took.
- A received message owns its `Files`: whoever gets it takes what it keeps (`File`) and calls `Close` for the rest. A signal matching several subscriptions has its descriptors closed: they can only have one owner.

### Tests
- `dbustest.New(t)` is an in-process bus:
  - EXTERNAL auth, names, `RequestName` and `NameOwnerChanged`, routing by destination, every signal to every other connection.
  - A fake service (logind, a ScreenSaver client) is a second `dbus.Conn` on it that `Export`s what the test needs.
- `conn_test.go` runs each case on the fake and, when `dbus-daemon` is installed, on a real one started with a private config.
