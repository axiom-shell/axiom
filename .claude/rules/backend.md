---
paths:
  - "backend/**"
---

# The axiom binary (`backend/`)

Go source of `axiom`: parent of the shell and greeter, owner of config.json, the command line. How it works: `docs/dev/backend/README.md`. `cmd/axiom/` only hands `os.Args` to `cli.Main`; every package is under `internal/`; `go generate` programs under `tools/`.

## Rules
- **Pure core, effects at the edge.** Pure packages (`axerr`, `jsonx`, `schema`, `config`, `migrate/…`, `share`, `compositor/kdl|actions|render`, `theme/palette|integrations`, `hookup`, `xkb`, `filesearch`, …: the list is `internal/archtest`) say `Pure:` in their doc comment (only they), do no I/O and import none of `os`, `os/exec`, `os/signal`, `net`, `syscall`, `golang.org/x/sys`, `io/ioutil`, `plugin`, `unsafe` (their tests may). Imports point down the tiers pure → edge → `daemon` → `cli` → `cmd/`, `tools/`. Every package is placed in a tier in archtest, which fails on one it doesn't know. Archtest doesn't order edge packages among themselves: keep their imports pointing at lower-level ones (`fsx`, `xdg`, `rpc`) by review.
- **No globals, no `init()`.** Package-level variables are read-only tables (regexps, maps, sentinel errors, `go:embed`, `sync.OnceValue`); an exception is listed with its reason in archtest. State lives in structs built from an `Options` (logger, clock, paths injected) so tests build their own. `context.Context` first on anything that blocks; every goroutine has an owner that stops it.
- **One error type across boundaries**: `axerr.Error` with a `Kind`; RPC codes, exit codes and what the shell shows come from the kind. Messages stay English (the shell translates by kind). Wrap with `%w`.
- **The config is a tree, not structs**: migrate, prune, defaults, validate and write work on the ordered `jsonx` tree, so key order, unknown keys and old shapes survive. Generated structs are read-only views.
- **The schema is the source of truth**: never hand-copy a key list, default or annotation into Go; read it through `schema` or generate from it.
- **Embedded files are generated copies** (`internal/assets/data/`, by `tools/syncassets`): edit the originals. A fresh clone needs `scripts/generate.sh` before it compiles.
- **CLI commands are entries in the command table** (`internal/cli`): help, completions and docs come from it. A command parses, calls a library package or the daemon, and prints through `Env.Output` (text, or one JSON value with `--json`).
- **Security-relevant code** (sockets, locks, runtime dirs, atomic writes, the child's environment, the lock screen path) follows `docs/dev/backend/README.md` › Security, and every check there has a test.

## Style
- Every package has a doc comment (it feeds `docs/dev/generated/files.md`); exported names are documented; comments say why.
- Tests are table-driven with `t.Parallel()`, hand-written fakes, files in `t.TempDir()`. Wait with `testkit.Eventually` or a `select` bounded by `testkit.Bound(d)`, never a bound of your own (CI stretches them via `AXIOM_TEST_WAIT_FACTOR`). Behaviour shared with QML is tested through the shared fixtures (`docs/dev/backend/README.md` › Shared fixtures), never restated inline.
- Generated Go files are `zz_generated_*.go` with the standard `// Code generated … DO NOT EDIT.` line.

## Dependencies
Standard library first. A new module must be pure Go (`CGO_ENABLED=0`) and gets a row here saying why.

| Module | Why |
|---|---|
| `honnef.co/go/tools` (tool) | staticcheck, pinned in go.mod's `tool` block |
| `golang.org/x/vuln` (tool) | govulncheck, pinned the same way |
| `go.yaml.in/yaml/v3` | reads the schema's YAML source (`schema/yamlsrc` adds the strictness) |
| `github.com/dop251/goja` | runs the frozen format-1 migrations (`migrate/legacy`, `legacy.js`) exactly as the shell did, instead of a port that could drift |
| `github.com/yuin/gopher-lua` | runs a user's Hyprland Lua sandboxed for the bind merge (`compositor/binds`), checks edits still parse without `luac` (`compositor/luacheck`), runs `compositor/render`'s Lua in tests |
| `github.com/fsnotify/fsnotify` | inotify without cgo: `store` watches config.json, dev mode (`daemon/dev.go`) watches the tree and binary |
| `golang.org/x/image` | BMP and WebP decoding for theme generation and launcher thumbnails |
| `github.com/teambition/rrule-go` | RFC 5545 recurrence for calendars (`calendar/ical`), matching the dateutil expansion it replaced |
| `golang.org/x/sys` | Linux calls `syscall` lacks: peer credentials (`rpc`, `wayland/wire`), fd passing (`unixmsg`), `flock`/`O_NOFOLLOW` (`fsx`), memfds, close-on-exec across re-exec (`daemon`), inotify open/close (`camera`) and `IN_DONT_FOLLOW` watches (`fileindex`), scheduling and I/O priority (`procprio`), the bind merge child's memory limit |

## Checks
`scripts/check_go.sh` (generate, gofmt, vet, staticcheck, `go mod tidy`, tests with `-race`; `--fix` regenerates and formats; `--ci` adds govulncheck). verify.sh runs it when `backend/` or an embedded file changed.
