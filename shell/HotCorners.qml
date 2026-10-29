pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.hosts.popout

// Each hot corner (HotCorners.items) on the screens its target puts it on:
// a transparent pixel of a window in its corner, on Top (so it's quiet
// under a fullscreen window, as the bars are) and mapped after the bars
// (LayerSlot), running its action (ShellManager.runAction) once the pointer
// has rested there for its delay, and again only after it left. Keyed by
// id, so editing one corner rebuilds only it.
Scope {
  Variants {
    // Once the layer rules are in (CompositorManager.surfacesReady), so
    // each maps in its place after the bars and border
    model: CompositorManager.surfacesReady ? HotCornersConfig.ids : []

    delegate: Scope {
      id: entry
      required property string modelData
      readonly property var item: HotCornersConfig.itemById(modelData)

      Variants {
        model: entry.item ? General.screensFor(entry.item.screen) : []

        delegate: PanelWindow {
          id: corner
          required property ShellScreen modelData
          readonly property string _corner: entry.item?.corner ?? "topLeft"

          screen: modelData
          visible: slot.shown
          WlrLayershell.layer: WlrLayer.Top
          WlrLayershell.namespace: "axiom-hot-corner"
          exclusionMode: ExclusionMode.Ignore
          color: "transparent"
          implicitWidth: 1
          implicitHeight: 1
          anchors {
            top: corner._corner.startsWith("top")
            bottom: corner._corner.startsWith("bottom")
            left: corner._corner.endsWith("Left")
            right: corner._corner.endsWith("Right")
          }

          LayerSlot {
            id: slot
            window: corner
            namespace: "axiom-hot-corner"
          }

          MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            onEntered: dwell.restart()
            onExited: dwell.stop()
          }

          Timer {
            id: dwell
            interval: entry.item?.delay ?? 0
            onTriggered: {
              if (area.containsMouse && entry.item)
                ShellManager.runAction(entry.item.action, entry.item.argument);
            }
          }
        }
      }
    }
  }
}
