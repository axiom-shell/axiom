pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.methods
import qs.components.reusable

// A US keyboard (KeyMap.rows, then KeyMap.extras), each key coloured and
// labelled through hooks: the editor's key map of free keys and the
// keybinds reference's keyboard. `tall` keys show an icon and what the key
// does under its name.
ColumnLayout {
  id: root

  // Hooks, by a key's name: its fill, its ink, whether it takes a click,
  // and for tall keys what it does (a label and an icon; a tooltip shows
  // the label in full)
  property var fillOf: key => Theme.backgroundAlt
  property var inkOf: key => Theme.foreground
  property var clickableOf: key => false
  property var labelOf: key => ""
  property var iconOf: key => ""
  property bool tall: false

  signal clicked(string key)

  // One key unit, the main block being 15 wide
  readonly property real unit: Math.floor((root.width - Widget.spacing / 2 * 14) / 15)
  // The main block's width, which every row is centred to
  readonly property real blockWidth: root.unit * 15 + Widget.spacing / 2 * 14

  spacing: Widget.spacing / 2
  // Its rows are sized from its width, so none fills it: left to them, the
  // layout's minimum and maximum would be their width and lock it (at
  // nothing, or too wide), so only its parent sizes it
  Layout.minimumWidth: 0
  Layout.maximumWidth: Number.POSITIVE_INFINITY

  component KeyButton: Rectangle {
    id: keyButton

    required property var entry
    readonly property bool blank: keyButton.entry.key === ""
    readonly property bool clickable: !keyButton.blank && root.clickableOf(keyButton.entry.key)
    readonly property string does: keyButton.blank ? "" : root.labelOf(keyButton.entry.key)
    readonly property string icon: keyButton.blank ? "" : root.iconOf(keyButton.entry.key)
    readonly property color ink: root.inkOf(keyButton.entry.key)

    implicitHeight: Math.round(Widget.height * (root.tall ? 1.9 : 0.9))
    radius: Widget.radius / 2
    color: keyButton.blank ? "transparent" : root.fillOf(keyButton.entry.key)
    border.width: keyArea.containsMouse && keyButton.clickable ? 1 : 0
    border.color: Theme.foreground

    // Its name: centred, or in the corner of a tall key that does something
    StyledText {
      readonly property bool corner: root.tall && (keyButton.does !== "" || keyButton.icon !== "")
      x: corner ? 4 : (parent.width - width) / 2
      y: corner ? 2 : (parent.height - height) / 2
      width: corner ? implicitWidth : parent.width - Widget.px(4)
      horizontalAlignment: Text.AlignHCenter
      text: keyButton.entry.label
      textColor: keyButton.ink
      opacity: keyButton.blank ? 0.3 : (corner ? 0.7 : 1)
      textSize: Appearance.fontSizeBy(corner ? -3 : -2)
      elide: Text.ElideRight
    }

    Column {
      visible: root.tall && !keyButton.blank
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Widget.spacing
      spacing: 0

      StyledIcon {
        visible: keyButton.icon !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        text: keyButton.icon
        textColor: keyButton.ink
        textSize: Appearance.fontSize
      }

      StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: keyButton.does
        textColor: keyButton.ink
        textSize: Appearance.fontSizeBy(-3)
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: keyArea
      anchors.fill: parent
      enabled: !keyButton.blank
      hoverEnabled: true
      cursorShape: keyButton.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (keyButton.clickable)
        root.clicked(keyButton.entry.key)
    }

    LazyLoader {
      active: root.tall && keyArea.containsMouse && keyButton.does !== ""
      StyledToolTip {
        target: keyButton
        text: keyButton.does
      }
    }
  }

  Repeater {
    model: KeyMap.rows

    delegate: Row {
      id: keyRow
      required property var modelData
      Layout.alignment: Qt.AlignHCenter
      spacing: Widget.spacing / 2

      Repeater {
        model: keyRow.modelData

        delegate: KeyButton {
          required property var modelData
          entry: modelData
          width: root.unit * modelData.width + Widget.spacing / 2 * (modelData.width - 1)
        }
      }
    }
  }

  // Ten to a row, so the rows end with the main block's
  Flow {
    id: extras
    readonly property real keyWidth: Math.floor((width - spacing * 9) / 10)
    Layout.preferredWidth: root.blockWidth
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: Widget.spacing / 2
    spacing: Widget.spacing / 2

    Repeater {
      model: KeyMap.extras

      delegate: KeyButton {
        required property var modelData
        entry: modelData
        width: extras.keyWidth
      }
    }
  }
}
