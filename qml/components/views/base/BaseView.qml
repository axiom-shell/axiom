pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.hosts.overlay

// The base of every overlay page (views/<type>.qml): its grid and
// viewConfig, and the page sizes hand-built pages lay out with.
Item {
  id: root
  // This screen's card grid (OverlayGrid): size cards and panels from it
  property OverlayGrid grid
  // This view's entry in Overlay.views
  property var viewConfig

  // Hand-built pages are two cards tall; one that's a single card is this
  // wide, and an editor's side panel (the lists) is `sideWidth`
  readonly property real pageHeight: root.grid ? root.grid.span(8) : 0
  readonly property real cardPageWidth: root.grid ? root.grid.unit * 2.6 + OverlayConfig.cardSpacing : 0
  readonly property real sideWidth: root.grid ? root.grid.unit * 0.8 : 0
  // An editor's main area beside its side panel: as wide as the page
  // allows, within reason
  readonly property real editorWidth: root.grid ? Math.max(root.grid.unit * 1.8, Math.min(root.grid.unit * 2.8, root.grid.roomWidth - root.sideWidth - OverlayConfig.cardSpacing * 3)) : 0
  default property alias content: rowLayout.data

  // While the page is first being built: its StreamedLoaders queue their
  // builds (BuildQueueManager) and fade in. Once the queue has drained,
  // loaders made later (a search narrowing a list, a tab switch) build at
  // once, as the page is already shown
  property bool buildStreaming: true
  Connections {
    target: BuildQueueManager
    enabled: root.buildStreaming
    function onPendingChanged() {
      if (BuildQueueManager.pending === 0)
        root.buildStreaming = false;
    }
  }
  // A page queuing nothing is done at once
  Component.onCompleted: Qt.callLater(() => {
    if (BuildQueueManager.pending === 0)
      root.buildStreaming = false;
  })

  implicitWidth: rowLayout.implicitWidth
  implicitHeight: rowLayout.implicitHeight

  RowLayout {
    id: rowLayout
    spacing: OverlayConfig.cardSpacing
  }
}
