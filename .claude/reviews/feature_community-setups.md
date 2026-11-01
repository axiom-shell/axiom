# feature:community-setups
reviewed: e750d42 2026-11-01  (full)

A small, well-checked system (catalog parsing and the Go fetcher sound and tested); its bugs sit on rare paths: the Applied chip after re-applying an edited setup, IPC apply before a catalog read, enabling the gallery while shown, and a re-exec mid-download.

## Open findings
- Major: [Re-applying a community setup over its edited copy never shows Applied](../../docs/dev/issues.md#re-applying-a-community-setup-over-its-edited-copy-never-shows-applied)
- Major: [IPC community apply does nothing until the catalog was read](../../docs/dev/issues.md#ipc-community-apply-does-nothing-until-the-catalog-was-read)
- Major: [Turning the gallery on while its card is shown leaves it empty](../../docs/dev/issues.md#turning-the-gallery-on-while-its-card-is-shown-leaves-it-empty)
- Major: [community.fetch isn't sent again after a daemon re-exec, and blanks every thumbnail](../../docs/dev/issues.md#communityfetch-isnt-sent-again-after-a-daemon-re-exec-and-blanks-every-thumbnail)
- Cleanup: [CommunityCatalog's setups carry three fields nothing reads](../../docs/dev/issues.md#communitycatalogs-setups-carry-three-fields-nothing-reads)
- Cleanup: [The apply's wallpaper rides in a property instead of the callback](../../docs/dev/issues.md#the-applys-wallpaper-rides-in-a-property-instead-of-the-callback)
- Minor: A setup's screenshot stays the old one after a refresh changes it (`services/apps/CommunitySetupsManager.qml:100`, `_screenshots` kept per session; clear it on a non-cached `_readIndex`).

## Contract
Holds: nothing downloads before open(); one refresh per session; offline keeps the cache with a status; parse's id/path/sha checks and dedupe; `compatible`; inert `about`, plain text elsewhere, only http(s) links open; community.fetch's scheme, redirects, 20 MB, 60 s, four at once, hash before atomic write, cache, order, three roots (matching Paths); one run of each kind; greeter off; apply's one call, palette rescan, look-only applyShared, wallpaper; a failed call fails every file; launcher applies without wallpaper; Export and submit.

## Coverage
Read deeply: CommunitySetupsManager, CommunitySetupsCard, CommunityCatalog, community.go, tools.go, the reader and schema, SavedConfigsManager · Outlined: saved.go (apply, keep, freeName), BackendManager (call, repeatable), LauncherConfigBrowser, ThemeManager.reloadCommunityThemes, SettingsContent's x-card loader · Skipped: the community-setups repo (not fetched).

## History
- 2026-11-01 full: 7 findings (4 Major, 2 Cleanup, 1 Minor); recorded
