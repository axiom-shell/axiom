pragma ComponentBehavior: Bound
import QtQuick

// The last non-null `source`: an entry looked up by id (a dock, an OSD)
// reads null for a moment as it's removed, before what's built from it is
// destroyed, which would otherwise be handed null. Null only until first
// found.
QtObject {
  id: root

  property var source: null
  readonly property var value: root.source ?? root._last

  property var _last: null
  onSourceChanged: {
    if (root.source !== null)
      root._last = root.source;
  }
  Component.onCompleted: root._last = root.source
}
