# Configuration

[README](../README.md) · [Features](features.md) · [Installation](installation.md) · [Keybinds, IPC and launcher](usage.md) · [Configuration](configuration.md)

## The config file

Everything is configured from inside the shell (see [Features](features.md)). Open the overlay, and use the **Settings**, **Bar editor**, **Layouts**, **Keybinds**, **Monitors** and **Themes** pages. Any single setting can also be set from the launcher: `/config Appearance.font.size 14`.

- Settings are saved to `~/.config/axiom/config.json`. The `axiom` binary owns that file: it checks every change against the schema and writes it atomically. You never need to open it, but axiom notices when the file changes, so editing it by hand also works.
- From a terminal or a script, `axiom config` reads and changes it while axiom runs, and the shell shows the change at once: `axiom config get Appearance.font`, `axiom config set Appearance.font.size 14`, `axiom config reset Appearance.font.size`. `axiom config validate` checks a file without changing anything, and `axiom config path` shows where everything is.
- Configs from older versions are migrated automatically. A config from before the current format is converted once and the original kept beside it as `config.format1.json`.
- The schema defines every option and its default, and generates the Settings page. Its source is YAML under `config/schema/` (one file per section and definition), built into `config/json/config.schema.json`.
- Chat API keys are entered in **Settings → Modules → Chat** and stored in your keyring (or `$XDG_STATE_HOME/axiom/secrets.json`, mode 600, without one). A provider's environment variable (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`) wins over a stored key. Conversations are saved in `$XDG_STATE_HOME/axiom/chats/`.

> [!IMPORTANT]
> An invalid `config.json` never replaces the running config. axiom keeps the last good one and refuses to save until the file is fixed. `axiom config status` says what's wrong with it; restoring a saved config also fixes it.

### Where axiom keeps your files

