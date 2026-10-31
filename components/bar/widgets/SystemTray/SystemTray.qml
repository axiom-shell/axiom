pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.SystemTray
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The status notifier items, one icon each, in a row (or column, on a
// vertical bar). Hovering an item with a menu opens it as a popout.
BarWidget {
  id: root

  // Each icon the size of every other bar widget's (IconTextWidget's)
  readonly property int iconSize: Math.round(barConfig.fontSize)
  readonly property bool showPassive: properties.showPassive
  // Sized by the bar, as BarIconWidget does
  readonly property real padding: barConfig.widgetPadding
  readonly property real spacing: barConfig.widgetSpacing * 1.5
  // No item showing (none, or only passive ones while those are hidden):
  // a zero natural size, which the bar skips, as IconTextWidget's `hidden`
  readonly property bool hidden: items.implicitWidth <= 0

  hasBackground: !hidden
  accentColor: Theme.resolveColor(properties.backgroundColor)

  implicitWidth: isVertical ? barConfig.widgetSize : hidden ? 0 : items.implicitWidth + padding * 2
  implicitHeight: isVertical ? (hidden ? 0 : items.implicitHeight + padding * 2) : barConfig.widgetSize

  Grid {
    id: items
    anchors.centerIn: parent
    flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight
    rows: root.isVertical ? Math.max(1, trayItems.count) : 1
    columns: root.isVertical ? 1 : Math.max(1, trayItems.count)
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
      id: trayItems
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
              "trayItem": trayItem.modelData,
              "barConfig": root.barConfig,
              "isVertical": root.isVertical
            })
        }
      }
    }
  }
}
