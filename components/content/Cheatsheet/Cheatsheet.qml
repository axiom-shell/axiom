pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts
import qs.services.ui

// The keybinds as a read-only cheat sheet (KeybindManager, as Hyprland
// reports them), sections in as many columns as fit, with a search field of
// its own (the Keybinds page's filters are left alone). `sections` keeps to
// some sections (by title); undescribed binds show only with
// `showUndescribed`. A short card runs the first binds along one row;
// compact, the count. `view` "keyboard" shows a keyboard under `mods`
// instead. A click on one of axiom's binds opens it in the Keybinds editor.
// properties: { sections, showUndescribed, view, mods }
Panel {
  id: root

  readonly property string query: field.text.trim()
  readonly property var sections: KeybindFilter.filter(KeybindManager.keybindings.filter(section => !section.undescribed || root.properties.showUndescribed), root.query, {
    "sections": root.properties.sections ?? []
  })
  readonly property int bindCount: root.sections.reduce((sum, section) => sum + section.binds.length, 0)
  readonly property int columnCount: Math.max(1, Math.floor((root.innerWidth + Widget.spacing * 2) / (Appearance.fontSize * 22)))
  readonly property var columns: KeybindFilter.columns(root.sections, root.columnCount)
  // The binds of every section, for the strip
  readonly property var allBinds: [].concat(...root.sections.map(section => section.binds))

  readonly property bool keyboard: root.properties.view === "keyboard"
  // One row: binds side by side
  readonly property bool strip: !root.keyboard && root.embedded && root.innerHeight < Appearance.fontSize * 6
  readonly property bool showSearch: !root.keyboard && !root.strip && (!root.embedded || root.innerHeight >= Appearance.fontSize * 10)

  function edit(bindIndex) {
    KeybindManager.editBind(bindIndex);
    ShellManager.openOverlayPage("Keybinds");
  }

  implicitWidth: Appearance.fontSize * 30
  fullMinWidth: Appearance.fontSize * 14
  fullMinHeight: Appearance.fontSize * 3
  wantsKeyboardFocus: root.showSearch
  spacing: Widget.spacing

  Component.onCompleted: {
    if (KeybindManager.keybindings.length === 0)
      KeybindManager.refresh();
  }

  compactContent: CompactFigure {
    icon: "keyboard"
    value: String(root.bindCount)
    label: I18n.tr("keybinds")
  }

  RowLayout {
    visible: root.showSearch
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledTextEntry {
      id: field
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      placeholderText: I18n.tr("Search keybinds")
      input.wrapMode: Text.NoWrap
      Keys.onEscapePressed: event => {
        if (field.text === "") {
          event.accepted = false;
          return;
        }
        field.text = "";
      }
    }
    StyledText {
      text: I18n.tr("{0} binds", root.bindCount)
      textSize: Appearance.fontSizeBy(-2)
      textColor: Theme.foregroundAlt
    }
  }

  // Built only while shown
  StreamedLoader {
    visible: root.keyboard
    wanted: root.keyboard
    Layout.fillWidth: true
    label: "keyboard reference"

    sourceComponent: KeyboardReference {
      sections: root.sections
      mods: root.properties.mods
      showMods: false
      onEditRequested: bindIndex => root.edit(bindIndex)
    }
  }

  // Nothing (that matches)
  Item {
    visible: !root.keyboard && !root.strip && root.sections.length === 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredHeight: root.embedded ? -1 : Appearance.fontSize * 8
    EmptyState {
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: parent.height
      icon: root.query !== "" ? "search_off" : "keyboard"
      text: root.query !== "" ? I18n.tr("No keybinds match \"{0}\"", root.query) : I18n.tr("No keybinds to show")
    }
  }

  // The sections in columns, scrolling
  Flickable {
    id: flick
    visible: !root.keyboard && !root.strip && root.sections.length > 0
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? -1 : Math.min(columnsRow.implicitHeight, Appearance.fontSize * 30)
    contentHeight: columnsRow.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    RowLayout {
      id: columnsRow
      width: flick.width
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
                onEditRequested: bindIndex => root.edit(bindIndex)
              }
            }
          }
        }
      }
    }
  }

  // A short card: the first binds along a row, as many as fit
  Flow {
    visible: root.strip
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Widget.spacing * 3
    clip: true

    Repeater {
      model: root.strip ? Math.min(root.allBinds.length, 12) : 0

      KeybindRow {
        required property int index
        bind: root.allBinds[index]
        onEditRequested: bindIndex => root.edit(bindIndex)
        width: Math.min(implicitWidth, root.innerWidth)
      }
    }
  }
}
