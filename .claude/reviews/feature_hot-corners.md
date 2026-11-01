# feature:hot-corners
reviewed: f03a923 2026-11-01  (full)

A small, sound system; its real gaps are the known Overlay-layer covering and the pre-v71 shared file entries; the action list is kept by hand.

## Open findings
- Cleanup: [Hot corners' action list is a hand-kept copy of the keybind one](../../docs/dev/issues.md#hot-corners-action-list-is-a-hand-kept-copy-of-the-keybind-one)
- Known: [A hot corner can't close what covers it](../../docs/dev/issues.md#a-hot-corner-cant-close-what-covers-it) (also: reopens on re-enter after a keyboard close, PLAUSIBLE)
- Known: [A shared file older than v71 resets niri's hot corner](../../docs/dev/issues.md#a-shared-file-older-than-v71-resets-niris-hot-corner)

## Contract
Every line of docs/dev/features/hot-corners.md holds; tst_BindActions pins the action enum and argument x-showIf; v82 go test passes.

## Coverage
Deep: shell/HotCorners.qml, config/HotCornersConfig.qml, HotCorners.yaml, v82.go, ShellManager.runAction, BindActions.ipcCall. Outlined: niri.go managedText, LayerStack hot-corner entry.

## History
- 2026-11-01 full: 1 finding (Cleanup); recorded
