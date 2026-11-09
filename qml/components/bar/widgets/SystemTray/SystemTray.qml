pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.SystemTray
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The status notifier items, one icon each, in a row (or column, on a
// vertical bar). Hovering an item with a menu opens it as a popout. A
// head icon (`leadIcon`) before them is its icon part on a split bar
// (SplitLead).
BarWidget {
  id: root

  // Each icon the size of every other bar widget's (IconTextWidget's)
  readonly property int iconSize: Math.round(barConfig.fontSize)
  readonly property bool showPassive: properties.showPassive
  // Sized by the bar, as BarIconWidget does
  readonly property real padding: barConfig.innerPadding
  readonly property real spacing: barConfig.innerGap * 1.5
  // No item showing (none, or only passive ones while those are hidden):
  // a zero natural size, which the bar skips, as IconTextWidget's `hidden`
  readonly property bool hidden: items.implicitWidth <= 0

  hasBackground: !hidden
  accentField: "backgroundColor"

  readonly property real _itemsLength: isVertical ? items.implicitHeight : items.implicitWidth
  // Where the head and the items after it start, centred in the widget
  readonly property real _start: Math.round(((isVertical ? height : width) - lead.length - _itemsLength) / 2)

  implicitWidth: isVertical ? barConfig.thickness : hidden ? 0 : lead.length + items.implicitWidth + padding * 2
  implicitHeight: isVertical ? (hidden ? 0 : lead.length + items.implicitHeight + padding * 2) : barConfig.thickness

  splits: lead.splits
  splitAt: lead.splitAt
  splitPart: lead.splitPart

  SplitLead {
    id: lead
    barConfig: root.barConfig
    start: root._start
    icon: root.hidden ? "" : root.properties.leadIcon
    iconColor: root.colors.icon
  }

  Grid {
    id: items
    x: root.isVertical ? Math.round((root.width - width) / 2) : root._start + lead.length
    y: root.isVertical ? root._start + lead.length : Math.round((root.height - height) / 2)
    // One line of the shown icons (-1: counted by the Grid); each 1 waits
    // for the other to leave it, so a bar turning never makes it 1 by 1
    rows: !root.isVertical && columns === -1 ? 1 : -1
    columns: root.isVertical && rows === -1 ? 1 : -1
    spacing: root.spacing

    // An app's icon arriving (or a passive one showing) grows in; the
    // others make room for it
    add: Transition {
      NumberAnimation {
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
      NumberAnimation {
        property: "scale"
        from: 0.6
        to: 1
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
    }
    move: Transition {
      NumberAnimation {
        properties: "x,y"
        duration: Appearance.animFast
        easing.type: Appearance.easing
      }
    }

    Repeater {
      model: SystemTray.items

      Item {
        id: trayItem
        required property SystemTrayItem modelData
        visible: root.showPassive || modelData.status !== Status.Passive
        width: root.iconSize
        height: root.iconSize

        Image {
          anchors.centerIn: parent
          source: {
            const appName = trayItem.modelData.id || trayItem.modelData.title || "";
            return (appName && IconsConfig.overrides[appName]) || trayItem.modelData.icon || "";
          }
          sourceSize.width: root.iconSize
          sourceSize.height: root.iconSize
          fillMode: Image.PreserveAspectFit
          smooth: true
        }

        // Hovered through the bar's hit area, which lies over the icons
        // (BarWidgetHost.hitArea)
        QtObject {
          id: iconHover
          readonly property bool hovered: root.hitArea?.hovers(trayItem) ?? false
        }

        PopoutAnchor {
          hitArea: root.hitArea ? iconHover : null
          popoutName: "SystemTray"
          openDelay: 150
          active: root.properties.popout.enabled && trayItem.modelData.hasMenu
          extraData: ({
              "trayItem": trayItem.modelData
            })
        }
      }
    }
  }
}
