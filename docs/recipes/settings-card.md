# Recipe: a hand-built settings card or intro

> **Use when:** a settings section needs more than generated rows: a status card with actions, a list of entries, or a status line above the fields.
> **Copy from:** `components/views/Settings/OnboardingCard.qml` (`FieldGroup` with a header button), `components/views/Settings/PolkitStatusCard.qml` (status), `components/views/Settings/OSDListCard.qml` (an entry list via `EntryListCard`, folding), `components/views/Settings/CalendarAccountsCard.qml` (a `FoldingCard`), `components/views/Settings/NightLightStatus.qml` (an `x-intro`).
> **Docs:** [core/settings-page](../dev/core/settings-page.md), [core/schema-annotations](../dev/core/schema-annotations.md).

## The three annotations
- `x-card: "<Name>"` on a section: loads `components/views/Settings/<Name>Card.qml` as the section's first card (`SettingsContent` adds the `Card` suffix).
- `x-cardTitle: "<Title>"` with it (required): the card's title, which `SettingsContent` passes in as `title` and the sidebar lists; the card's QML sets none. Set `x-cardWide: true` when it holds a list or a form that needs the room.
- `x-cardFolds: true` with it: the card folds like the generated cards and is given `foldKey` (`"<Section>:<Name>"`).
- `x-intro: "<Name>"` on a section or an object property: loads `components/views/Settings/<Name>.qml` at the top of that group's card, above its fields; it hides while its `shown` (if it declares one) is false.

## Files to touch
1. `config/schema/sections/<Section>.yaml`: the annotation on the section (or property).
2. `components/views/Settings/<Name>Card.qml` (or `<Name>.qml` for an intro).
3. `config/i18n/*.json`: nothing to do: the pre-commit hook adds the new keys, empty, to every language and the template.

## Skeleton
A status card:
```qml
pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.<group>  // FooManager's folder: core, compositor, session, system, ui or apps
import qs.components.reusable

// The Foo section's first card (its `x-card`): <what it shows and does>
FieldGroup {
  id: root

  description: FooManager.available ? "" : I18n.tr("Foo isn't installed.")
  headerExtras: StyledTextButton {
    text: I18n.tr("Check again")
    iconText: "refresh"
    onClicked: FooManager.check()
  }
}
```
A folding card (`x-cardFolds: true`):
```qml
FoldingCard {
  id: root

  // The settings group key it folds under, from SettingsContent
  property string foldKey

  collapsed: SettingsManager.isCollapsed(root.foldKey)
  onToggled: SettingsManager.setCollapsed(root.foldKey, !root.collapsed)
}
```

## Steps
1. Add the annotation; write the file under the exact name (`<Name>Card.qml` for `x-card`, `<Name>.qml` for `x-intro`).
2. **Check the file exists yourself**: `check_structure.py` doesn't check `x-card`/`x-intro`, and a typo only shows in `scripts/log.sh` once the category is opened.
3. Edits go through the settings draft (`SettingsManager.setValue` / `commitValue(s)`; read unsaved values from `SettingsManager.localConfig`), never `ConfigManager.config` directly.
4. Verify.

## Gotchas
- Text fields follow the push pattern (`StyledTextEntry`: push values in unless focused, act on `textEdited`); see AGENTS.md › QML pitfalls.
- A card that takes over something on this PC (Hyprland mode, locker, idle, polkit, greeter) belongs to an `x-takeover` setting: only its own card changes it.
- Secrets typed in a card go to `SecretsManager`, never the draft (`CalendarAccountsCard`).

## Verify
- `scripts/dev/verify.sh`
- Settings categories have no IPC: add a temporary `IpcTarget` to `shell.qml` calling `SettingsManager.openCategory("<Category>")`, look with `scripts/dev/shot.sh`, then remove it in place ([testing](../dev/testing.md)).

## Docs to update
- [core/settings-page](../dev/core/settings-page.md) if it adds a new kind of card; the feature's doc.
