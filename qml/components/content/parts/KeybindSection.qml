pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable

// One section of the keybinds reference as a card: its icon and title,
// then its rows grouped by modifiers (BindRows.byModifiers), each group
// under its modifiers, with the keys in one aligned column
StyledContainer {
  id: root

  // A KeybindManager section, binds possibly filtered by a search
  required property var section
  // It, or an empty one while the delegate is torn down (section goes null
  // before its bindings stop)
  readonly property var _section: root.section ?? {
    "title": "",
    "undescribed": false,
    "binds": []
  }

  readonly property bool compact: KeybindManager.page.refDensity === "compact"
  // Headers and rows in order: { mods, row, count } (row null for a
  // header, which counts its group's rows)
  readonly property var items: [].concat(...BindRows.byModifiers(root._section.binds).map(group => (group.mods.length > 0 ? [
        {
          "mods": group.mods,
          "row": null,
          "count": group.rows.length
        }
      ] : []).concat(group.rows.map(row => ({
          "mods": group.mods,
          "row": row
        })))))
  // The key column's width: the widest of the rows' keys, measured from the
  // rows built (_measureKeys), never from reports kept across a rebuild
  property real keyWidth: 0

  signal editRequested(int bindIndex)

  // Once a frame at most (Qt.callLater folds the calls): a row built, gone
  // or resized
  function _measureKeys() {
    let widest = 0;
    for (let i = 0; i < rows.count; i++)
      widest = Math.max(widest, root._keyWidthOf(rows.itemAt(i)));
    root.keyWidth = widest;
  }

  // (untyped: qmllint knows only Item's members)
  function _keyWidthOf(delegate) {
    return delegate?.rowKeyWidth ?? 0;
  }

  Layout.fillWidth: true
  implicitHeight: column.implicitHeight + Widget.padding * 2

  ColumnLayout {
    id: column
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Widget.padding
    spacing: root.compact ? 0 : Widget.spacing / 2

    RowLayout {
      Layout.fillWidth: true
      Layout.bottomMargin: Widget.spacing / 2
      spacing: Widget.spacing

      StyledIcon {
        text: root._section.undescribed ? "help" : KeybindManager.sectionIcon(root._section.title)
        textColor: Theme.accent
      }

      StyledLabel {
        text: KeybindManager.sectionTitle(root._section)
        textColor: Theme.accent
        font.weight: Font.Bold
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      StyledLabel {
        text: root._section.binds.length
        opacity: 0.5
        textSize: Appearance.fontSizeBy(-2)
      }
    }

    StyledText {
      visible: root._section.undescribed
      text: I18n.tr("A bind's description sets its label, and a \"Section: Label\" prefix picks its section.")
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Repeater {
      id: rows
      model: root.items
      onItemAdded: Qt.callLater(root._measureKeys)
      onItemRemoved: Qt.callLater(root._measureKeys)

      delegate: Item {
        id: entry
        required property var modelData
        required property int index
        readonly property string groupKey: KeybindManager.page.refGroupKey(root._section, entry.modelData.mods)
        readonly property bool folded: KeybindManager.page.refFolded.includes(entry.groupKey)
        readonly property bool grouped: entry.modelData.mods.length > 0
        // Its keys' own width (0 for a header)
        readonly property real rowKeyWidth: entry.modelData.row ? row.keyImplicitWidth : 0
        onRowKeyWidthChanged: Qt.callLater(root._measureKeys)
        Layout.fillWidth: true
        visible: !entry.modelData.row || !entry.folded
        implicitHeight: entry.modelData.row ? row.implicitHeight : header.implicitHeight

        // A group's modifiers, then +; a click folds it. Built only for a header
        Loader {
          id: header
          active: !entry.modelData.row
          visible: active
          width: parent.width
          sourceComponent: Item {
            implicitHeight: headerLine.implicitHeight + (entry.index > 0 ? Widget.spacing : 0)

            Rectangle {
              anchors.fill: headerLine
              anchors.margins: -2
              radius: Widget.radius / 2
              color: Qt.alpha(Theme.backgroundHighlight, headerArea.containsMouse ? 0.6 : 0)

              ColorGlide on color {
                duration: Appearance.animFast
              }
            }

            RowLayout {
              id: headerLine
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Widget.padding / 2
              anchors.rightMargin: Widget.padding / 2
              spacing: Widget.spacing / 2

              ModifierCap {
                mods: entry.modelData.mods
                glyphs: KeybindManager.page.refGlyphs
                compact: true
                opacity: 0.8
              }

              StyledLabel {
                text: "+"
                opacity: 0.5
              }

              StyledLabel {
                visible: entry.folded
                text: entry.modelData.count ?? ""
                opacity: 0.5
                textSize: Appearance.fontSizeBy(-2)
              }

              Item {
                Layout.fillWidth: true
              }

              StyledIcon {
                text: "expand_more"
                textColor: headerArea.containsMouse ? Theme.accent : Theme.foregroundAlt
                rotation: entry.folded ? -90 : 0

                Glide on rotation {}
              }
            }

            MouseArea {
              id: headerArea
              anchors.fill: headerLine
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: KeybindManager.page.toggleRefFold(entry.groupKey)
            }
          }
        }

        KeybindRow {
          id: row
          visible: !!entry.modelData.row
          // Rows under a group's modifiers sit in from them
          x: entry.grouped ? Widget.padding : 0
          width: parent.width - x
          bind: entry.modelData.row ?? ({
              "label": "",
              "combos": [],
              "ids": [],
              "action": "",
              "overrides": ""
            })
          groupMods: entry.modelData.mods
          keyWidth: root.keyWidth
          onEditRequested: bindIndex => root.editRequested(bindIndex)
        }
      }
    }
  }
}
