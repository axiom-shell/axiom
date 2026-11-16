# Building an editor (tool) page

A tool page that edits a list of things (custom widgets, monitors) is built from the same pieces in `qml/components/views/base/`, so every one looks and behaves alike. At the end you have a page of one or two panes: a list, and for the selected entry an inspector (and for a canvas page, a work area).

**Copy from:** `qml/components/views/CustomWidgets/` (`CustomWidgets.qml` and `DefinitionsPanel.qml`: a list pinned above a script form, an inspector with an `InspectorHeader`, tabs and the empty states) and `qml/components/views/Monitors/` (a toolbar, an embedded `WorkArea` and a footer). For a `ToolBar` also read `Monitors` and `Keybinds`; for a `ListSection`, `CalendarPage` (CustomWidgets uses neither).
**Background:** [editors pattern](../dev/core/editors-pattern.md) (the vocabulary this page follows), [shared UI pieces](../dev/core/shared-ui-pieces.md) › Tool pages, [overlay-view](overlay-view.md) (the page type itself, its schema and launcher command), [style](../dev/core/style.md)

## The shape
`[ListPane] [WorkArea over Inspector | Inspector]`, every pane a `ToolPane` and the page `BaseView.pageWidth` wide (a pane from `sideWidth`, `editorWidth`, `inspectorWidth` or `listWidth`).

## Which piece for which job
| You need | Use |
|---|---|
| A pane with a title, Save/Discard, tabs, a pinned list, a toolbar, a scrolling body, a footer | `ToolPane`: title = the kind of pane, never the selection's name; slots `pinned`, `tabModel`, `toolbar`, the body (its children), `footer` |
| Nothing yet / nothing selected / nothing found | `ToolPane.emptyKind` `"none"`, `"select"`, `"results"` with `emptyIcon` (the page's icon for `"none"`), `emptyText`, `emptyHint`, `emptyActionText` |
| Search, controls and a count over the list | `ToolBar` in `toolbar` |
| A titled group of rows (a collapsible built-in set) | `ListSection` |
| The list's rows | `ListEntryRow` + `RowAction`s, `AddEntryButton` under them; connect `removeRequested` to the remove its × runs |
| The selection's name and its actions | `InspectorHeader` in `pinned` (`canDuplicate`, `canRemove`, `closable`) |
| An inspector's groups in columns | `GroupColumns` around its `FieldGroup`s |
| A canvas with undo, tools, a status line and Save | `WorkArea` (`embedded` when it is the pane's only main content) |
| A tall work surface in a pane's body | its height from `pane.bodyHeight`, never `pageHeight - …` |

## Steps
1. Follow [overlay-view](overlay-view.md) for the page itself.
2. Put the list in a left `ToolPane`'s `pinned`; connect each row's `removeRequested` to the remove its × runs (with its blocked rule) and, where the page can clear its selection, `escapePressed` to that with `escapeClears: true` (otherwise leave both, so Escape reaches the host and closes the overlay: a list that always has a selection, as the layouts editor's, leaves it; Escape-clears is opt-in per list, for one with an empty-selection state).
3. Put the selected entry's editor in the right `ToolPane`: an `InspectorHeader` in `pinned`, tabs in `tabModel`, the form in the body (a selection-keyed `KeyedLoader`, so nothing is built hidden).
4. Save and Discard belong in the header of the top-right pane (`dirty`, `onSave`, `onReset`).

## Watch out for
- A pane's own `StyledScrollView` that holds forms (FormRows) sets `bleed: Style.rowBleed` and `Layout.leftMargin/rightMargin: -Style.rowBleed` (`anchors.` margins when anchored), so a row's hover tint isn't cut at the view's edge; `showScrollBar: true` for a body that can overflow.
- One left edge: nothing in `pinned`, the body or `footer` sets a side margin of its own.
- `ToolPane`'s own children go through its default slot; never add one to `headerExtras` or `bodyContent` by hand.
- A hidden child of a hidden parent reads as hidden: decide a pinned or filter row's visibility from its own condition, not from `visibleChildren` of what it sits in.
- Colours, text and icon sizes: `Style` roles (`check_style.py`).

## Check it
- `scripts/dev/verify.sh` (the layout harness in `tests-layout/` loads the pieces at every scale, density and font size).
- `scripts/dev/shot.sh page <Type>`, then read `scripts/log.sh`.
