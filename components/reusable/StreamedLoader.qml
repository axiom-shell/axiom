pragma ComponentBehavior: Bound
import QtQuick
import qs.services.core

// A Loader built a moment after it's created, from BuildQueueManager's
// queue, then faded in: a tool page's sections, cards and long lists, so the
// page shows at once and fills in over the next frames instead of building
// everything in the frame it opens. Lay it out as its content (Layout.*
// on it; it takes the item's implicit size) and hand the content its data
// from the loader's own properties (a Repeater's `required` ones go on the
// loader). It only streams while its page is first being built (the
// nearest ancestor's `buildStreaming`, BaseView's) or, with `always`, whenever
// it's made: otherwise, or with `stream: false`, it builds at once, as a
// plain Loader.
Loader {
  id: root

  property bool stream: true
  // Streams whenever it's made, not just while its page is first being
  // built (e.g. the cards of a settings category switched to)
  property bool always: false
  // What a build taking over a frame is logged as (`--debug`)
  property string label: ""
  // Off: not built (or unbuilt) even once its turn has come, as `active`
  property bool wanted: true

  property bool _granted: false
  property bool _streamed: false
  active: root._granted && root.wanted
  opacity: root.item !== null || !root._streamed ? 1 : 0

  Glide on opacity {
    enabled: root._streamed
  }

  // (untyped: qmllint knows only Item's members)
  function _flagOf(host) {
    return host.buildStreaming === true;
  }

  // Whether the page it's on is still being built (no such page: yes)
  function _pageStreaming() {
    for (let item = root.parent; item; item = item.parent) {
      if ("buildStreaming" in item)
        return root._flagOf(item);
    }
    return true;
  }

  Component.onCompleted: {
    if (root.stream && (root.always || root._pageStreaming())) {
      root._streamed = true;
      BuildQueueManager.request(root, () => root._granted = true, root.label);
    } else {
      root._granted = true;
    }
  }
  Component.onDestruction: BuildQueueManager.cancel(root)
}
