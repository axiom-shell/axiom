# Adding a hand-built settings card

Most of the settings page is generated from the schema. When a section needs more than rows (a status card with actions, a list of entries, a status line above the fields) you write a card by hand and attach it to the section with an annotation. At the end the section shows your card first, or your intro at the top of its own card.

**Copy from:** `qml/components/views/Settings/PolkitStatus.qml` (a status card, the simplest), `qml/components/views/Settings/DependenciesCard.qml` (a `FieldGroup` with a header button), `qml/components/views/Settings/CalendarAccountsCard.qml` (a `FoldingCard`, wide), `qml/components/views/Settings/OSDListCard.qml` (an entry list via `EntryListCard`), `qml/components/views/Settings/NightLightStatus.qml` (an `x-intro`). The sections that use them are in `qml/config/schema/sections/` (`Polkit.yaml`, `Calendar.yaml`, `OSD.yaml`; the intro: the NightLight section's file).
**Background:** [core/settings-page](../dev/core/settings-page.md), [core/schema-annotations](../dev/core/schema-annotations.md) › Hand-built parts

## Files
1. `qml/config/schema/sections/<Section>.yaml`: the annotation on the section.
2. `qml/components/views/Settings/<File>Card.qml` for an `x-card`, or `<Name>.qml` for an `x-intro`, with a purpose comment above the root.

New translation keys are added by the pre-commit hook.

## The annotations
- `x-card: {file, title, wide, folds, perField}` on a section: loads `views/Settings/<file>Card.qml` (the `Card` suffix is added) as the section's first card.
  - `title` is required and is what the card and the sidebar show; the card's own QML sets none.
  - `wide: true` spans both columns, for a list or a form that needs the room.
  - `folds: true` makes it fold like the generated cards and gives it `foldKey` (`<Section>:<file>`).
  - `perField: true` instead makes each direct field its own card (`ThemeIntegrations`).
- `x-intro: <Name>` on a section or an object property: loads `views/Settings/<Name>.qml` at the top of that group's card, above its fields. It hides while its own `shown` property, if it declares one, is false.
- `x-row: <Name>` on a field: a hand-built row in place of the control its type would get; see schema-annotations.

## Steps
1. Add the annotation, for example `x-card: {file: CommunitySetups, title: Community setups}`; a status over the section's own settings is an `x-intro` (`PolkitStatus`: `x-intro: {file: PolkitStatus, setup: [enabled]}`, exposing `status` and `statusColor`), and write the file under the exact name.
2. Build the card from the pieces the settings page already uses: `FieldGroup` for a plain card, `FoldingCard` for one that folds (it needs `foldKey` and these two lines, as in `CalendarAccountsCard.qml`):
   ```qml
   property string foldKey
   collapsed: SettingsManager.isCollapsed(root.foldKey)
   onToggled: SettingsManager.setCollapsed(root.foldKey, !root.collapsed)
   ```
   and `EntryListCard` for a list of entries.
3. Edit settings only through the settings draft: `SettingsManager.setValue` / `commitValue(s)`, reading unsaved values from `SettingsManager.localConfig`. Never write `ConfigManager.config`.
4. Run `scripts/dev/verify.sh`. `check_structure` fails an `x-card`, `x-intro` or `x-row` whose file doesn't exist.

## Watch out for
- **Text fields** follow the push pattern (`StyledTextEntry`: push values in unless focused, act on `textEdited`); see [qml-pitfalls](../dev/core/qml-pitfalls.md).
- **Takeovers.** A card that takes over something on this PC (compositor mode, locker, idle, polkit, greeter) belongs to an `x-takeover` setting, and only that card changes it.
- **Secrets** typed in a card go to `SecretsManager`, never the draft (`CalendarAccountsCard`).
- **Reuse.** Check [shared-ui-pieces](../dev/core/shared-ui-pieces.md) before drawing anything; a second copy of a pattern becomes a shared piece.

## Check it
- `scripts/dev/verify.sh`
- Settings categories have no IPC. Add a temporary `IpcTarget` to `qml/shell.qml` that calls `SettingsManager.openCategory("<Category>")`, look with `scripts/dev/shot.sh`, then remove it ([testing](../dev/testing.md)).

## Docs to update
- [core/settings-page](../dev/core/settings-page.md), if it adds a new kind of card, and the feature's doc.
