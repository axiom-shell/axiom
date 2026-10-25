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

  readonly property bool compact: KeybindManager.refDensity === "compact"
  // Headers and rows in order: { mods, row } (row null for a header)
  readonly property var items: [].concat(...BindRows.byModifiers(root.section.binds).map(group => (group.mods.length > 0 ? [
        {
          "mods": group.mods,
          "row": null
        }
      ] : []).concat(group.rows.map(row => ({
          "mods": group.mods,
          "row": row
        })))))
  // The rows' key widths by item index; the column takes the widest
  property var _keyWidths: ({})
  readonly property real keyWidth: Object.keys(root._keyWidths).reduce((widest, i) => Math.max(widest, root._keyWidths[i]), 0)

  signal editRequested(int bindIndex)

  function _reportKeyWidth(index, width) {
    if (root._keyWidths[index] === width)
      return;
    const next = Object.assign({}, root._keyWidths);
    next[index] = width;
    root._keyWidths = next;
  }

  onItemsChanged: root._keyWidths = {}

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
        text: root.section.undescribed ? "help" : KeybindManager.sectionIcon(root.section.title)
        textColor: Theme.accent
      }

      StyledText {
        text: root.section.undescribed ? I18n.tr("Undescribed") : (root.section.title ? I18n.tr(root.section.title) : I18n.tr("Other"))
        textColor: Theme.accent
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      StyledText {
        text: root.section.binds.length
        opacity: 0.5
        textSize: Appearance.fontSizeBy(-2)
      }
    }

    StyledText {
      visible: root.section.undescribed
      text: I18n.tr("A bind's description sets its label, and a \"Section: Label\" prefix picks its section.")
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }

    Repeater {
      model: root.items

      delegate: Item {
        id: item
        required property var modelData
        required property int index
        readonly property string groupKey: KeybindManager.refGroupKey(root.section, item.modelData.mods)
        readonly property bool folded: KeybindManager.refFolded.includes(item.groupKey)
        readonly property bool grouped: item.modelData.mods.length > 0
        Layout.fillWidth: true
        visible: !item.modelData.row || !item.folded
        implicitHeight: item.modelData.row ? row.implicitHeight : header.implicitHeight

        // A group's modifiers, then +; a click folds it
        Item {
          id: header
          visible: !item.modelData.row
          width: parent.width
          implicitHeight: headerLine.implicitHeight + (item.index > 0 ? Widget.spacing : 0)

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
              mods: item.modelData.mods
              glyphs: KeybindManager.refGlyphs
              compact: true
              opacity: 0.8
            }

            StyledText {
              text: "+"
              opacity: 0.5
            }

            StyledText {
              visible: item.folded
              text: root.section.binds.filter(r => (r.combos[0]?.mods ?? []).join("+") === item.modelData.mods.join("+")).length
              opacity: 0.5
              textSize: Appearance.fontSizeBy(-2)
            }

            Item {
              Layout.fillWidth: true
            }

            StyledIcon {
              text: "expand_more"
              textColor: headerArea.containsMouse ? Theme.accent : Theme.foregroundAlt
              rotation: item.folded ? -90 : 0

              Glide on rotation {}
            }
          }

          MouseArea {
            id: headerArea
            anchors.fill: headerLine
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: KeybindManager.toggleRefFold(item.groupKey)
          }
        }

        KeybindRow {
          id: row
          visible: !!item.modelData.row
          // Rows under a group's modifiers sit in from them
          x: item.grouped ? Widget.padding : 0
          width: parent.width - x
          bind: item.modelData.row ?? ({
              "label": "",
              "combos": [],
              "ids": [],
              "action": "",
              "overrides": ""
            })
          groupMods: item.modelData.mods
          keyWidth: root.keyWidth
          onKeyImplicitWidthChanged: if (item.modelData.row)
            root._reportKeyWidth(item.index, keyImplicitWidth)
          Component.onCompleted: if (item.modelData.row)
            root._reportKeyWidth(item.index, keyImplicitWidth)
          onEditRequested: bindIndex => root.editRequested(bindIndex)
        }
      }
    }
  }
}
