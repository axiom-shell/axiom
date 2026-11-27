pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.hosts.window

// Each hot corner (HotCorners.items) on the screens its target puts it on:
// a transparent pixel of a window in its corner, on the Overlay layer after
// the overlay's page (its `hot-corner` row; hidden under a fullscreen window,
// so it's quiet there) (LayerSlot), running its action (ShellManager.runAction) once the pointer
// has rested there for its delay, and again only after it left. Keyed by
// id, so editing one corner rebuilds only it.
Scope {
  Variants {
    // Once the layer rules are in (CompositorManager.surfacesReady), so
    // each maps in its place
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
          WlrLayershell.layer: slot.layer
          readonly property string layerNamespace: "axiom-hot-corner"
          WlrLayershell.namespace: corner.layerNamespace
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
                ActionsManager.run(entry.item.action, {
                  "argument": entry.item.argument,
                  "call": entry.item.call,
                  "output": corner.modelData.name
                });
            }
          }
        }
      }
    }
  }
}
