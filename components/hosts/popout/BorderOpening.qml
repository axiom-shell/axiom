pragma ComponentBehavior: Bound
import QtQuick

import qs.services.ui

// Publishes a stretch of the border's stroke a surface covers
// (`opening`: { screen, edge, start, end }, screen px along the edge, and
// the fillets curving into it at its ends, `startFillet`/`endFillet` as
// SurfaceContext.opening gives them; or null) to ShellManager.setBorderOpening, under this object as its owner,
// and takes it back when this goes. Bindings of an item being torn down
// (a pill on a switch to floating pills) still update after its
// destruction, so nothing is published once it's begun.
QtObject {
  id: root

  property var opening: null
  property bool _gone: false

  onOpeningChanged: {
    if (!root._gone)
      ShellManager.setBorderOpening(root, root.opening);
  }
  Component.onCompleted: ShellManager.setBorderOpening(root, root.opening)
  Component.onDestruction: {
    root._gone = true;
    ShellManager.setBorderOpening(root, null);
  }
}
