# daemon
reviewed: d51805b 2026-11-01  (full, except the files under Coverage › Not read)

The daemon core holds up: hello guards, the latest-wins queue, in-order calls, the re-exec handoff, supervision and polled topics do what the docs say, and each security rule has a test. Left: 54 lines of dead call paths and helpers, one goroutine past `tasks.Go`, a garbled `axiom daemon status` line, and doc lists behind the code.

## Open findings
- Cleanup: "The shell's unused daemon-call paths" (fixed, row 20 platform-01)
- Cleanup: [Two dead Go helpers and a forwarding wrapper](../../docs/dev/issues.md#two-dead-go-helpers-and-a-forwarding-wrapper)
- Cleanup: [daemon.shutdown starts its goroutine past tasks.Go](../../docs/dev/issues.md#daemonshutdown-starts-its-goroutine-past-tasksgo)

### axiom daemon status runs the config folder into the revision
- **Where:** `backend/internal/cli/run.go:134` (`daemonCommand`)
- **What:** `"config   %srevision %d"` with `Dirs.Config` ending in `/` prints `config   /home/u/.config/axiom/revision 12`. Fix: `"config   %s\nrevision %d\n"`.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the daemon system

### The daemon docs' lists of parts, topics and in-order methods are behind the code
- **Where:** `docs/dev/backend/README.md:25`, `docs/dev/backend/README.md:27`, `docs/dev/backend/protocol.md:31`, `docs/dev/backend/protocol.md:40`
- **What:** README lists 8 of 26 parts; the topic and latest-wins lists miss `vpn`; the in-order list names a nonexistent `config.restore` and misses `switcher.hold` / `switcher.release`. Fix: point at `daemon.go`'s `parts`, add `vpn`, list the five in-order methods.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the daemon system

### A redundant id check in the read loop
- **Where:** `backend/internal/rpc/rpc.go:471` (`readLoop`)
- **What:** `if m.ID != nil` is always true there (notifications took the `continue` at 464). Fix: drop it.
- **Size:** trivial
- **Found:** 2026-11-01, while reviewing the daemon system

## Contract
Holds: hello refusals (protocol, schema, shell pid) and lenient hello decode; nothing before the hello; latest-wins one place, newest data; queue 4096 / 16 MiB / depth 64 / 256 in flight; in-order chaining; pushShapes complete; polled topics start/stop/forget with subscribers, new request fetched at once; re-exec close-on-exec under ForkLock, restored on failure and re-set on adopt; handoff trusted only on this display's held lock; supervisor backoff, give-up after 5/min, orphan stop on exact cmdline; AXIOM_INCOMPATIBLE per start, AXIOM_BIN installed; shell reconnect timing, repeatable resend, listener isolation; each security rule tested.

## Coverage
Read deeply: daemon/{daemon,methods,reexec,contract,tasks,topics,dev}.go, rpc/{rpc,server}.go, supervise.go, topics/topics.go, command/{watch,command}.go, ipcroute.go, BackendManager.qml, cli/run.go · Outlined: Paths.qml, DevManager.qml, IpcTarget.qml, fsx/lock.go, xdg.go, children.go, cli.go, dead-member sweep of every Go file · Skipped (budget): see Not read.

**Not read (budget), to be read by the next pass, full or incremental, whether or not they change:** cli/config.go, cli/greeter.go, cli/compositor.go, command/stream.go, files.go, lockscreen.go, rpc/shape.go, the scripts/dev/*.sh scripts, fixtures.py, syncassets, testkit. Only the dead-member sweep touched them, so this review vouches for nothing else in them. The 14 existing issues.md entries on them weren't rechecked either.

## History
- 2026-11-01 full (11 files and folders not read, see Coverage): 6 findings (3 Cleanups recorded, 3 Minor); recorded
