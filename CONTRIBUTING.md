# Contributing

Thanks for wanting to help. Bug reports, ideas, translations and code are all welcome.

## Reporting and requesting

[Open an issue](https://github.com/axiom-shell/axiom/issues/new/choose) and pick the form that fits:

| Form | For |
| --- | --- |
| **Bug report** | Something broken or behaving wrongly |
| **New feature or component** | Something big: a new surface, page type, editor or subsystem |
| **Small feature or improvement** | A change to something that exists, a new setting or launcher command, or a small feature that stands on its own |
| **Bar widget or module** | Something new for the bar, or a module for overlay pages, edge menus, the desktop, the lock screen or the login screen |
| **App theme request** | Another app that should follow axiom's theme |
| **Compositor or distribution support** | Running on another compositor, or installing on another distribution. Needs someone who runs it to test it |
| **Translation** | A new language, or wrong or untranslated text |

For a bug, paste the output of two commands: `axiom bug-info`, which prints your versions and setup (`~/.local/bin/axiom bug-info` if `axiom` isn't on your `PATH`), and `axiom log`, which shows the shell's log.

Each form adds its kind's label plus `triage`, which a maintainer swaps for `needs-info`, `help wanted`, `good first issue` or a `compositor: …` label once it's sorted. Platform requests also carry `needs-maintainer` until someone signs up to test them.

Questions and help with setting up go in [Discussions › Q&A](https://github.com/axiom-shell/axiom/discussions/categories/q-a), ideas not ready to be a request in [Ideas](https://github.com/axiom-shell/axiom/discussions/categories/ideas), and your setup in [Show and tell](https://github.com/axiom-shell/axiom/discussions/categories/show-and-tell). Want to build something big? Open its request first, so we can agree on the shape before you build it.

**Want to translate?** Copy `qml/config/i18n/template/language.json` to `qml/config/i18n/<code>.json` (`de.json`), fill in `_meta.name` (the language's own name, `Deutsch`) and `_meta.locale` (`de_DE`), adjust the date formats, and translate the strings. Anything left empty shows in English, so a partial translation is fine to send. `scripts/check_i18n.py` lists what's missing. It shows up under **Settings → General → Language** right away.

**Want to add a theme?** Copy `qml/config/themes/template/theme.json` to `qml/config/themes/<name>.json`, set its `name`, `author` and `variant`, and replace the sixteen `base00`–`base0F` colors. The `semantic` names map onto those and are already sensible, so only change the ones your palette needs. For a dark/light pair, give each file a `paired` field naming the other. It shows up under **Themes** as soon as you save.

**Want to share your setup?** Submit it to [community-setups](https://github.com/axiom-shell/community-setups), where anyone can browse and apply it from **Settings → Maintenance → Community setups**. **Export and submit…** there starts it; the repository's [guide](https://github.com/axiom-shell/community-setups/blob/main/CONTRIBUTING.md) has the rest. The `data/examples/` shipped with axiom are picked by the maintainers.

**Found a security problem?** Don't open an issue: report it privately as [SECURITY.md](SECURITY.md) describes.

## Help wanted

axiom is built and tested on one machine with one GPU, so some help goes further than code. [Help wanted](https://github.com/orgs/axiom-shell/discussions/67) has the details. In short:

- **Compositor testers**: people who use Hyprland, sway/SwayFX or niri every day on other hardware and setups (other GPUs, several monitors, scaling, laptops), and report what breaks.
- **Packagers**: `axiom-shell` and `axiom-shell-git` for the AUR and Fedora COPR, and `axiom-shell` for Nix. [docs/dev/packaging.md](docs/dev/packaging.md) lists the dependencies.
- **Translators**: see the [translations tracker](https://github.com/axiom-shell/axiom/issues/66).
- **First contributions**: issues labelled [good first issue](https://github.com/axiom-shell/axiom/labels/good%20first%20issue) are small and name the files to look at. [help wanted](https://github.com/axiom-shell/axiom/labels/help%20wanted) ones are bigger or need a particular setup to test.

## Setting up

axiom is two parts. The shell is QML (`qml/`) with no build step: Quickshell runs it as it is and reloads a file the moment you save it. The `axiom` binary (Go, in `backend/`) is its parent process: it starts the shell, owns the config file and is the `axiom` command. Most changes touch only the QML.

You work in a clone of your own, anywhere, which axiom runs in **dev mode**: its own binary, built from your clone and rebuilt as you edit it, on a config of its own (`~/.config/axiom/dev/config.json`, copied from yours the first time). The installed axiom (`~/.local/share/axiom-shell`) stays as it is, and `axiom dev off` goes back to it.

1. Fork the repository and clone your fork wherever you like:
   ```bash
   git clone https://github.com/<you>/axiom.git ~/dev/axiom
   ```
2. Run its installer (`~/dev/axiom/install.sh`): it installs the latest release, then offers to make your clone axiom's dev tree. Already have axiom installed? Run `axiom dev set ~/dev/axiom` instead.
3. Turn on the pre-commit hook, which keeps what's committed but generated up to date: the translation files (new text goes into every language, empty, and into the template a new language starts from) and the theme template:
   ```bash
   git config core.hooksPath .githooks
   ```
4. Run `scripts/generate.sh` once, then `axiom dev on` (needs Go 1.26 or newer): axiom builds your clone and switches to it. From then on a saved QML file reloads, a schema edit rebuilds the schema, and a saved Go file rebuilds the binary and switches to it, without restarting the shell. It stays on across logins until `axiom dev off`. **Settings → Development** (with **Developer options** on under Maintenance → axiom updates) shows the dev tree and its build, and copies settings between the dev config and yours; the `DevMode` bar widget shows it's on.

## The workflow

1. **Branch** off `main`.
2. **Find your way in.** Use the table below to find the doc for what you're touching, and read it first. Check the [open issues](https://github.com/axiom-shell/axiom/issues) in that area too.
3. **Edit and save.** With dev mode running your clone, the shell reloads, so you see the change straight away, and a saved Go file rebuilds the binary too.
4. **Check it** with `scripts/dev/verify.sh` until it prints `verify ok`. It formats your QML, runs the checks your change touches and shows the shell's log.
5. **Update the docs** that describe what you changed (verify.sh lists them).
6. **Open a pull request** against `main` and fill in the template, linking the issue it closes (`Fixes #123`). CI runs every check (`scripts/dev/verify.sh --all` locally).

Found an unrelated bug along the way? [Report it](https://github.com/axiom-shell/axiom/issues/new?template=01-bug.yml) rather than fixing it in the same pull request.

## How it's laid out

```bash
qml/              # the shell: what Quickshell runs (qs -p qml)
  shell.qml       # entrypoint: one top-level item per surface, plus services only reached by IPC
  greeter.qml     # the login screen's entrypoint
  shell/          # top-level pieces, one per surface
  components/
    methods/      # pure helpers with unit tests: no files, processes or side effects
    reusable/     # generic Styled* widgets, no feature logic
    forms/        # schema-driven form widgets for the settings page
    content/      # loadable panels by name: overlay modules and bar popouts
    hosts/        # where content appears: popouts, overlay pages and slots
    views/        # overlay pages by type, with their pieces in subfolders
    bar/          # the bar; bar/widgets/ holds the bar widget types
    surfaces/     # standalone windows (launcher, lock screen, toasts, dock, power menu, …)
  services/       # *Manager singletons: state and every side effect (processes, files, the compositor),
                  # grouped core/ compositor/ session/ system/ ui/ apps/ (one QML module each)
  config/         # config readers; schema/ (the config schema's YAML source), themes/, i18n/
  assets/         # fonts and icons
data/             # runtime files that aren't QML: the login screen's scripts, theme templates, the example setups
backend/          # the axiom binary (Go): the shell's parent, the config's owner, the command line
packaging/        # the AUR packages
scripts/          # the dev checks and tools
tests/            # qmltestrunner tests and script tests
docs/             # user docs; docs/dev/ for contributors
```

Dependencies point one way: `methods/` helpers → config readers → services → UI. The UI never runs processes or writes files itself; it asks a service. Services are moving their side effects into the `axiom` binary bit by bit, so new code doesn't start processes, open files or sockets of its own either: it goes through the shared services (`CommandManager`, `FileManager`, `StateManager`) or the binary (`scripts/check_structure.py` enforces it).

## Where to look

Read [AGENTS.md](AGENTS.md) before your first change: it holds the project's rules, for people and agents alike. How each part works is in [docs/dev/](docs/dev/README.md), one doc per topic.

| I want to… | Start at |
| --- | --- |
| Add a bar widget, overlay module, setting, launcher command, theme integration, … | Its recipe in [docs/recipes/](docs/recipes/): files to touch and one to copy |
| Change a bar widget or the bar's look | [docs/dev/bar/](docs/dev/bar/) |
| Change edge menus, overlay pages or modules | [docs/dev/edge-menus/](docs/dev/edge-menus/), [docs/dev/overlay/](docs/dev/overlay/) |
| Change a popout | [docs/dev/popouts/surface-context.md](docs/dev/popouts/surface-context.md) |
| Change a feature (launcher, lock screen, dock, notifications, …) | `docs/dev/features/<feature>.md` |
| Change something about settings or the config | [config-manager](docs/dev/core/config-manager.md), [schema-annotations](docs/dev/core/schema-annotations.md) |
| Build UI | [shared-ui-pieces](docs/dev/core/shared-ui-pieces.md): reuse what's there before drawing a new card or row |
| Work on compositor support, or add a compositor | [docs/dev/compositor/](docs/dev/compositor/README.md) |
| Work on themes or theming other apps | [docs/dev/theming/](docs/dev/theming/) |
| Work on the `axiom` binary (Go) | [backend/AGENTS.md](backend/AGENTS.md), [docs/dev/backend/](docs/dev/backend/README.md) |
| Change what the shell and the binary say to each other | [protocol](docs/dev/backend/protocol.md), and every method in `docs/dev/generated/rpc.md` (generated by `scripts/generate.sh`, not on GitHub) |
| Change the config's shape (rename or move a setting) | [the migration recipe](docs/recipes/migration.md): a Go step and its test |
| Find which file does something | `grep -n '<word>' docs/dev/generated/files.md` |
| Look up a setting: its default, and what reads it | `docs/dev/config/<Section>.md` |

## Testing your change

- **Use it.** Your change is live as soon as you save. For anything visual, add a screenshot to the pull request: `scripts/dev/shot.sh page <ViewType>` (or `launcher`, or `ipc <target> <open>`) takes one for you.
- **Read the log.** `scripts/log.sh` (`axiom log`, trimmed) shows warnings and errors since the last reload (`--debug` adds `console.log`, `-f` follows).
- **Unit tests.** Changing a helper in `qml/components/methods/`? Add a case in `tests/` and run `scripts/run_tests.sh <Name>`. Changing the Go side, a config migration included? Its tests sit beside the code, and `scripts/check_go.sh` runs them with the other Go checks (verify.sh runs it whenever `backend/` changed).
- **Another compositor, or a fresh config.** `scripts/dev/nested.sh <sway|niri>` runs that compositor in a window with a second axiom inside it, on its own config, so you can try managed mode or a first start without touching your desktop.

More tricks for debugging the running shell are in [docs/dev/testing.md](docs/dev/testing.md).

## Using AI

Coding agents are welcome, and the repository is set up for them (`CLAUDE.md` imports AGENTS.md, and the recipes double as skills). You're still responsible for what you submit: read it, run it, and check the log.
