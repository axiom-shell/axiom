# dbus-wayland
reviewed: 47db042 2026-11-01  (full)

The D-Bus and Wayland wire layers are sound (spec limits enforced, fuzzed without a panic, descriptors closed on every path). The open problem is the shared Wayland connection's failure path: a protocol error leaves every client claiming its protocol.

## Open findings
- Major: "A Wayland protocol error leaves every client claiming its protocol" (fixed, row 20 core-ui-theming-03)
- Cleanup: "Three Wayland client members nothing in the daemon calls" (fixed, row 20 core-ui-theming-01)
- Minor: A call abandoned on its deadline can leak its reply's descriptors: `backend/internal/dbus/conn.go:298` (`Conn.Call`); a reply buffered in the call's channel as ctx ends is never closed. Fix: after `c.forget(serial)`, drain `ch` and `Close` it.
- Minor: dbus.md's intro lists only idle and brightness as users; nmvpn, filepicker and theme/effects.go also dial the bus.

## Contract
Holds: unix path=/abstract= only, EXTERNAL + NEGOTIATE_UNIX_FD + Hello; one reader and one dispatcher goroutine with Done/Err; error kinds by name; local signal filtering (well-known Sender by the bus only), 64-deep queues dropping the newest and closing its fds; Export's signature check, Defer once, Introspect with children, Peer; every spec limit on decode and encode, both byte orders; unixmsg CLOEXEC, FIFO, untaken fds closed. Wayland: id reuse after delete_id; display error ends Run; Fd sends a dup; SealedFile fully sealed; client.Run ordering (Start, globals, Ready after two syncs); outputs v4 + xdg v3 and Names semantics; vkbd limits; keyhold mapping and release paths. Checks: ReadMessage fuzzed 45 s (5.1M inputs), no panic; go test -race passes; idle redials dropped buses after Retry. Does not hold: wayland.md's "every flag reads off" before ready (in the Major).

## Coverage
Read deeply: backend/internal/dbus (non-test), unixmsg, wayland/wire, wayland/{client, seat, outputs, datacontrol, keyhold, gamma, ctm, idlenotify, vkbd}, daemon/{wayland, switcher}.go, services/core/WaylandManager.qml · Outlined: daemon/daemon.go (beyond its Wayland parts), dbus/dbustest, wayland/wire/wiretest, tests and fixtures · Skipped: none.

## History
- 2026-11-01 full: 4 findings (1 Major, 1 Cleanup, 2 Minor); recorded
