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

// The keybinds page: the compositor's binds by section, as cards in
// columns, with a search over labels, sections and keys and toggle chips
// by section, modifier and source (KeybindFilter); or the editor for
// axiom's own binds: their list by section (BindEditor) beside an
// inspector for the selected one (BindInspector), or with none selected,
// the key map (KeyMapPanel)
BaseView {
  id: root

  readonly property bool editing: KeybindManager.page.editing
  readonly property bool keyboard: !root.editing && KeybindManager.page.refView === "keyboard"
  // A combo pressed to look up, by its id ("" for none)
  readonly property string lookupId: BindKeys.keyId(KeybindManager.page.lookupCombo)
  readonly property real inspectorWidth: root.sideWidth * 1.45
  // The list beside it: rows need little room, so three quarters of an
  // editor's width (narrower still where the screen has no room for both)
  readonly property real listWidth: root.grid ? Math.max(root.grid.unit * 1.2, Math.min(root.editorWidth * 0.75, root.grid.roomWidth - root.inspectorWidth - OverlayConfig.cardSpacing * 3)) : 0

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
  readonly property bool narrowed: root.query !== "" || KeybindManager.page.filtering || root.lookupId !== ""

  readonly property int shownCount: root.sections.reduce((sum, section) => sum + section.binds.length, 0)
  readonly property int totalCount: KeybindManager.keybindings.reduce((sum, section) => sum + section.binds.length, 0)

  // Masonry: each section goes to the shortest column, by row count
  readonly property var columns: KeybindFilter.columns(root.sections, root.columnCount)

  Item {
    id: listSide
    // The list alone takes the editor's whole width, so switching keeps it
    implicitWidth: root.editing ? root.listWidth : root.listWidth + root.inspectorWidth + OverlayConfig.cardSpacing
    implicitHeight: root.pageHeight

    TitledCard {
      id: listCard
      title: I18n.tr("Keybinds")
      scrollKey: "Keybinds"
      showActions: false

      headerExtras: [
        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing * 2

          SegmentRow {
            Repeater {
              // I18n.tr("All binds") I18n.tr("Keyboard") I18n.tr("Edit axiom binds")
              model: ["All binds", "Keyboard", "Edit axiom binds"]

              delegate: SegmentButton {
                required property string modelData
                required property int index
                readonly property bool selected: index === 2 ? root.editing : !root.editing && root.keyboard === (index === 1)
                implicitHeight: Widget.height
                text: I18n.tr(modelData) + (index === 2 && KeybindManager.editor.isDirty ? "  •" : "")
                active: selected
                Layout.fillWidth: false
                onClicked: {
                  if (index < 2) {
                    KeybindManager.editor.stopRecording();
                    KeybindManager.page.setRefView(index === 1 ? "keyboard" : "list");
                  }
                  KeybindManager.page.editing = index === 2;
                }
              }
            }
          }

          StyledTextEntry {
            visible: !root.editing && !root.keyboard
            Layout.fillWidth: true
            Layout.preferredHeight: Widget.height
            placeholderText: I18n.tr("Search keybinds")
            Component.onCompleted: input.text = KeybindManager.page.query
            onTextChanged: KeybindManager.page.query = text
          }

          StyledTextEntry {
            id: editSearch
            visible: root.editing
            Layout.fillWidth: true
            Layout.preferredHeight: Widget.height
            placeholderText: I18n.tr("Search binds by key, action or label")
            Component.onCompleted: input.text = KeybindManager.page.editQuery
            onTextChanged: KeybindManager.page.editQuery = text
            // Add bind clears the search
            Connections {
              target: KeybindManager.page
              function onEditQueryChanged() {
                if (editSearch.input.text !== KeybindManager.page.editQuery)
                  editSearch.input.text = KeybindManager.page.editQuery;
              }
            }
          }

          StyledTextButton {
            visible: root.editing
            implicitHeight: Widget.height
            iconText: "playlist_add"
            text: I18n.tr("Presets")
            onClicked: presetSheet.open()
          }

          StyledTextButton {
            visible: root.editing
            implicitHeight: Widget.height
            iconText: "add"
            text: I18n.tr("Add bind")
            onClicked: KeybindManager.editor.addAndStartRecording({})
          }

          Item {
            visible: root.keyboard
            Layout.fillWidth: true
          }

          // Press a combo to see what it does
          KeyRecorder {
            visible: !root.editing && !root.keyboard
            Layout.preferredWidth: root.grid.unit * 0.55
            bindIndex: KeybindManager.editor.lookupIndex
            combo: KeybindManager.page.lookupCombo
            placeholder: I18n.tr("Look up a combo")
          }

          StyledIconButton {
            visible: !root.editing && KeybindManager.page.lookupCombo !== ""
            Layout.fillWidth: false
            Layout.fillHeight: false
            Layout.preferredWidth: Widget.height
            Layout.preferredHeight: Widget.height
            iconText: "close"
            tooltipText: I18n.tr("Show every bind")
            onClicked: KeybindManager.page.lookupCombo = ""
          }

          StyledIconButton {
            visible: !root.editing && !root.keyboard
            Layout.fillWidth: false
            Layout.fillHeight: false
            Layout.preferredWidth: Widget.height
            Layout.preferredHeight: Widget.height
            iconText: KeybindManager.page.refDensity === "compact" ? "density_small" : "density_medium"
            tooltipText: KeybindManager.page.refDensity === "compact" ? I18n.tr("Comfortable rows") : I18n.tr("Compact rows")
            onClicked: KeybindManager.page.setRefDensity(KeybindManager.page.refDensity === "compact" ? "comfortable" : "compact")
          }

          StyledIconButton {
            visible: !root.editing && !root.keyboard
            Layout.fillWidth: false
            Layout.fillHeight: false
            Layout.preferredWidth: Widget.height
            Layout.preferredHeight: Widget.height
            iconText: "keyboard_command_key"
            iconColor: KeybindManager.page.refGlyphs ? Theme.accent : Theme.foreground
            tooltipText: KeybindManager.page.refGlyphs ? I18n.tr("Modifiers as words") : I18n.tr("Modifiers as symbols")
            onClicked: KeybindManager.page.setRefGlyphs(!KeybindManager.page.refGlyphs)
          }

          StyledText {
            visible: !root.editing && !root.keyboard
            text: root.narrowed ? I18n.tr("{0} of {1} binds", root.shownCount, root.totalCount) : I18n.tr("{0} binds", root.totalCount)
            opacity: 0.6
          }
        },
        StreamedLoader {
          visible: !root.editing && !root.keyboard
          Layout.fillWidth: true
          label: "keybind filter chips"

          sourceComponent: FilterChips {
            groups: [
              {
                "id": "section",
                "options": KeybindManager.keybindings.filter(section => section.binds.length > 0).map(section => ({
                      "value": KeybindFilter.sectionKey(section),
                      "label": (section.undescribed ? I18n.tr("Undescribed") : (section.title ? I18n.tr(section.title) : I18n.tr("Other"))) + "  " + section.binds.length
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
            selection: ({
                "section": KeybindManager.page.sectionFilter,
                "mod": KeybindManager.page.modFilter,
                "source": KeybindManager.page.sourceFilter
              })
            filtering: KeybindManager.page.filtering
            onToggled: (group, value) => KeybindManager.page.toggleFilter(group, value)
            onCleared: KeybindManager.page.clearFilters()
          }
        },
        StreamedLoader {
          visible: root.editing && KeybindManager.editor.binds.length > 0
          Layout.fillWidth: true
          label: "keybind filter chips"

          sourceComponent: FilterChips {
            groups: [
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
                  ] : []).concat(KeybindManager.editor.issueCount > 0 || KeybindManager.page.editIssuesOnly ? [
                  {
                    "value": "issues",
                    "label": I18n.tr("With issues") + "  " + KeybindManager.editor.issueCount
                  }
                ] : [])
              }
            ]
            selection: ({
                "editSection": KeybindManager.page.editSectionFilter,
                "editMod": KeybindManager.page.editModFilter,
                "editState": (KeybindManager.page.editPausedOnly ? ["paused"] : []).concat(KeybindManager.page.editIssuesOnly ? ["issues"] : [])
              })
            filtering: KeybindManager.page.editFiltering
            onToggled: (group, value) => {
              if (group === "editState" && value === "paused")
                KeybindManager.page.editPausedOnly = !KeybindManager.page.editPausedOnly;
              else if (group === "editState")
                KeybindManager.page.editIssuesOnly = !KeybindManager.page.editIssuesOnly;
              else
                KeybindManager.page.toggleFilter(group, value);
            }
            onCleared: KeybindManager.page.clearEditFilters()
          }
        }
      ]

      Loader {
        active: root.editing
        visible: active
        Layout.fillWidth: true
        sourceComponent: BindEditor {
          scrollTo: item => listCard.scrollTo(item, true)
        }
      }

      StyledText {
        visible: !root.editing && !root.keyboard && root.narrowed && root.sections.length === 0
        text: root.lookupId !== "" ? I18n.tr("Nothing is bound to {0}", KeybindManager.displayCombo(KeybindManager.page.lookupCombo)) : root.query !== "" ? I18n.tr("No keybinds match \"{0}\"", root.query) : I18n.tr("No keybinds match the filters")
        opacity: 0.6
        Layout.fillWidth: true
        Layout.topMargin: Widget.padding
      }

      StyledTextButton {
        visible: !root.editing && !root.keyboard && root.lookupId !== "" && root.sections.length === 0
        implicitHeight: Widget.height
        iconText: "add"
        text: I18n.tr("Bind it")
        onClicked: {
          const combo = KeybindManager.page.lookupCombo;
          KeybindManager.page.lookupCombo = "";
          KeybindManager.page.editing = true;
          KeybindManager.editor.addBind({
            "key": combo
          });
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
