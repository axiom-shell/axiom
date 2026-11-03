pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.components.methods
import qs.components.reusable

// One example setup (SavedConfigsManager.examples) as a card: a small
// screen drawn in its theme, with its bars on their edges in their style,
// its docks and the screen border, then its palette, title and description.
// A click applies it at once.
StyledContainer {
  id: root

  // { name, title, description, theme, screenBorder, bars: [{ location,
  // background }], docks: [{ edge }] }
  required property var example

  // Its theme's preview colors, or the running theme's for one not found
  readonly property var preview: ThemeFamilies.previewOf(ThemeManager.themeFamilies, root.example.theme ?? "") ?? ({})
  readonly property color background: root.preview.background ?? Theme.background
  readonly property color foreground: root.preview.foreground ?? Theme.foreground
  readonly property color accent: root.preview.accent ?? Theme.accent
  readonly property bool applied: SavedConfigsManager.activeSource === root.example.name

  implicitHeight: column.implicitHeight + Widget.padding * 2
  borderWidth: 2
  borderColor: root.applied ? Theme.accent : area.containsMouse ? Theme.border : "transparent"

  ColorGlide on borderColor {}

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.spacing / 2

    // The screen, 16:10
    Rectangle {
      id: screen
      Layout.fillWidth: true
      Layout.preferredHeight: width * 10 / 16
      radius: Widget.radius / 2
      color: root.background
      clip: true

      // How thick a bar is, and how far a floating one sits off its edge
      readonly property real thickness: height * 0.1
      readonly property real gap: height * 0.04

      Rectangle {
        anchors.fill: parent
        visible: root.example.screenBorder === true
        radius: parent.radius
        color: "transparent"
        border.width: Math.max(1, screen.gap / 2)
        border.color: Qt.alpha(root.foreground, 0.3)
      }

      Repeater {
        model: root.example.bars ?? []

        // A bar on its edge of the screen: a strip along it (solid, or
        // held off the edge when floating), a pill per group of widgets
        // (pills, floating pills), or the widgets alone (transparent). Its
        // groups sit at the start, middle and end, as a bar's sections do
        delegate: Item {
          id: bar
          required property var modelData
          readonly property string location: bar.modelData.location
          readonly property string style: bar.modelData.background
          readonly property bool across: bar.location === "top" || bar.location === "bottom"
          readonly property bool floats: bar.style === "floating" || bar.style === "floatingPills"
          readonly property bool pills: bar.style === "pills" || bar.style === "floatingPills"
          readonly property real inset: bar.floats ? screen.gap : bar.pills ? screen.gap / 2 : 0
          // Its length along the edge
          readonly property real length: bar.across ? bar.width : bar.height

          x: bar.location === "right" ? screen.width - screen.thickness - bar.inset : bar.inset
          y: bar.location === "bottom" ? screen.height - screen.thickness - bar.inset : bar.inset
          width: bar.across ? screen.width - bar.inset * 2 : screen.thickness
          height: bar.across ? screen.thickness : screen.height - bar.inset * 2

          Rectangle {
            anchors.fill: parent
            visible: bar.style === "solid" || bar.style === "floating"
            radius: bar.floats ? Math.min(width, height) / 2 : 0
            color: Qt.alpha(root.foreground, 0.15)
          }

          Repeater {
            model: 3

            delegate: Rectangle {
              id: group
              required property int index
              // The middle group is the longest, as a bar's centre usually is
              readonly property real size: bar.length * (group.index === 1 ? 0.24 : 0.16)
              readonly property real pad: bar.pills ? 0 : screen.thickness * 0.3
              readonly property real at: group.index === 0 ? group.pad : group.index === 1 ? (bar.length - group.size) / 2 : bar.length - group.size - group.pad
              x: bar.across ? group.at : 0
              y: bar.across ? 0 : group.at
              width: bar.across ? group.size : screen.thickness
              height: bar.across ? screen.thickness : group.size
              radius: Math.min(width, height) / 2
              color: bar.pills ? Qt.alpha(root.foreground, 0.2) : "transparent"

              // The widgets: the first group's in the accent
              Rectangle {
                anchors.centerIn: parent
                width: bar.across ? group.size * 0.6 : screen.thickness * 0.35
                height: bar.across ? screen.thickness * 0.35 : group.size * 0.6
                radius: Math.min(width, height) / 2
                color: group.index === 0 ? root.accent : Qt.alpha(root.foreground, 0.6)
              }
            }
          }
        }
      }

      Repeater {
        model: root.example.docks ?? []

        // A pill centred on its edge, past any bar there
        delegate: Rectangle {
          id: dock
          required property var modelData
          readonly property bool across: modelData.edge === "top" || modelData.edge === "bottom"
          readonly property real offset: screen.gap * 1.5 + ((root.example.bars ?? []).some(entry => entry.location === dock.modelData.edge) ? screen.thickness + screen.gap : 0)
          width: across ? screen.width * 0.24 : screen.thickness
          height: across ? screen.thickness : screen.width * 0.24
          radius: Math.min(width, height) / 2
          color: Qt.alpha(root.foreground, 0.2)
          x: across ? (screen.width - width) / 2 : modelData.edge === "left" ? offset : screen.width - width - offset
          y: across ? (modelData.edge === "top" ? offset : screen.height - height - offset) : (screen.height - height) / 2
        }
      }
    }

    // Its palette
    Row {
      spacing: Widget.spacing / 2

      Repeater {
        model: root.preview.colors ?? []

        delegate: Rectangle {
          required property string modelData
          width: Widget.px(10)
          height: Widget.px(10)
          radius: width / 2
          color: modelData
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      StyledText {
        Layout.fillWidth: true
        text: root.example.title
        textFormat: Text.PlainText
        font.bold: true
        elide: Text.ElideRight
      }

      StatusChip {
        shown: root.applied
        color: Theme.accent
        text: I18n.tr("Applied")
      }
    }

    StyledText {
      Layout.fillWidth: true
      text: root.example.description
      textFormat: Text.PlainText
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: SavedConfigsManager.applyExample(root.example.name)
  }
}
