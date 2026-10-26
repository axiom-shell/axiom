# Merging user binds (managed mode)

> **Files:** `backend/internal/compositor/binds/`, `backend/internal/compositor/manager/hypr.go`, `services/compositor/CompositorConfigManager.qml` (`mergeUserBinds`, `previewMerge`), `backend/internal/compositor/actions/`, `components/methods/BindKeys.qml`, `components/methods/BindActions.qml`
> **Config:** `Keybinds.binds`
> **Related:** [Managed takeover](managed-takeover.md), [Keybinds](keybinds.md), [Config modes](config-modes.md)

`mergeUserBinds(only)` moves the binds in `user/*.lua` into `Keybinds.binds`, so axiom owns them and nothing is bound twice. It works in managed mode only.

### Entry points
- The Keybinds page's Merge button.
  - When the page opens, `previewMerge()` counts the binds it would move (`mergeable`).
  - While there are binds to move, the button shows in place of "Remove binds your Hyprland config also has".
- A claim merges only the adopted file's binds, through `mergeUserBinds(name)` (`extract --only`) ([Managed takeover](managed-takeover.md)).

### Where it runs
- The merge is the binary's (`backend/internal/compositor/binds`, every compositor's `extract` and `remove` with the same JSON, documented in its package comment). The daemon runs it (managed mode: the adopted file on a takeover, all of `user/` on the Keybinds page's Merge, `compositor.merge` / `compositor.previewMerge`); `axiom compositor binds extract|remove --kind K DIR [SITES]` runs it from the command line.
- What a command calling axiom (`axiom ipc …`, `axiom lock`, `axiom restart`) or a volume, brightness or media command maps onto comes from `compositor/actions`, which reads `BindActions.qml`'s `ipcActions` and `actionFlags` from the tree, so a new IPC action needs no Go change.

### Extracting
- It runs the files under gopher-lua (Lua 5.1), with no `lua` binary.
  - The daemon runs them in a child (`axiom compositor binds extract --memory-limit`, its own image through `/proc/self/exe`) that caps itself at 1 GiB (`RLIMIT_DATA`, `binds.MemoryLimit`): gopher-lua has no heap limit, and a file building a huge string allocates it in one instruction, so only the kernel can refuse it, and then only the child dies, never the daemon (the shell's parent). The merge then fails with what happened, and nothing moves. Refused memory, the Go runtime usually says `out of memory`, but inside its collector it may crash with a SIGSEGV instead: a child that crashed (killed by a signal, or the runtime's `fatal error` / `SIGSEGV` on stderr: `binds.crashed`) holding a quarter of the limit (peak RSS, `ProcessState.SysUsage`) is reported as too big too, since reading the files takes a few MiB; a crash below that reads as a crash, and the child's own error (a Lua error from a large file) reads as itself whatever its peak. A vforked child's peak counts the daemon's memory at exec, so a peak the daemon itself reached (its own `RUSAGE_SELF`) reads as a crash too (`binds.diedOfMemory`).
  - In any process, `string.rep` refuses a result over 16 MiB and the call stack is bounded.
  - Each file is required as `user.<name>` against a stand-in `hl` that records `hl.bind`/`hl.unbind` with their file and line.
  - Because the files really run, variables, string building and loops work.
  - Limits:
    - `io.popen` reads empty, `io.open` only reads, `os.execute`, `os.remove` and `os.rename` do nothing, and there's no `debug` library (`require("io")` and `package.loaded.io` are the stand-in too)
    - `print` goes nowhere
    - a stand-in value lists as empty
    - submap and `hl.on` handlers aren't seen
    - the run stops after 30 s (a file that never ends), and nothing moves.
  - A file using Lua 5.4's syntax (`//`, `goto`, `<const>`, bitwise operators) doesn't parse under 5.1: it's one of the `errors`, and its binds stay. `table.unpack`, `table.pack` and `math.type` are there.
- Each dispatcher is mapped onto an action:
  - `exec_cmd` of wpctl/pactl/brightnessctl/playerctl → the media actions
  - the example config's exit command → `exitSession`
  - any other exec → `exec`
  - focus/move/float/pseudo/togglesplit/special/drag → their own actions
  - anything else → the `raw` action (`compositor: hyprland`), with the dispatcher as written.
- Hyprland's example config maps completely.
- **Remapped keys.** Binds from an adopted `00-previous*.lua` on keys axiom's defaults use are moved (`exampleKeys`) and reported in `remapped`. A key in the user's other files was their own choice, so it isn't moved.
  - togglesplit: `SUPER + J` (focus down) → `SUPER + X`
  - the special workspace: `SUPER + S` / `SUPER + SHIFT + S` (WASD's down) → `SUPER + V` / `SUPER + SHIFT + V`
  - float: `SUPER + V` → axiom's `SUPER + Z`.

### What can move
- A call moves only whole:
  - every bind it makes must map (a loop makes several)
  - it may use no option axiom's binds lack (`non_consuming`, …)
  - it must be its own statement in a `user/*.lua` file, not in a `user/lib/` module
  - any variable it's kept in must be unused.

### Committing and removing
1. The daemon saves the binds first (`Keybinds.binds`, through the store; refused while the config is read-only, `saveFailed`). The `compositor.bindsMerged` push lets KeybindManager add them to a dirty draft.
2. `remove` then deletes those calls, plus any `hl.unbind` of a moved key (it would unbind the moved bind too).
   - It first writes a dated `<file>.axiom-backup-<date>` copy, keeping the file's mode.
   - It leaves a file alone if the result doesn't parse (`luacheck`: `luac -p` where it's installed, else gopher-lua).
   - A file it can't read, back up or write is failed (`io`) and the others go on, so what was deleted is always known.
3. Whatever it couldn't delete (`failed`, per file or per call) is taken back out.
   - The binds are committed again as `mergeBinds(before, binds from the sites that went)`, so no key is bound twice.
   - Only the binds that went are sent to `bindsMerged`.

### Duplicates and results
- Moved binds get ids as they're saved (`manager.withIDs`, the same rule as `BindKeys.withIds`: from the key, `super-y`), as the schema requires one.
- A key axiom already binds stays one bind. `BindKeys.mergeBinds` puts the moved bind in place of axiom's, because the user's config loads after axiom's layer and so was the one in effect. A paused bind holds no key, so it's never the one replaced: a preset's bind put after it on that key is. It does the same in a draft with unsaved edits.
- Reasons are codes (listed in the `binds` package comment), translated by `BindEditor.reasonText`. `tracked` names files that are in a git repository.
- `lastMerge` shows above the bind list. Its fields are `moved`, `removed`, `kept` (with reasons), `failed`, `remapped`, `tracked`, `errors` and `saveFailed`.
