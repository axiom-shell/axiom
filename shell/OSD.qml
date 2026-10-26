pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.components.hosts.popout
import qs.components.reusable
import qs.components.surfaces.osd
import qs.components.methods

// Every enabled OSD (OSD.osds), each on the screens its `monitors` puts it
// on: an EdgePopout, held off its edge when `detached` (as a dock or edge
// menu can be). A change opens every OSD holding that bar, on the target
// screen (the focused one), or on all of them in "all" mode. Hiding is the
// host's own hover-aware dismiss timer. Keyed by id, so editing an OSD's
// settings updates it in place instead of rebuilding every OSD.
Scope {
  Variants {
    model: OSDConfig.shownIds

    delegate: Scope {
      id: entry
      required property string modelData
      readonly property var _found: OSDConfig.osdById(modelData)
      // As last found, so its popouts are never handed null as it's removed
      property LastFound _held: LastFound {
        source: entry._found
      }
      readonly property var osd: entry._held.value
      readonly property var screens: entry._found ? General.screensFor(entry._found.screen) : []

      Variants {
        model: entry.screens

        delegate: EdgePopout {
          id: edgeHost
          required property ShellScreen modelData

          screen: modelData
          edge: ScreenEdge.fromConfig(entry.osd.edge)
          position: entry.osd.position / 100
          // Held off the edge, `gap` in from the frame lines there
          held: entry.osd.detached
          gap: entry.osd.gap
          triggerEnabled: entry.osd.openOnHover
          overNamespace: "axiom-osd"
          // Closes under a higher popout, and won't open under one
          claimKey: "osd:" + entry.osd.id + ":" + (modelData?.name ?? "")
          claimKind: "osd"
          // The strip spans the OSD's own length along the edge
          triggerLength: edgeHost.vertical ? (edgeHost.contentItem?.implicitHeight ?? 0) : (edgeHost.contentItem?.implicitWidth ?? 0)
          dismissDelay: entry.osd.timeout
          // The bars inside also report their own changes, so they must
          // exist while the OSD is closed
          keepLoaded: true

          content: Component {
            OSDContent {
              osd: entry.osd
              screenName: edgeHost.screen?.name ?? ""
              edgeVertical: edgeHost.vertical
              onPoked: force => edgeTriggers.poke(force)
            }
          }

          OSDTriggers {
            id: edgeTriggers
            host: edgeHost
            osd: entry.osd
          }
        }
      }
    }
  }
}
