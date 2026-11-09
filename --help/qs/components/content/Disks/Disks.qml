pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// Usage bar per mount point, under a header where there's room; side by
// side when they don't fit stacked; compact, the first one's figure.
// properties: { paths: ["/", "/home"] }
Card {
  id: root

  readonly property var paths: root.properties.paths?.length > 0 ? root.properties.paths : ["/"]

  // One disk's rows (path and sizes, then the bar), and the room inside
  readonly property real diskHeight: Appearance.fontSize * 1.4 + Widget.px(8) + Widget.spacing / 2
  // Stacked unless they don't fit that way, then as many across as fit
  readonly property int columns: {
    const n = root.paths.length;
    const stacked = n * root.diskHeight + (n - 1) * Widget.spacing * 1.5;
    return stacked <= root.innerHeight ? 1 : Math.max(1, Math.min(n, Math.floor(root.innerWidth / (Appearance.fontSize * 12))));
  }
  readonly property int diskRows: Math.ceil(root.paths.length / root.columns)
  readonly property bool showHeader: root.innerHeight >= Appearance.fontSize * 2 + Widget.spacing + root.diskRows * root.diskHeight + (root.diskRows - 1) * Widget.spacing * 1.5

  fullMinWidth: Appearance.fontSize * 7
  fullMinHeight: Appearance.fontSize * 3

  function register() {
    SystemManager.acquire(root, {
      "metrics": ["disk"],
      "diskPaths": root.paths
    });
  }
  onPathsChanged: register()
  Component.onCompleted: register()
  Component.onDestruction: SystemManager.release(root)

  function barColor(ratio) {
    return ratio > 0.9 ? Theme.error : ratio > 0.75 ? Theme.warning : Theme.accent;
  }

  // Compact: the first path's usage
  compactContent: CompactFigure {
    readonly property var usage: SystemManager.disks[root.paths[0]] ?? null
    icon: "hard_drive"
    iconColor: root.barColor((usage?.usage ?? 0) / 100)
    value: usage ? String(Math.round(usage.usage)) : "…"
    unit: usage ? "%" : ""
    label: root.paths[0]
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    ModuleHeader {
      visible: root.showHeader
      icon: "hard_drive"
      title: I18n.tr("Disks")
    }

    // The disks, centred in the space under the header
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      GridLayout {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        columns: root.columns
        columnSpacing: root.pad
        rowSpacing: Widget.spacing * 1.5
        uniformCellWidths: true

        Repeater {
          model: root.compact ? [] : root.paths

          ColumnLayout {
            id: disk
            required property string modelData
            readonly property var usage: SystemManager.disks[disk.modelData] ?? null
            readonly property real ratio: disk.usage ? disk.usage.usage / 100 : 0
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: Widget.spacing / 2

            RowLayout {
              Layout.fillWidth: true
              StyledText {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                text: disk.modelData
                font.bold: true
              }
              // Narrow: the used size only, then nothing beside the path
              StyledText {
                readonly property bool narrow: disk.width < Appearance.fontSize * 12
                visible: disk.width >= Appearance.fontSize * 7
                text: !disk.usage ? "…" : narrow ? Utils.formatSize(disk.usage.used) : Utils.formatSize(disk.usage.used) + " / " + Utils.formatSize(disk.usage.total)
                textSize: Appearance.fontSizeBy(-2)
                opacity: 0.7
              }
            }
            LevelMeter {
              Layout.fillWidth: true
              Layout.preferredHeight: thickness
              thickness: Widget.px(8)
              share: disk.ratio
              trackColor: Theme.backgroundAlt
              fillColor: root.barColor(disk.ratio)
            }
          }
        }
      }
    }
  }
}
