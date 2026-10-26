# The axiom binary (`backend/`)

Go source of `axiom`: the parent process of the shell and greeter, the owner of config.json, and the command line. Rules here add to the root `AGENTS.md`. How it works: `docs/dev/backend/` (start at `README.md`).

## Layout

```
cmd/axiom/        main: hands os.Args to cli.Main, nothing else
internal/         every package (nothing is importable from outside the module)
tools/            go generate programs (syncassets, …)
```

## Rules

- **Pure core, effects at the edge.** The pure packages (`axerr`, `jsonx`, `schema`, `schema/yamlsrc`, `config`, `migrate/…`, `share`, `compositor/kdl`, `compositor/actions`, `compositor/render`) say `Pure:` in their doc comment (that exact marker, and only they), do no I/O and import none of `os`, `os/exec`, `os/signal`, `net`, `syscall`, `golang.org/x/sys`, `io/ioutil`, `plugin`, `unsafe` (or their subpackages; their tests may): they are the Go side of `components/methods/`. File, socket and process work lives in the edge packages above them, which only `daemon` and `cli` wire together: imports only point down the tiers pure → edge → `daemon` → `cli` → `cmd/`, `tools/`. Every package is placed in one in `internal/archtest`, which enforces these rules and the next one, and fails on a package it doesn't know. The edge tier is one tier: archtest doesn't order the edge packages among themselves, so keep their imports pointing at lower-level ones (`fsx`, `xdg`, `rpc`, …) by review.
- **No globals, no `init()`.** Package-level variables are read-only tables (regexps, lookup maps, sentinel errors, `go:embed` data, values computed once with `sync.OnceValue`), never written after init; an exception is listed with its reason in archtest. State lives in structs built by constructors taking an `Options` (logger, clock, paths injected), so tests build their own. `context.Context` first on anything that blocks; every goroutine has an owner that stops it.
- **One error type across boundaries**: `axerr.Error` with a `Kind`. RPC codes, CLI exit codes and what the shell shows all come from the kind; messages stay English (the shell translates by kind). Wrap causes with `%w`.
- **The config is a tree, not structs.** Migrate, prune, defaults, validate and write work on the ordered JSON tree (`jsonx`), so key order, unknown keys and old shapes survive and the bytes match the JS reference. Generated structs are read-only views, never written back.
- **The schema is the source of truth**: never hand-copy a key list, default or annotation from it into Go; read it through `schema`, or generate from it.
- **Embedded repo files are generated copies** (`internal/assets/data/`, gitignored, by `tools/syncassets` through `go generate`; the schema among them is built from its YAML there): edit the originals. A fresh clone doesn't compile until `scripts/generate.sh` (or `go generate ./internal/assets`) has run.
- **CLI commands are entries in the command table** (`internal/cli`): help, completions and the generated docs come from it. A command parses, calls a library package or the daemon, and prints through `Env.Output` (text, or one JSON value with `--json`).
- **Security-relevant code** (sockets, locks, runtime dirs, atomic writes, the child's environment, the lock screen path) follows the security rules in `docs/dev/backend/README.md`, and every check there has a test.

## Style

- Every package has a doc comment saying what it is for (it feeds `docs/dev/generated/files.md`); exported names are documented; comments say why, at the density of the surrounding code.
- Tests are table-driven with `t.Parallel()`, fakes are written by hand (no mocking library), files are tested in `t.TempDir()`. Behaviour shared with the QML side is tested through the shared fixtures (`docs/dev/backend/README.md` › Shared fixtures), never re-stated inline.
- Generated Go files are named `zz_generated_*.go` and start with the standard `// Code generated … DO NOT EDIT.` line.

## Dependencies

Standard library first. A new module needs a line here saying why, and must be pure Go (`CGO_ENABLED=0` builds).

| Module | Why |
|---|---|
| `honnef.co/go/tools` (tool) | staticcheck, pinned through go.mod's `tool` block |
| `golang.org/x/vuln` (tool) | govulncheck, pinned the same way |
| `go.yaml.in/yaml/v3` | reads the config schema's YAML source (`schema/yamlsrc`, which adds the strictness) |
| `github.com/dop251/goja` | a pure-Go JS engine, used only by `migrate/legacy` to run the frozen format-1 migrations (`legacy.js`) exactly as the shell did, instead of a hand port that could drift |
| `github.com/yuin/gopher-lua` | a pure-Go Lua (5.1) parser and VM: runs a user's Hyprland Lua files, sandboxed, for the bind merge (`compositor/binds`), and checks that an edit to them still parses where `luac` isn't installed (`compositor/luacheck`), without `lua` as a dependency |
| `github.com/fsnotify/fsnotify` | inotify without cgo: `store` watches config.json for edits made outside the daemon, and the daemon's dev mode (`daemon/dev.go`) watches the tree and the installed binary to rebuild or re-exec |
| `golang.org/x/sys` | the Linux calls `syscall` lacks or freezes: peer credentials on sockets (`rpc`, `wayland/wire`), descriptor passing (`unixmsg`), `flock` and `O_NOFOLLOW` opens (`fsx`), sealed memfds (`wayland/wire`), close-on-exec across a re-exec (`daemon`), and the bind merge child's memory limit (`compositor/binds`) |

## Checks

`scripts/check_go.sh` (`scripts/generate.sh --fixtures` first, then generated code, gofmt, vet, staticcheck, `go mod tidy`, tests with `-race`); `--fix` regenerates and formats; `--ci` adds govulncheck (the release cross-builds are `release.yml`'s). `scripts/dev/verify.sh` runs it when anything under `backend/` (or an embedded file) changed.
