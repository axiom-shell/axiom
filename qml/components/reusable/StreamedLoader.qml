pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.core
import qs.components.methods

// A Loader built a moment after it's created, from BuildQueueManager's
// queue, then faded in: a tool page's sections, cards and long lists, so the
// page shows at once and fills in over the next frames instead of building
// everything in the frame it opens. Lay it out as its content (Layout.*
// on it; it takes the item's implicit size) and hand the content its data
// from the loader's own properties (a Repeater's `required` ones go on the
// loader). It only streams while its page is first being built (the
// nearest ancestor's `buildStreaming`, BaseView's) or, with `always`, whenever
// it's made: otherwise, or with `stream: false`, it builds at once, as a
// plain Loader. A streamed item fades in and slides up into place; the
// slide is a Translate (never the loader's own `y`, which its layout or a
// caller owns), and `enterIndex` staggers a row of them.
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
  // >= 0 delays the enter by this many steps (at most 8) after the item
  // is built, so a row of them rises one after another
  property int enterIndex: -1
  // Off: it only fades in, without sliding up (the settings cards and their
  // fields, which sit on a page that slides in itself)
  property bool rise: true
  // Its build goes ahead of every other queued one (the settings sidebar,
  // which otherwise arrives after all the cards)
  property bool buildFirst: false

  // Streamed with `always` and still filling in (until the queue drains):
  // the loaders inside it stream too, so a settings card switched to fills
  // in field by field, its lists' rows included, instead of building them
  // all in the frame the card arrives
  property bool streamsInside: false

  // A relay: the walks of the texts it builds stop here
  readonly property var inkHostAbove: InkHost.find(root.parent)
  readonly property real drawnZoom: TextRender.zoomAt(root.parent)

  property bool _granted: false
  property bool _streamed: false
  // The item has been shown (after its stagger)
  property bool _entered: false
  // The slide's distance left
  property real _enter: 0
  active: root._granted && root.wanted
  opacity: !root._streamed || root._entered ? 1 : 0
  transform: Translate {
    y: Math.round(root._enter)
  }

  Glide on opacity {
    enabled: root._streamed
  }

  onItemChanged: {
    if (root.item === null) {
      root._entered = false;
      root._enter = 0;
    } else if (root._streamed && !root._entered) {
      root._enter = root.rise ? Style.enterOffset : 0;
      riseAnim.restart();
    }
  }

  SequentialAnimation {
    id: riseAnim

    PauseAnimation {
      duration: Appearance.animations && root.enterIndex >= 0 ? Math.min(root.enterIndex, 8) * Style.staggerStep : 0
    }
    ScriptAction {
      script: root._entered = true
    }
    NumberAnimation {
      target: root
      property: "_enter"
      to: 0
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }

  // (untyped: qmllint knows only Item's members)
  function _flagOf(host) {
    return host.buildStreaming === true;
  }

  // Whether the page it's on is still being built (no such page: yes), or
  // a loader around it streaming with `always` is
  function _pageStreaming() {
    for (let item = root.parent; item; item = item.parent) {
      if ((item as StreamedLoader)?.streamsInside)
        return true;
      if ("buildStreaming" in item)
        return root._flagOf(item);
    }
    return true;
  }

  Component.onCompleted: {
    if (root.stream && (root.always || root._pageStreaming())) {
      root._streamed = true;
      root.streamsInside = root.always;
      BuildQueueManager.request(root, () => root._granted = true, root.label, root.buildFirst);
    } else {
      root._granted = true;
    }
  }
  Component.onDestruction: BuildQueueManager.cancel(root)

  Connections {
    target: BuildQueueManager
    enabled: root.streamsInside
    function onPendingChanged() {
      if (BuildQueueManager.pending === 0)
        root.streamsInside = false;
    }
  }
}
