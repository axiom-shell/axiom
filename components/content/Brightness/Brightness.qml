pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.services.system
import qs.config
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// Screen brightness (BrightnessManager: a laptop panel's backlight, an
// external monitor over DDC/CI). On one monitor, its slider. On all of
// them, a slider per monitor under one setting every monitor at once; that
// one is greyed out while the monitors differ, and a click on it brings
// them back to their mean. The sliders scroll when the card is short (a
// strip shows the shared one first), and the expand button opens the
// whole card over the grid; compact, the level. Changes here don't open
// the OSD. QuickActions' brightness tile opens this.
// properties: { monitor: "*" (all) | "" (the primary monitor) | a name }
Panel {
  id: root

  readonly property bool all: root.properties.monitor === "*"
  readonly property string monitorName: root.properties.monitor || General.primaryMonitor
  // The monitors it sets, those with a controller
  readonly property var targets: root.all ? BrightnessManager.names : BrightnessManager.names.filter(name => name === root.monitorName)
  readonly property real level: BrightnessManager.average(root.targets)
  // All, with more than one: a row per monitor under the shared one
  readonly property bool perMonitor: root.all && root.targets.length > 1
  // The monitors aren't all at one level (the shared slider greys out)
  readonly property bool desynced: root.perMonitor && root.targets.some(name => Math.abs(BrightnessManager.valueFor(name) - root.level) > 0.005)
  // Room for the header over the sliders
  readonly property bool showHeader: !root.embedded || root.innerHeight >= Appearance.fontSize * 7
  // Some sliders are scrolled out of sight: offer the whole card
  readonly property bool cramped: root.embedded && list.implicitHeight > scroll.height + 1

  fullMinWidth: Appearance.fontSize * 12
  fullMinHeight: Appearance.fontSize * 3.5

  function icon(level) {
    return level < 0.34 ? "brightness_low" : level < 0.67 ? "brightness_medium" : "brightness_high";
  }

  // Values changed outside axiom
  Component.onCompleted: root.targets.forEach(name => BrightnessManager.refresh(name))

  compactContent: CompactFigure {
    icon: root.icon(root.level)
    value: root.targets.length > 0 ? String(Math.round(root.level * 100)) : ""
    unit: root.targets.length > 0 ? "%" : ""
    label: root.targets.length > 0 ? I18n.tr("Brightness") : I18n.tr("No control")
  }

  ModuleHeader {
    visible: root.showHeader && root.targets.length > 0
    icon: root.icon(root.level)
    title: I18n.tr("Brightness")
    ExpandButton {
      module: root
      type: root.cramped ? "Brightness" : ""
      properties: root.properties
    }
  }

  // Nothing to control here
  Item {
    visible: root.targets.length === 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    EmptyState {
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: parent.height
      icon: "brightness_empty"
      text: I18n.tr("No monitor here has a brightness control (a backlight, or ddcutil for DDC/CI)")
    }
  }

  RowLayout {
    visible: root.targets.length > 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 0

    // The shared slider, then a row per monitor (modelled by count:
    // BrightnessManager.names only changes when a monitor comes or goes)
    StyledScrollView {
      id: scroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: list.implicitHeight
      contentPadding: 0
      showScrollBar: list.implicitHeight > scroll.height + 1

      ColumnLayout {
        id: list
        width: scroll.availableWidth
        spacing: 2

        // Every target at once (the one monitor, or all)
        AudioRow {
          id: allRow
          icon: root.icon(root.level)
          title: root.all ? I18n.tr("All monitors") : root.monitorName
          subtitle: root.desynced ? I18n.tr("Out of sync: click to sync") : ""
          volume: root.level
          muted: root.desynced
          showMute: false
          onVolumeMoved: v => BrightnessManager.setMany(root.targets, v, true)

          // Out of sync: a click anywhere brings every monitor to the mean
          MouseArea {
            anchors.fill: parent
            visible: root.desynced
            cursorShape: Qt.PointingHandCursor
            onClicked: BrightnessManager.setMany(root.targets, root.level, true)
          }
        }

        StyledSeparator {
          visible: root.perMonitor
          Layout.fillWidth: true
          separatorColor: Theme.backgroundHighlight
        }

        Repeater {
          model: root.perMonitor ? root.targets.length : 0

          AudioRow {
            required property int index
            readonly property string name: root.targets[index] ?? ""
            readonly property real value: BrightnessManager.valueFor(name)
            icon: root.icon(value)
            title: name
            volume: value
            showMute: false
            onVolumeMoved: v => BrightnessManager.set(name, v, true)
          }
        }
      }
    }

    // Without the header, the expand button sits beside the sliders
    ExpandButton {
      Layout.alignment: Qt.AlignTop
      module: root
      type: !root.showHeader && root.cramped ? "Brightness" : ""
      properties: root.properties
    }
  }
}
