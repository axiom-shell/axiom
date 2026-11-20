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
// properties: { count, sortBy: "cpu" | "mem", grow }
Card {
  id: root

  readonly property string sortBy: root.properties.sortBy
  readonly property real rowHeight: Widget.height
  // Room for the command beside both figures
  readonly property bool narrow: root.innerWidth < Appearance.fontSize * 18
  // The header only above two rows or more
  readonly property bool showHeader: root.innerHeight >= Appearance.fontSize * 2 + Widget.spacing + root.rowHeight * 2

  // Grows to list as many as asked for (from compact, to the full layout)
  wantedHeight: root.compact ? 1 : root.height > 0 ? root.height + Math.max(0, root.properties.count - root.fitting) * (root.rowHeight + Widget.spacing / 2) : 0

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
    font.pixelSize: Style.typeCaption
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
        Layout.rightMargin: root.narrow ? Widget.spacing * 1.5 + Widget.smallHeight : Widget.spacing / 2
        horizontalAlignment: Text.AlignRight
        text: "CPU"
        role: "caption"
        tone: root.sortBy === "cpu" ? "accent" : "muted"
      }
      StyledText {
        visible: !root.narrow || root.sortBy === "mem"
        Layout.preferredWidth: numberMetrics.advanceWidth
        Layout.rightMargin: Widget.spacing * 1.5 + Widget.smallHeight
        horizontalAlignment: Text.AlignRight
        text: I18n.tr("Mem")
        role: "caption"
        tone: root.sortBy === "mem" ? "accent" : "muted"
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
            radius: Style.radius
            color: "transparent"

            StateLayer {
              hovered: rowHover.hovered
            }

            HoverHandler {
              id: rowHover
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Widget.spacing
              anchors.rightMargin: Widget.spacing / 2
              spacing: Widget.spacing

              StyledLabel {
                Layout.fillWidth: true
                overflow: "line"
                text: row.proc.command
              }
              StyledLabel {
                visible: !root.narrow || root.sortBy === "cpu"
                Layout.preferredWidth: numberMetrics.advanceWidth
                horizontalAlignment: Text.AlignRight
                text: `${row.proc.cpu.toFixed(1)}%`
                role: "caption"
                tone: root.sortBy === "cpu" ? "accent" : "text"
              }
              StyledLabel {
                visible: !root.narrow || root.sortBy === "mem"
                Layout.preferredWidth: numberMetrics.advanceWidth
                horizontalAlignment: Text.AlignRight
                text: `${row.proc.mem.toFixed(1)}%`
                role: "caption"
                tone: root.sortBy === "mem" ? "accent" : "text"
              }
              FlatIconButton {
                Layout.alignment: Qt.AlignVCenter
                iconText: "close"
                kind: "danger"
                iconSize: Style.iconXs
                size: Widget.smallHeight
                opacity: rowHover.hovered ? 1 : 0
                enabled: rowHover.hovered
                tooltipText: I18n.tr("End process")
                onClicked: SystemManager.kill(row.proc.pid)
              }
            }
          }
        }
      }
    }
  }
}
