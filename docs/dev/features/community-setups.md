# Community setups

> **Files:** `services/apps/CommunitySetupsManager.qml`, `backend/internal/community/`, `backend/internal/daemon/tools.go`, `components/methods/CommunityCatalog.qml`, `config/CommunitySetups.qml`, `components/views/Settings/CommunitySetupsCard.qml`, `services/core/SavedConfigsManager.qml`
> **Config:** `CommunitySetups.*` (reader `CommunitySetups`); an applied setup becomes the saved config `community-<id>`
> **Related:** [Saved configs and sharing](../core/saved-configs-sharing.md), [Themes](../theming/themes.md), [Launcher](launcher.md), [Config manager](../core/config-manager.md) (where files live)

A gallery of setups other people shared at [axiom-shell/community-setups](https://github.com/axiom-shell/community-setups), applied like an import. Tests: `tst_CommunityCatalog`, `backend/internal/community`'s Go tests.

### The other repo
- `setups/<id>/` holds `setup.json` (title, author, tags, tested compositors, fonts, a wallpaper's license), `config.json` (an Export), a screenshot, and optionally `theme.json` and a wallpaper.
- Its CI checks a setup when it's posted or changed, against axiom's `main` that day (its `edge` build and the commit it was built from, fetched by that repo's [axiom.sh](https://github.com/axiom-shell/community-setups/blob/main/scripts/axiom.sh)), and never again: the config is loaded by that binary (`axiom config share --places --json`, `saved.Share`: converts any version, validates, and answers the file as Export would write it plus what that leaves out, `dropped`, each with its scope from `share.Dropped`). A setup holding anything dropped is refused: only the look is admitted, monitors by place. No personal values (commands, apps, keybinds), no machine values, no `x-takeover` settings.
- So the catalog holds configs of many versions: an older one is converted when it's applied (axiom's `saved.load`), like any import, and only one newer than this axiom is refused (`compatible`). Migrations must keep handling every old version.
- After a merge it publishes the `catalog` branch: `index.json` (format 1) plus each setup's files and a 640px `thumb.webp`. Each file is listed as `{ path, sha256, size }`, relative to the index. That branch's README is the gallery.
- Submissions come as pull requests, or as an issue form a workflow turns into one. A pull request may change only its author's setups: the author is checked as the base branch has it, too.
- A change to `x-scope` or the theme format here changes what that repo accepts from its next submission on; setups already there aren't checked again.

### Reading the catalog (`CommunityCatalog`, pure)
- `parse(index, currentVersion)`: the setups, newest first, or null for another `format`.
  - Every entry is checked: the id by pattern, each file's `path` inside `setups/<id>/` (no `..`, no absolute path), each `sha256` 64 hex digits. A malformed entry is dropped, a repeated id kept once.
  - `compatible`: its config version is one this axiom migrates (≤ `ConfigManager.currentVersion`; format-1 versions are converted).
  - `about` is made inert Markdown: raw HTML is escaped and images become links, so showing it loads nothing. Everything else from the catalog is shown as plain text, and only http(s) links open.
- `search(setups, text, tags)` (every word, by `Search.score` over title, author, description, theme and tags; every tag), `tags`, `missingFonts`, `fileUrl`, `extension`.

### Downloading (`CommunitySetupsManager`)
- Nothing touches the network until the gallery is shown: the card (and `/config community`) calls `open()`, which reads the cached `index.json` and refreshes it once per session. **Refresh** fetches it again. Offline, the cached catalog stays, with a status saying so.
- Every download goes through the daemon's `community.fetch` (`{ files: [{ url, dest, sha256 }] }`, `backend/internal/community`): http/https only (redirects too), 20 MB cap, 60 s a file, up to four files of a call at once; the sha256 (none for the catalog) is checked before the file is written atomically (`fsx.WriteFile`), so a bad or half-downloaded one never lands. A destination already holding that hash isn't fetched again (the cache). It answers each file's `{ dest, error }` in their order, which `_fetch` turns into the destinations that landed and the failures. A destination outside `communityCachePath`, `communityThemesPath` and `userDataPath + "wallpapers/"` is refused.
- One run of each kind at a time: a fresher catalog arriving while the thumbnails download fetches them again after that run, and a screenshot asked for during another's download follows it.
- Where things go (`Paths`, `DataDirs`):
  - `communityCachePath` (`$XDG_CACHE_HOME/axiom/community/`): `index.json`, `thumbs/<id>.webp`, `setups/<id>/` (config, screenshot).
  - `communityThemesPath` (`$XDG_DATA_HOME/axiom/themes/<id>.json`): installed palettes, kept after the setup is replaced.
  - `userDataPath + "wallpapers/<id>.<ext>"`: a wallpaper the user chose to take.
- Nothing in it runs in the greeter (`enabled` is false there).

### Applying
`apply(id, withWallpaper)`:
1. Downloads the config, the palette (straight into `communityThemesPath`) and, when asked, the wallpaper, all hash-checked in one call.
2. Rescans the community palettes (`ThemeManager.reloadCommunityThemes`).
3. Hands the config to `SavedConfigsManager.applyShared(id, path, title)`: the same checks as Import (a `version`, not newer than this axiom), then `_apply` with personal parts and commands **off**. So unsaved changes are kept as `unsaved` (and the last applied copy dropped: [saved configs](../core/saved-configs-sharing.md)), only the look is taken (`share.Apply`), and `x-takeover` settings are kept (`share.Apply` and the store's `Replace` both keep them). Even a setup that got past the repo's CI can't bring a command.
4. On `SavedConfigsManager.applied(id)`, sets the wallpaper (with `withWallpaper`) on every monitor as the fixed one, `wallpaper.mode` `fixed`, in one `ConfigManager.commit` (without `takeover`, like every save that writes no takeover setting). On `applyFailed(id)` it stops.
5. `SavedConfigsManager` then saves the result (wallpaper included) as the snapshot `community-<id>`, the active one, as it does for examples and imports ([saved configs](../core/saved-configs-sharing.md)).
- `applied` is derived, not stored: the id while `community-<id>` is `SavedConfigsManager.active`, saved by the apply (`activeSource`, its `_example.source`) and not `modified`. Restoring another snapshot, applying anything else, changing the look or saving over it clears that setup's **Applied** chip; a snapshot the user names `community-<id>` never shows it.
- Every download is one `_fetch(files, done)`. A call that fails as a whole (no daemon) fails every file, so an apply never stays under way.
- Changes from `community_fetch.sh`: Go's HTTP instead of curl (the failure reasons read differently in the log), a call's files downloaded four at a time rather than one by one, and destinations limited to those three folders.

### Where it shows
- **Settings → Maintenance**: `CommunitySetupsCard` is the `CommunitySetups` section's `x-card` (wide). It has a search field, tag chips (`SegmentButton`s in a Flow) and a `TileFlow` of thumbnails. A tile opens the details: the full screenshot (`fetchScreenshot`; the thumbnail until then), about, chips for tested compositors / its own palette / missing fonts / a newer axiom, the wallpaper's license with an "Also use its wallpaper" switch (off), and Apply (a second click confirms). **Export and submit…** exports the look (personal parts and commands off, monitors by place) and opens the submission issue form (`submitUrl`: its title prefilled from the active saved config; attachments can't be).
- **Launcher**: `/config community <search>` lists matches with their thumbnails (`matched` rows) and applies one without its wallpaper.
- **IPC** `community`: `refresh`, `list`, `apply <id>`. The service is created from `shell.qml`'s `_services`, so the target exists before the gallery is opened.

### Themes
A bundled palette is `Appearance.theme` `community/<id>` (`Paths.themeFile`'s third prefix beside `generated/`). `ThemeManager` scans `communityThemesPath` with a third loader. Its families carry `community: true` and sit after the stock ones (`ThemePicker` lists them with the stock themes; the launcher's `/theme` labels them). A community palette is one theme on its own: its `paired` is ignored.
