pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// The busiest processes, with a kill button on hover. Narrow, only the
// sorted figure; short, no header; compact, the busiest one's figure.
// properties: { count, sortBy: "cpu" | "mem" }
Card {
  id: root

  readonly property string sortBy: root.properties.sortBy
  readonly property real rowHeight: Widget.height
  // Room for the command beside both figures
  readonly property bool narrow: root.innerWidth < Appearance.fontSize * 18
  // The header only above two rows or more
  readonly property bool showHeader: root.innerHeight >= Appearance.fontSize * 2 + Widget.spacing + root.rowHeight * 2

  fullMinWidth: Appearance.fontSize * 9
  fullMinHeight: Widget.height + Appearance.fontSize * 1.5
  // As many as asked for, and as fit
  readonly property int fitting: Math.max(1, Math.floor((list.height + Widget.spacing / 2) / (root.rowHeight + Widget.spacing / 2)))
  // Not `rows`: that is the slot size in Card
  readonly property var processes: SystemManager.processes.slice().sort((a, b) => b[root.sortBy] - a[root.sortBy]).slice(0, Math.min(root.properties.count, root.fitting))

  Component.onCompleted: SystemManager.acquire(root, {
    "metrics": ["processes"],
    "interval": 3000
  })
  Component.onDestruction: SystemManager.release(root)

  TextMetrics {
    id: numberMetrics
    text: "100.0%"
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSizeBy(-1)
  }

  TextMetrics {
    id: killMetrics
    text: "close"
    font.family: Appearance.iconFamily
    font.pixelSize: Appearance.fontSize
  }

  // Compact: the busiest process
  compactContent: CompactFigure {
    readonly property var busiest: root.processes[0] ?? null
    icon: "bug_report"
    value: busiest ? busiest[root.sortBy].toFixed(0) : "…"
    unit: busiest ? "%" : ""
    label: busiest?.command ?? ""
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    ModuleHeader {
      visible: root.showHeader
      icon: "bug_report"
      title: I18n.tr("Processes")
      // Column heads over the figures (the kill button's room at the end)
      StyledText {
        visible: !root.narrow || root.sortBy === "cpu"
        Layout.preferredWidth: numberMetrics.advanceWidth
        Layout.rightMargin: root.narrow ? Widget.spacing * 1.5 + killMetrics.advanceWidth : Widget.spacing / 2
        horizontalAlignment: Text.AlignRight
        text: "CPU"
        textColor: root.sortBy === "cpu" ? Theme.accent : Theme.foreground
        textSize: Appearance.fontSizeBy(-2)
        opacity: 0.7
      }
      StyledText {
        visible: !root.narrow || root.sortBy === "mem"
        Layout.preferredWidth: numberMetrics.advanceWidth
        Layout.rightMargin: Widget.spacing * 1.5 + killMetrics.advanceWidth
        horizontalAlignment: Text.AlignRight
        text: I18n.tr("Mem")
        textColor: root.sortBy === "mem" ? Theme.accent : Theme.foreground
        textSize: Appearance.fontSizeBy(-2)
        opacity: 0.7
      }
    }

    Item {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true

      Column {
        width: parent.width
        spacing: Widget.spacing / 2

        // Modelled by count: the processes are a new array every sample, which
        // would recreate the delegates (and drop the hover) each time
        Repeater {
          model: root.processes.length

          Rectangle {
            id: row
            required property int index
            readonly property var proc: root.processes[index] ?? ({
                "command": "",
                "cpu": 0,
                "mem": 0,
                "pid": 0
              })
            width: parent.width
            height: root.rowHeight
            radius: Widget.radius
            color: rowHover.hovered ? Theme.backgroundHighlight : "transparent"

            HoverHandler {
              id: rowHover
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Widget.spacing
              anchors.rightMargin: Widget.spacing / 2
              spacing: Widget.spacing

              StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: row.proc.command
              }
              StyledText {
                visible: !root.narrow || root.sortBy === "cpu"
                Layout.preferredWidth: numberMetrics.advanceWidth
                horizontalAlignment: Text.AlignRight
                text: `${row.proc.cpu.toFixed(1)}%`
                textColor: root.sortBy === "cpu" ? Theme.accent : Theme.foreground
                textSize: Appearance.fontSizeBy(-1)
              }
              StyledText {
                visible: !root.narrow || root.sortBy === "mem"
                Layout.preferredWidth: numberMetrics.advanceWidth
                horizontalAlignment: Text.AlignRight
                text: `${row.proc.mem.toFixed(1)}%`
                textColor: root.sortBy === "mem" ? Theme.accent : Theme.foreground
                textSize: Appearance.fontSizeBy(-1)
                opacity: 0.8
              }
              StyledIcon {
                Layout.preferredWidth: killMetrics.advanceWidth
                opacity: rowHover.hovered ? 1 : 0
                text: "close"
                textColor: Theme.error
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: SystemManager.kill(row.proc.pid)
                }
              }
            }
          }
        }
      }
    }
  }
}
