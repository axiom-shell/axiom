pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts
import qs.components.views.base

// The keybinds page, a ToolPane with a tab for each mode: the compositor's
// binds by section, as cards in columns, with a search over labels, sections
// and keys, a look-up by key and filters by section, modifier and source
// (KeybindFilter); the keyboard they sit on; or the editor for axiom's own
// binds: their list by section (BindEditor) beside an inspector for the
// selected one (BindInspector), or with none selected, the key map
// (KeyMapPanel). One toolbar serves every tab, its controls shown by tab
// (never a Loader per tab: a recording in the look-up survives a switch).
BaseView {
  id: root

  readonly property bool editing: KeybindManager.page.editing
  readonly property bool keyboard: !root.editing && KeybindManager.page.refView === "keyboard"
  // A combo pressed to look up, by its id ("" for none)
  readonly property string lookupId: BindKeys.keyId(KeybindManager.page.lookupCombo)

  Component.onCompleted: KeybindManager.editor.ensureLoaded()

  readonly property int columnCount: Math.max(1, Math.floor((root.listWidth + root.inspectorWidth) / (root.grid.unit * 0.8)))

  readonly property string query: KeybindManager.page.query.trim()

  // From the binds, the search and the chips only, so nothing rebuilds
  // while it's shown
  readonly property var sections: KeybindFilter.filter(KeybindManager.keybindings, root.query, {
    "sections": KeybindManager.page.sectionFilter,
    "mods": KeybindManager.page.modFilter,
    "sources": KeybindManager.page.sourceFilter,
    "ids": root.lookupId !== "" ? [root.lookupId] : null
  })
  // Whether nothing holds the looked-up key, whatever the search and chips hide
  readonly property bool lookupFree: root.lookupId !== "" && KeybindFilter.filter(KeybindManager.keybindings, "", {
    "ids": [root.lookupId]
  }).length === 0
  // The mode's tab: 0 all binds, 1 keyboard, 2 edit
  readonly property int tabIndex: root.editing ? 2 : root.keyboard ? 1 : 0
  readonly property bool narrowed: root.query !== "" || KeybindManager.page.filtering || root.lookupId !== ""

  readonly property int shownCount: root.sections.reduce((sum, section) => sum + section.binds.length, 0)

  // Masonry: each section goes to the shortest column, by row count
  readonly property var columns: KeybindFilter.columns(root.sections, root.columnCount)

  // The filter chips' groups and what is on, for each tab's `Filters` button
  // and its active chips
  readonly property var listGroups: [
    {
      "id": "section",
      "options": KeybindManager.keybindings.filter(section => section.binds.length > 0).map(section => ({
            "value": KeybindFilter.sectionKey(section),
            "label": KeybindManager.sectionTitle(section) + "  " + section.binds.length
          }))
    },
    {
      "id": "mod",
      "options": KeybindManager.page.modOptions.map(mod => ({
            "value": mod,
            "label": KeyNames.modifierLabel(mod)
          }))
    },
    {
      "id": "source",
      "options": [
        {
          "value": "axiom",
          "label": I18n.tr("Axiom binds")
        },
        {
          "value": "user",
          "label": I18n.tr("Your binds")
        }
      ]
    }
  ]
  readonly property var listSelection: ({
      "section": KeybindManager.page.sectionFilter,
      "mod": KeybindManager.page.modFilter,
      "source": KeybindManager.page.sourceFilter
    })
  readonly property var editGroups: [
    {
      "id": "editSection",
      "options": KeybindManager.page.editSectionOptions.map(option => ({
            "value": option.key,
            "label": I18n.tr(option.title) + "  " + option.count
          }))
    },
    {
      "id": "editMod",
      "options": KeybindManager.page.editModOptions.map(mod => ({
            "value": mod,
            "label": KeyNames.modifierLabel(mod)
          }))
    },
    {
      "id": "editState",
      "options": (KeybindManager.page.pausedCount > 0 || KeybindManager.page.editPausedOnly ? [
          {
            "value": "paused",
            "label": I18n.tr("Paused") + "  " + KeybindManager.page.pausedCount
          }
        ] : []).concat(KeybindManager.page.conditionalCount > 0 || KeybindManager.page.editConditionalOnly ? [
        {
          "value": "conditional",
          "label": I18n.tr("Only when") + "  " + KeybindManager.page.conditionalCount
        }
      ] : []).concat(KeybindManager.editor.issueCount > 0 || KeybindManager.page.editIssuesOnly ? [
        {
          "value": "issues",
          "label": I18n.tr("With issues") + "  " + KeybindManager.editor.issueCount
        }
      ] : [])
    }
  ]
  readonly property var editSelection: ({
      "editSection": KeybindManager.page.editSectionFilter,
      "editMod": KeybindManager.page.editModFilter,
      "editState": (KeybindManager.page.editPausedOnly ? ["paused"] : []).concat(KeybindManager.page.editConditionalOnly ? ["conditional"] : []).concat(KeybindManager.page.editIssuesOnly ? ["issues"] : [])
    })

  function toggleEditFilter(group, value) {
    if (group === "editState" && value === "paused")
      KeybindManager.page.editPausedOnly = !KeybindManager.page.editPausedOnly;
    else if (group === "editState" && value === "conditional")
      KeybindManager.page.editConditionalOnly = !KeybindManager.page.editConditionalOnly;
    else if (group === "editState")
      KeybindManager.page.editIssuesOnly = !KeybindManager.page.editIssuesOnly;
    else
      KeybindManager.page.toggleFilter(group, value);
  }

  // Binds the looked-up key, which nothing holds, in the editor
  function bindLookup() {
    const combo = KeybindManager.page.lookupCombo;
    KeybindManager.page.lookupCombo = "";
    KeybindManager.page.editing = true;
    KeybindManager.editor.addBind({
      "key": combo
    });
  }

  Item {
    id: listSide
    // The list alone takes the editor's whole width, so switching keeps the page's
    implicitWidth: root.editing ? root.listWidth : root.pageWidth
    implicitHeight: root.pageHeight

    ToolPane {
      id: listCard
      anchors.fill: parent
      title: I18n.tr("Keybinds")
      scrollKey: "Keybinds"
      showActions: false

      tabModel: [I18n.tr("All binds"), I18n.tr("Keyboard"), I18n.tr("Edit axiom binds")]
      tabIndex: root.tabIndex
      tabMarked: KeybindManager.editor.isDirty ? [2] : []
      onTabClicked: index => {
        if (index < 2) {
          KeybindManager.editor.stopRecording();
          KeybindManager.page.setRefView(index === 1 ? "keyboard" : "list");
        }
        KeybindManager.page.editing = index === 2;
      }

      // Nothing matched the search, the look-up or the chips
      emptyKind: root.tabIndex === 0 && root.narrowed && root.sections.length === 0 ? "results" : ""
      emptyText: root.lookupFree ? I18n.tr("Nothing is bound to {0}", KeybindManager.displayCombo(KeybindManager.page.lookupCombo)) : root.query !== "" ? I18n.tr("No keybinds match \"{0}\"", root.query) : I18n.tr("No keybinds match the filters")
      emptyActionText: root.lookupFree ? I18n.tr("Bind it") : I18n.tr("Clear")
      onEmptyTriggered: {
        if (root.lookupFree) {
          root.bindLookup();
        } else {
          KeybindManager.page.query = "";
          KeybindManager.page.lookupCombo = "";
          KeybindManager.page.clearFilters();
        }
      }

      toolbar: ToolBar {
        id: bar

        // The keyboard has nothing to search or set
        visible: root.tabIndex !== 1
        searchable: true
        searchPlaceholder: root.editing ? I18n.tr("Search binds by key, action or label") : I18n.tr("Search keybinds")
        count: root.editing ? KeybindManager.page.visibleIndices.length : root.shownCount
        onSearchEdited: {
          if (root.editing)
            KeybindManager.page.editQuery = bar.searchText;
          else
            KeybindManager.page.query = bar.searchText;
        }

        // One field for both searches: it shows the shown tab's, and follows
        // it when the query changes elsewhere (Add bind clears the editor's)
        function syncSearch() {
          const wanted = root.editing ? KeybindManager.page.editQuery : KeybindManager.page.query;
          if (bar.searchText !== wanted)
            bar.searchText = wanted;
        }
        Component.onCompleted: bar.syncSearch()

        Connections {
          target: KeybindManager.page
          function onQueryChanged() {
            bar.syncSearch();
          }
          function onEditQueryChanged() {
            bar.syncSearch();
          }
        }

        Connections {
          target: root
          function onEditingChanged() {
            bar.syncSearch();
          }
        }

        trailing: [
          // Press a combo to see what it does
          KeyRecorder {
            visible: root.tabIndex === 0
            Layout.preferredWidth: root.grid.unit * 0.55
            bindIndex: KeybindManager.editor.lookupIndex
            combo: KeybindManager.page.lookupCombo
            placeholder: I18n.tr("Look up a combo")
          },
          StyledIconButton {
            visible: root.tabIndex === 0 && KeybindManager.page.lookupCombo !== ""
            size: Widget.height
            iconText: "close"
            tooltipText: I18n.tr("Show every bind")
            onClicked: KeybindManager.page.lookupCombo = ""
          },
          StyledIconButton {
            visible: root.tabIndex === 0
            size: Widget.height
            kind: KeybindManager.page.refDensity === "compact" ? "primary" : "text"
            iconText: KeybindManager.page.refDensity === "compact" ? "density_small" : "density_medium"
            tooltipText: KeybindManager.page.refDensity === "compact" ? I18n.tr("Comfortable rows") : I18n.tr("Compact rows")
            onClicked: KeybindManager.page.setRefDensity(KeybindManager.page.refDensity === "compact" ? "comfortable" : "compact")
          },
          StyledIconButton {
            visible: root.tabIndex === 0
            size: Widget.height
            kind: KeybindManager.page.refGlyphs ? "primary" : "text"
            iconText: "keyboard_command_key"
            tooltipText: KeybindManager.page.refGlyphs ? I18n.tr("Modifiers as words") : I18n.tr("Modifiers as symbols")
            onClicked: KeybindManager.page.setRefGlyphs(!KeybindManager.page.refGlyphs)
          },
          StyledTextButton {
            visible: root.editing
            kind: "tonal"
            implicitHeight: Widget.height
            iconText: "playlist_add"
            text: I18n.tr("Presets")
            onClicked: presetSheet.open()
          },
          StyledTextButton {
            visible: root.editing
            kind: "tonal"
            implicitHeight: Widget.height
            iconText: "add"
            text: I18n.tr("Add bind")
            onClicked: KeybindManager.editor.addAndStartRecording({})
          },
          FilterChips {
            visible: root.tabIndex === 0
            groups: root.listGroups
            selection: root.listSelection
            onToggled: (group, value) => KeybindManager.page.toggleFilter(group, value)
          },
          FilterChips {
            visible: root.editing && KeybindManager.editor.binds.length > 0
            groups: root.editGroups
            selection: root.editSelection
            onToggled: (group, value) => root.toggleEditFilter(group, value)
          }
        ]

        // The chips that are on, while any is
        filters: [
          ActiveFilters {
            visible: root.tabIndex === 0 && KeybindManager.page.filtering
            groups: root.listGroups
            selection: root.listSelection
            onToggled: (group, value) => KeybindManager.page.toggleFilter(group, value)
            onCleared: KeybindManager.page.clearFilters()
          },
          ActiveFilters {
            visible: root.editing && KeybindManager.page.editFiltering
            groups: root.editGroups
            selection: root.editSelection
            onToggled: (group, value) => root.toggleEditFilter(group, value)
            onCleared: KeybindManager.page.clearEditFilters()
          }
        ]
      }

      Loader {
        active: root.editing
        visible: active
        Layout.fillWidth: true
        sourceComponent: BindEditor {
          scrollTo: item => listCard.scrollTo(item, true)
        }
      }

      // Built only while shown
      StreamedLoader {
        visible: root.keyboard
        wanted: root.keyboard
        Layout.fillWidth: true
        label: "keyboard reference"

        sourceComponent: KeyboardReference {
          sections: KeybindManager.keybindings
          onEditRequested: bindIndex => KeybindManager.editor.editBind(bindIndex)
        }
      }

      RowLayout {
        visible: !root.editing && !root.keyboard
        Layout.fillWidth: true
        spacing: Widget.spacing * 2

        Repeater {
          model: root.columnCount

          delegate: ColumnLayout {
            id: column
            required property int index
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: Widget.spacing * 2

            Repeater {
              // By count: a model of the sections themselves is copied for
              // every delegate
              model: root.columns[column.index]?.length ?? 0

              delegate: StreamedLoader {
                id: sectionLoader
                required property int index
                readonly property var modelData: root.columns[column.index]?.[sectionLoader.index] ?? null
                Layout.fillWidth: true
                wanted: !root.editing && !root.keyboard
                label: "keybind section"

                sourceComponent: KeybindSection {
                  section: sectionLoader.modelData
                  onEditRequested: bindIndex => KeybindManager.editor.editBind(bindIndex)
                }
              }
            }
          }
        }
      }
    }

    // A Popup, closed until asked, streamed in (StreamedLoader) as the page
    // opens; the loader covers the list, so it's placed as over it
    StreamedLoader {
      id: presetSheet
      anchors.fill: parent
      label: "keybind presets"

      function open() {
        (presetSheet.item as PresetSheet)?.open();
      }

      sourceComponent: PresetSheet {
        width: listSide.width - Widget.padding * 4
        height: listSide.height * 0.8
        x: (listSide.width - width) / 2
        y: (listSide.height - height) / 2
      }
    }
  }

  // The selected bind, or the key map; Save and Discard for the page.
  // Built only while editing, streamed in (StreamedLoader)
  StreamedLoader {
    visible: root.editing
    wanted: root.editing
    Layout.preferredWidth: root.inspectorWidth
    Layout.preferredHeight: root.pageHeight
    label: "keybind inspector"

    sourceComponent: TitledCard {
      title: KeybindManager.editor.selectedIndex >= 0 ? I18n.tr("Bind") : I18n.tr("Key map")
      // The key map keeps its place; a bind starts at its top
      scrollKey: KeybindManager.editor.selectedIndex >= 0 ? "" : "Keybinds/map"
      showActions: true
      dirty: KeybindManager.editor.isDirty
      onSave: KeybindManager.editor.save()
      onReset: KeybindManager.editor.reset()

      Repeater {
        model: root.editing && KeybindManager.editor.selectedIndex >= 0 ? [KeybindManager.editor.selectedIndex] : []

        delegate: BindInspector {
          required property int modelData
          bindIndex: modelData
          Layout.fillWidth: true
        }
      }

      StreamedLoader {
        visible: root.editing && KeybindManager.editor.selectedIndex < 0
        wanted: root.editing && KeybindManager.editor.selectedIndex < 0
        Layout.fillWidth: true
        label: "key map"

        sourceComponent: KeyMapPanel {}
      }
    }
  }
}
