pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable

// A US keyboard (KeyMap.rows, then KeyMap.extras), each key coloured and
// labelled through hooks: the editor's key map of free keys and the
// keybinds reference's keyboard. `tall` keys show an icon and what the key
// does under its name. Above it the modifier chips, below it what the
// colours mean.
ColumnLayout {
  id: root

  // Hooks, by a key's name: whose it is (a source, coloured by fillFor; axiom's
  // and both take the background's ink), whether it takes a click, and for
  // tall keys what it does (a label and an icon; a tooltip shows the label
  // in full)
  property var sourceOf: key => ""
  property var fillFor: source => Theme.backgroundAlt
  property var clickableOf: key => false
  property var labelOf: key => ""
  property var iconOf: key => ""
  property bool tall: false
  // The modifier chips (shown with showMods), lit for `mods`: they toggle
  // the page's key map modifiers
  property bool showMods: false
  property var mods: []
  // What the colours mean: [[source, label]]
  property var legend: []

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
    readonly property string source: keyButton.blank ? "" : root.sourceOf(keyButton.entry.key)
    readonly property color ink: keyButton.source === "axiom" || keyButton.source === "both" ? Theme.background : Theme.foreground

    implicitHeight: Math.round(Widget.height * (root.tall ? 1.9 : 0.9))
    radius: Widget.radius / 2
    color: keyButton.blank ? "transparent" : root.fillFor(keyButton.source)
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

  Flow {
    visible: root.showMods
    Layout.fillWidth: true
    Layout.bottomMargin: Widget.spacing
    spacing: Widget.spacing / 2

    Repeater {
      model: KeyNames.modifiers

      delegate: SegmentButton {
        required property string modelData
        text: KeyNames.modifierLabel(modelData)
        active: root.mods.includes(modelData)
        onClicked: KeybindManager.page.toggleKeyMapMod(modelData)
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

  // A Flow, from the left: it wraps in a narrow Cheatsheet
  Flow {
    Layout.fillWidth: true
    Layout.topMargin: Widget.spacing
    spacing: Widget.spacing * 2

    Repeater {
      model: root.legend

      delegate: Row {
        id: legendEntry
        required property var modelData
        spacing: Widget.spacing / 2

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Appearance.fontSize
          height: Appearance.fontSize
          radius: Widget.px(3)
          color: root.fillFor(legendEntry.modelData[0])
          border.width: 1
          border.color: Theme.border
        }

        StyledLabel {
          text: legendEntry.modelData[1]
          opacity: 0.7
          textSize: Appearance.fontSizeBy(-2)
        }
      }
    }
  }
}