axiom never writes inside its own folder (`~/.config/quickshell/axiom`). What it saves goes in the standard XDG folders (under `$XDG_CONFIG_HOME`, `$XDG_STATE_HOME` and `$XDG_DATA_HOME` if they're set):

| What | Where |
|---|---|
| `config.json` and saved configs | `~/.config/axiom/` |
| Small UI state (launcher history, pinned clips, editor and page choices, first-run progress) | `~/.local/state/axiom/ui/` |
| Notes, when no notes folder is set | `~/.local/share/axiom/notes/` |
| Themes generated from the wallpaper | `~/.local/state/axiom/themes/` |
| Chats, notification history, secrets without a keyring, and the files axiom generates for your compositor and themed apps | `~/.local/state/axiom/` |

To back up your setup or keep it in a dotfiles repo, `~/.config/axiom/` is the folder to keep (`~/.local/share/axiom/notes/` too, if your notes live there).

### Saved configurations

Your whole setup (bars, overlay pages, edge menus, docks, the lock and login screens, every setting) is one file, so it can be kept and swapped as a whole:

- **Settings → Maintenance → Saved configurations** saves the current config under a name, and restores or deletes saved ones. Restoring replaces the current config.
- The launcher does the same: `/config save <name>` and `/config restore <name>`.
- Saved configs are plain copies of `config.json` in `~/.config/axiom/saved/`. Copy one to another machine, or share it, and restore it there.

### Example setups

axiom ships the setups from the README in `examples/`. Apply one from **Settings → Maintenance → Example setups**, or with `/config example <name>` in the launcher.

- An example holds only the look and the layout: the theme, font and shape, the bars and their style, overlay pages, edge menus, docks, OSDs, popouts, the lock screen layout, workspaces, notifications' placement, the power menu and the window switcher.
- Everything else stays as it is: wallpapers, monitors, apps, keybinds, calendars, chat providers, compositor settings, idle and the login screen.
- Your current config is saved first, as `before-<name>`, so going back is one **Restore** away.
- An example is a partial `config.json` with a `_example` header (`title`, `description`). What it may hold is each setting's `x-scope` in `config/json/config.schema.json`. If it uses a font you don't have, the text falls back to another; a theme you don't have falls back to the default palette.

### Sharing a setup

- **Settings → Maintenance → Share → Export** writes the current look and layout to `~/axiom-<name>-<date>-<time>.json`, holding only what differs from the defaults. Monitors, wallpapers, accounts and paths are never in it. Keybinds, apps and commands are left out unless you switch them on, and so are your personal preferences, such as your interface scale, card size and density.
- **Import…** opens a file (an export, an example or a whole `config.json`) and applies it the way an example applies, after saving the current config as `before-<name>`. A file without a `version`, or from a newer axiom, is refused.
- If the file holds keybinds, apps and commands, you can take those too, but the switch is off by default: a command runs as you, so read every command in a file someone else made before turning it on.

### Community setups

Setups other people built and shared at [axiom-shell/community-setups](https://github.com/axiom-shell/community-setups). Browse them in **Settings → Maintenance → Community setups**, or search with `/config community <text>` in the launcher.

- Nothing is downloaded until you open the gallery. Every file is checked against the catalog's checksum.
- Applying one works like an import with keybinds, apps and commands off: only the look and layout change, and your current config is saved first as `before-<id>`. Shared setups never contain commands, monitors, accounts or paths, and the repository's checks refuse any that try.
- A setup may bring its own palette, installed as the theme `community/<id>` (in `~/.local/share/axiom/themes/`, listed on the Themes page), and a wallpaper, which you get only with **Also use its wallpaper**.
- A setup lists the compositors its author ran it on and the fonts it uses; a missing font is flagged, and the text falls back to another.
- To share yours: **Export and submit…** under the gallery exports your look and opens the submission form. See the repository's [contributing guide](https://github.com/axiom-shell/community-setups/blob/main/CONTRIBUTING.md).
- Turn the gallery off, or point it at a mirror, under **Community gallery** on the same page.

### Themes

- Hand-made themes live in `config/themes/`, generated ones in `~/.local/state/axiom/themes/`, and community setups' palettes in `~/.local/share/axiom/themes/`.
- A theme is a base16 palette (`base00`–`base0F`) plus optional semantic overrides. See `config/themes/theme.schema.json`.
- To add a theme, copy the template `config/themes/template/theme.json` to `config/themes/<name>.json`, then set its name, variant and sixteen colors. To make a dark/light pair, give each file a `paired` field naming the other.

### Translations

- Pick a language in **Settings → General → Language**.
- To add a language, copy the empty template `config/i18n/template/language.json` to `config/i18n/<code>.json`, set `_meta.name` and `_meta.locale`, and translate the strings. It shows up in the dropdown right away.
- Missing strings fall back to English. `scripts/check_i18n.py` reports what's missing.

## Troubleshooting

View the shell's log with:

```bash
scripts/log.sh          # warnings and errors since the last reload
scripts/log.sh --debug  # include console.log output
scripts/log.sh -f       # follow
```

A clean reload prints only `Reloading configuration...` and `Configuration Loaded`.

The shell runs under `axiom run`, its parent process, which has a log of its own:

```bash
axiom ping              # is axiom running on this display, and which binary
axiom daemon status     # the daemon, the shell it runs, and whether the config loads
axiom daemon logs       # the daemon's log: config loads and saves, crashes, restarts
axiom restart           # restart the shell (the daemon keeps running)
```

- **A notice saying axiom isn't running the shell:** the shell was started directly with `qs`. Start it with `axiom run` instead, and use that in your compositor's start-up line.
- **A notice that the files and the binary are from different versions:** the `axiom` binary is older or newer than the shell's files, so axiom runs read-only and doesn't save settings. Rebuild the binary from the same clone (`scripts/generate.sh --no-docs && go -C backend build -o ~/.local/bin/axiom ./cmd/axiom`), then `axiom daemon reexec`.

Reporting a bug? Include the output of `scripts/bug_info.sh` (your versions, compositor, distribution and config mode) along with the log. Both scripts are in axiom's folder: `~/.config/quickshell/axiom` for a clone, `/usr/share/axiom` for a package.

Icons showing as words (`wifi`, `battery_full`) mean the icon font is missing: install `ttf-material-symbols-variable` and restart the shell.
