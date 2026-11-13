pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.components.hosts.popout
import qs.components.reusable
import qs.components.surfaces.osd
import qs.services.compositor
import qs.components.methods

// Every enabled OSD (OSD.osds), each on the screens its `monitors` puts it
// on: an EdgePopout, held off its edge when `detached` (as a dock or edge
// menu can be). A change opens every OSD holding that system, on the target
// screen (the focused one), or on all of them in "all" mode. Hiding is the
// parts' own times (OSDHost's collapse). Keyed by id, so editing an OSD's
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
          // Held off the edge, `distance` across the free screen from it,
          // sliding or fading in
          held: entry.osd.detached
          distance: entry.osd.distance / 100
          fade: entry.osd.animation === "fade"
          triggerEnabled: entry.osd.openOnHover
          overNamespace: "axiom-osd"
          // Closes under a higher popout, and won't open under one
          claimKey: "osd:" + entry.osd.id + ":" + (modelData?.name ?? "")
          claimKind: "osd"
          // The strip spans the OSD's own length along the edge
          triggerLength: (edgeHost.contentItem as OSDHost)?.triggerLength ?? 0
          dismissDelay: entry.osd.timeout
          // Room for every part out at once, as they come and go
          maxContentDepth: (edgeHost.contentItem as OSDHost)?.maxDepth ?? 0
          // The systems inside also report their own changes, so they must
          // exist while the OSD is closed
          keepLoaded: true

          content: Component {
            OSDHost {
              osd: entry.osd
              screen: edgeHost.screen
              // A window rule pauses OSDs on this monitor
              paused: WindowRulesManager.pauseOsdOn.includes(edgeHost.screen?.name ?? "")
              open: edgeHost.isOpen
              gap: edgeHost.contentPadding - Appearance.borderWidth
              edgeVertical: edgeHost.vertical
              edgeAtEnd: edgeHost.edge === ScreenEdge.Bottom || edgeHost.edge === ScreenEdge.Right
              // On its surface or hover strip (not what opened it: nothing)
              pointerIn: edgeHost.keepAlive
              // Until it has slid away, so the highlight stays as it goes
              hostOpen: edgeHost.occupied
              onPoked: force => edgeTriggers.poke(force)
              onCollapse: edgeHost.hide()
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
