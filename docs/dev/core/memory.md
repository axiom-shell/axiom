# Memory

> **Files:** `scripts/dev/mem.sh`, `scripts/dev/bench_overlay.sh`, `scripts/dev/nested.sh`, `backend/internal/supervise/supervise.go`
> **Config:** none
> **Related:** [Streamed building](streamed-building.md) (timing the same cycles), [Testing](../testing.md), [roadmap](../roadmap.md) › Phase 12

How to read the shell's memory, and the baseline every [Phase 12](../roadmap.md#phase-12-memory-footprint) entry is judged against. Almost all of qs's memory is C++ heap and per-window renderer state, not JS: measure before changing anything, and compare against the table below.

### Reading it
- `scripts/dev/mem.sh [-H] PID` prints one line, in MB: `rss`, `dirty` (Private_Dirty), `anon` (Anonymous) and `huge` (AnonHugePages) from `/proc/PID/smaps_rollup`; `js` and `js_live`, the JS heap at the last GC (the managed chunks it held, and what was still live after the collection); `thr`, the threads, and `render`, the `QSGRenderThread`s among them (one per window that has drawn). `-H` adds the column names.
- The JS heap comes from the instance's log: qs logs its collections only with `QT_LOGGING_RULES=qt.qml.gc.allocatorStats.debug=true` in its environment (quickshell's own Qt log filter doesn't block it). Without it those columns are `-`. There is no way to read it from outside; the rule logs about 30 lines per GC to that instance's log only, so set it on a nested shell, never the live one.
- `scripts/dev/bench_overlay.sh -p PID --mem -n CYCLES [PAGE…]` drives the overlay of the qs `PID` (`qs ipc --pid`, never `--newest`, which hits the live shell) through CYCLES open, page…, close cycles and prints a reading before the first and after each.

### Measuring in a nested session
Anything the variable or the experiment sets goes in the environment `scripts/dev/nested.sh` is started with: the nested compositor, its axiom and the shell all inherit it. In zsh, write the assignments out (`VAR=value scripts/dev/nested.sh niri`); `env $E` with spaces in `$E` doesn't split, and the run silently falls back to the live dirs.

```sh
QT_LOGGING_RULES=qt.qml.gc.allocatorStats.debug=true scripts/dev/nested.sh niri &
P=$(pgrep -f '^qs -p' | grep -vx <live qs pid>)   # the nested qs; wait for its "Configuration Loaded"
scripts/dev/bench_overlay.sh -w 1 -n 10 -p "$P" --mem Settings Themes
```

Wait about 20 s after `Configuration Loaded` before the first reading, take one more 30 s after the last cycle, and close the nested window (kill only the nested compositor you started) before the next run, so each starts fresh.

### Transparent huge pages
The shell runs with transparent huge pages off (maintainer, 2026-10-27: "yes, opt the shell out of THP"): its heap is freed in small pieces, which a huge page holds until all of it is free, so with THP `always` they kept 110–125 MB that was never returned (the table below). The flag (`PR_SET_THP_DISABLE`) belongs to a process and is inherited by its children, and Go's `os/exec` runs nothing between fork and exec, so the supervisor (`supervise.Options.NoTHP`, set by the daemon) starts the running image, `/proc/self/exe exec-no-thp qs -p <tree>`, which sets the flag on itself and execs qs in its place (`supervise.ExecNoTHP`; same pid, process group and environment). Only qs and what it runs itself go without: the daemon and the commands it runs for the shell keep huge pages. `grep THP_enabled /proc/<pid>/status` shows it (0 for qs). A kernel refusing the flag leaves huge pages on rather than the shell not starting.

### Baseline
2026-10-27: nested niri (one 1656×1301 output), the default config, Qt 6.12.0, quickshell 0.3.2, THP `always`; a cycle is open, Settings, Themes, close with `-w 1`. MB:

| Run | rss before | rss after 1 | rss after 10 | 30 s later | dirty after 10 | huge after 10 | js / live | render |
|---|---|---|---|---|---|---|---|---|
| baseline | 510 | 622 | 612 | 591 | 372 | 156 | 27 / 12 | 15 |
| `GLIBC_TUNABLES=glibc.malloc.arena_max=2:glibc.malloc.trim_threshold=131072` | 516 | 612–619 | 612–616 | 591–598 | 372–376 | 142–156 | 27–28 / 12 | 15 |
| THP off (`PR_SET_THP_DISABLE` before exec'ing qs; shipped since) | 398 | 499 | 500 | 466 | 260 | 0 | 26 / 12 | 15 |
| both | 399 | 496 | 492 | 471 | 252 | 0 | 26 / 12 | 15 |

(The tunables row is two runs.) What it says:
- The JS heap is 20–30 MB, 10–12 MB live: a few percent of RSS.
- The first cycle adds about 100 MB, which then stays flat over the next nine: built once and kept (pages, their windows' renderer state), not leaked per cycle.
- Fewer arenas and a fixed trim threshold change nothing measurable: the heap isn't stranded in idle arenas.
- THP off saves 110–125 MB at rest and after use (all of AnonHugePages, and Private_Dirty with it): huge pages are what holds memory that's freed in small pieces. Shipped: a nested niri started by the daemon read 396 MB RSS, 0 huge after load (the daemon itself kept its huge pages).
- The live shell, on the user's config, read 1375 MB RSS (868 dirty, 326 huge, 114 threads, 20 render threads) the same day: the nested default config is the reproducible baseline, not the worst case.
