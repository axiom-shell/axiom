pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Wayland

import qs.config
import qs.services.compositor
import qs.services.system
import qs.services.ui
import qs.components.methods
import qs.components.hosts.popout
import qs.components.reusable

// One screen's notification toasts (shell/Notifications builds one per
// screen of NotificationsConfig.screen): an edge, a place along it and a
// gap, as the OSD's and the dock's. Detached they're cards in a window
// over the free area; attached, rows of one box grown out of the border
// or a bar (an EdgePopout). Newest at the stack's start, the rest gliding
// along as toasts come and go; they slide in from and out to one edge
// (ToastMotion.slideEdge) and the stack makes way for popouts open over
// it (PopoutGeometry.makeWay).
Scope {
  id: root

  required property ShellScreen screen
  readonly property string screenName: root.screen?.name ?? ""

  // A toast the user closed here: the host closes it on every screen
  signal userClosed(var notification)

  // The toasts, newest first: { key, notification, uid }. One stays while
  // it leaves, until it's out of sight.
  property var toasts: []
  property int _serial: 0
  // key -> its ToastItem while it's built, as a card and as a row of the
  // attached box (both while the stack switches between them)
  property var _cards: ({})
  property var _rows: ({})
  // key -> its height
  property var _heights: ({})
  // Keys leaving, and where each was as it started to
  property var _leaving: ({})

  readonly property int spacing: Widget.padding
  readonly property int count: root.toasts.length
  readonly property bool showing: root.count > 0

  // Over a fullscreen window nothing else shows: the stack sits on the
  // whole screen, its gaps from the screen's edges
  readonly property bool fullscreen: CompositorManager.hasFullscreen(root.screenName)

  // Detached, or attached but pushed away from its edge by a popout,
  // which it can't stay joined to
  readonly property bool attached: !NotificationsConfig.detached && !root.fullscreen && !(root.grow.across && root.makeWay > 0)
  readonly property var grow: ToastMotion.growth(NotificationsConfig.edge, NotificationsConfig.position)
  readonly property bool vertical: NotificationsConfig.edge === ScreenEdge.Left || NotificationsConfig.edge === ScreenEdge.Right

  // ---- Toasts ----

  function show(notification) {
    if (!ShellManager.showsOn(root.screen, NotificationsConfig.screen))
      return;
    const critical = notification.urgency === NotificationUrgency.Critical;
    if (NotificationsConfig.quietFullscreen && root.fullscreen && !critical)
      return;
    // Make room: the oldest go
    const staying = root.toasts.filter(t => root._leaving[t.key] === undefined);
    staying.slice(NotificationsConfig.maxToasts - 1).forEach(t => root.hide(t.key));
    if (staying.length === 0)
      root._pickSlideEdge();
    root._serial += 1;
    root.toasts = [
      {
        "key": "t" + root._serial,
        "notification": notification,
        "uid": NotificationManager.uidOf(notification)
      }
    ].concat(root.toasts);
  }

  // Hides a toast (it stays in the history)
  function hide(key) {
    if (root._leaving[key] !== undefined)
      return;
    const staying = root.toasts.filter(t => root._leaving[t.key] === undefined);
    const index = staying.findIndex(t => t.key === key);
    if (index < 0)
      return;
    root._leaving = Utils.withEntry(root._leaving, key, root._offsets[key] ?? 0);
    const item = (root.attached ? root._rows : root._cards)[key];
    if (item)
      item.dismiss(index, root.grow);
    else
      root._drop(key);
  }

  // Hides every toast of a notification
  function hideNotification(notification) {
    root.toasts.filter(t => t.notification === notification).forEach(t => root.hide(t.key));
  }

  function _drop(key) {
    root.toasts = root.toasts.filter(t => t.key !== key);
    root._leaving = Utils.withEntry(root._leaving, key, undefined);
    root._heights = Utils.withEntry(root._heights, key, undefined);
  }

  // ---- Layout ----

  // Each staying toast's distance from the stack's start, newest first;
  // a leaving one keeps where it was
  readonly property var _offsets: {
    const staying = root.toasts.filter(t => root._leaving[t.key] === undefined);
    const rows = ToastMotion.rows(staying.map(t => root._heights[t.key] ?? 0), root.attached ? 0 : root.spacing);
    const out = {};
    staying.forEach((t, i) => out[t.key] = rows.offsets[i]);
    for (const key in root._leaving)
      out[key] = root._leaving[key];
    return out;
  }
  readonly property real stackLength: {
    const staying = root.toasts.filter(t => root._leaving[t.key] === undefined);
    return ToastMotion.rows(staying.map(t => root._heights[t.key] ?? 0), root.spacing).length;
  }
  readonly property real _firstHeight: root._heights[root.toasts.find(t => root._leaving[t.key] === undefined)?.key] ?? 0

  // The free area the detached stack sits in (its window's size, on the
  // screen), and its insets there from each side
  readonly property real areaWidth: area.width
  readonly property real areaHeight: area.height
  readonly property var _gaps: ScreenEdgeManager.detachedGaps(root.screen, NotificationsConfig.edge, NotificationsConfig.gap)
  function _inset(side) {
    const edge = NotificationsConfig.edge;
    let gap = root._gaps.end;
    if (side === edge)
      gap = root._gaps.across;
    else if (side === (root.vertical ? ScreenEdge.Top : ScreenEdge.Left))
      gap = root._gaps.start;
    else if (side === ScreenEdge.opposite(edge))
      gap = root._gaps.across;
    if (root.fullscreen)
      return Math.max(0, gap);
    return ScreenEdgeManager.heldInset(root.screen, side, gap);
  }
  readonly property real insetTop: root._inset(ScreenEdge.Top)
  readonly property real insetBottom: root._inset(ScreenEdge.Bottom)
  readonly property real insetLeft: root._inset(ScreenEdge.Left)
  readonly property real insetRight: root._inset(ScreenEdge.Right)

  // The stack's box at rest in its window, makeWay aside:
  // { x, y, width, height }
  readonly property var restRect: {
    const w = NotificationsConfig.width;
    const len = Math.max(root.stackLength, root._firstHeight);
    const p = NotificationsConfig.position;
    switch (NotificationsConfig.edge) {
    case ScreenEdge.Top:
    case ScreenEdge.Bottom:
      {
        const x = root.insetLeft + Math.max(0, root.areaWidth - root.insetLeft - root.insetRight - w) * p;
        const y = NotificationsConfig.edge === ScreenEdge.Top ? root.insetTop : root.areaHeight - root.insetBottom - len;
        return Qt.rect(x, y, w, len);
      }
    default:
      {
        const x = NotificationsConfig.edge === ScreenEdge.Left ? root.insetLeft : root.areaWidth - root.insetRight - w;
        const free = root.areaHeight - root.insetTop - root.insetBottom - root._firstHeight;
        const start = root.grow.sign > 0 ? root.insetTop + Math.max(0, free) * p : root.insetTop + root._firstHeight + Math.max(0, free) * p - len;
        return Qt.rect(x, start, w, len);
      }
    }
  }

  // How far it moves along its growth to clear the popouts showing over
  // it (none while it shows nothing)
  readonly property real makeWay: {
    if (!root.showing)
      return 0;
    const o = area.origin;
    const r = root.restRect;
    const room = root.grow.sign > 0 ? root.areaHeight - root.insetBottom - (r.y + r.height) : r.y - root.insetTop;
    return PopoutGeometry.makeWay(PopoutManager.entries, root.screenName, Qt.rect(o.x + r.x, o.y + r.y, r.width, r.height), "y", root.grow.sign, root.spacing, Math.max(0, room));
  }

  // A toast's place in its window: { x, y } of its top-left
  function placeOf(key, height) {
    const r = root.restRect;
    const off = root._offsets[key] ?? 0;
    const shift = root.makeWay * root.grow.sign;
    if (root.grow.sign > 0)
      return Qt.point(r.x, r.y + off + shift);
    return Qt.point(r.x, r.y + r.height - off - height + shift);
  }

  // The edge toasts slide from, picked while the stack is empty so it
  // stays one for all of them
  property int slideEdge: NotificationsConfig.edge
  function _pickSlideEdge() {
    const r = root.restRect;
    const o = area.origin;
    const h = Math.max(root._firstHeight, Widget.px(80));
    root.slideEdge = ToastMotion.slideEdge({
      "attached": root.attached,
      "edge": NotificationsConfig.edge,
      "rect": Qt.rect(o.x + r.x, o.y + (root.grow.sign > 0 ? r.y : r.y + r.height - h), r.width, h),
      "screenWidth": root.screen?.width ?? 0,
      "screenHeight": root.screen?.height ?? 0,
      "override": NotificationsConfig.motionStyle === "slide" ? NotificationsConfig.motionDirection : "auto"
    });
  }

  // How far a toast at `place` slides to be out of its window's sight
  function hiddenDistance(place, width, height) {
    switch (root.slideEdge) {
    case ScreenEdge.Top:
      return place.y + height;
    case ScreenEdge.Bottom:
      return root.areaHeight - place.y;
    case ScreenEdge.Left:
      return place.x + width;
    default:
      return root.areaWidth - place.x;
    }
  }

  // Whether a showing toast offers a reply: its window takes the keyboard
  // when clicked
  readonly property bool replyable: root.toasts.some(t => t.notification?.hasInlineReply ?? false)

  // ---- The detached window ----

  // The free area: anchored to every side, inside what the bars, border
  // and other panels reserve (the whole screen over a fullscreen window).
  // Its input mask is the toasts' box, so it takes no clicks elsewhere.
  PanelWindow {
    id: area
    screen: root.screen
    // Always mapped: it lends NotificationManager its image host
    visible: true
    color: "transparent"
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "axiom-notifications"
    WlrLayershell.keyboardFocus: root.replyable && !root.attached ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: root.fullscreen ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: 0
    focusable: false

    readonly property point origin: placeOnScreen.placed
    LayerOrigin {
      id: placeOnScreen
      window: area
      namespace: "axiom-notifications"
      layer: WlrLayer.Overlay
    }

    mask: Region {
      item: root.attached || !root.showing ? null : bounds
    }

    // Every toast's box, for the input mask
    Item {
      id: bounds
      readonly property var _boxes: root.toasts.map(t => root._cards[t.key]).filter(i => i && i.visible)
      readonly property bool _any: bounds._boxes.length > 0
      x: bounds._any ? Math.min(...bounds._boxes.map(i => i.x)) : 0
      y: bounds._any ? Math.min(...bounds._boxes.map(i => i.y)) : 0
      width: bounds._any ? Math.max(...bounds._boxes.map(i => i.x + i.width)) - x : 0
      height: bounds._any ? Math.max(...bounds._boxes.map(i => i.y + i.height)) - y : 0
    }

    // Where NotificationManager renders images to cache them: grabbing
    // needs an item in a window. The first stack lends it; another takes
    // over if that one goes.
    Item {
      id: imageHost
      x: 1
    }

    // Detached, each toast a card at its place, its fill drawn by the
    // blur window while that backs it
    Repeater {
      model: ScriptModel {
        values: root.attached ? [] : root.toasts
        objectProp: "key"
      }

      ToastItem {
        id: toastCard
        required property var modelData
        readonly property string key: toastCard.modelData.key
        readonly property point place: root.placeOf(toastCard.key, toastCard.height)

        notification: toastCard.modelData.notification
        uid: toastCard.modelData.uid
        slideEdge: root.slideEdge
        motionStyle: NotificationsConfig.motionStyle
        hiddenDistance: root.hiddenDistance(toastCard.place, toastCard.width, toastCard.height)
        width: implicitWidth
        height: implicitHeight
        visible: !SurfaceManager.captureFrozen
        screenName: root.screenName
        backed: BlurManager.backsOn(root.screen, true) && placeOnScreen.settled

        x: toastCard.place.x
        y: toastCard.place.y
        // Glides as the stack reflows; not on arrival, which slides it in
        property bool _placed: false
        Glide on y {
          enabled: toastCard._placed
          duration: Appearance.animNormal
        }

        Component.onCompleted: {
          root._cards = Utils.withEntry(root._cards, toastCard.key, toastCard);
          root._heights = Utils.withEntry(root._heights, toastCard.key, toastCard.height);
          Qt.callLater(() => toastCard._placed = true);
        }
        Component.onDestruction: {
          if (root._cards[toastCard.key] === toastCard)
            root._cards = Utils.withEntry(root._cards, toastCard.key, undefined);
        }
        onHeightChanged: root._heights = Utils.withEntry(root._heights, toastCard.key, toastCard.height)
        onFinished: root._drop(toastCard.key)
        onTimedOut: root.hide(toastCard.key)
        onUserClosed: root.userClosed(toastCard.notification)

        BlurShape {
          source: toastCard.box
          kind: "rect"
          screen: root.screenName
          x: area.origin.x + toastCard.x + toastCard.shiftX
          y: area.origin.y + toastCard.y + toastCard.shiftY
          color: Qt.alpha(Appearance.fill(Theme.background), Appearance.fill(Theme.background).a * toastCard.opacity)
          overlayLayer: true
          shown: toastCard.backed && toastCard.visible && !toastCard.gone
          clipRect: Qt.rect(area.origin.x, area.origin.y, area.width, area.height)
        }
      }
    }
  }

  Component.onCompleted: {
    if (!NotificationManager.imageHost)
      NotificationManager.imageHost = imageHost;
  }
  Component.onDestruction: {
    if (NotificationManager.imageHost === imageHost)
      NotificationManager.imageHost = null;
  }
  Connections {
    target: NotificationManager
    function onImageHostChanged() {
      if (!NotificationManager.imageHost)
        NotificationManager.imageHost = imageHost;
    }
  }

  // ---- Attached: one box grown out of the edge ----

  EdgePopout {
    id: box
    screen: root.screen
    edge: NotificationsConfig.edge
    position: NotificationsConfig.position
    // Along a side edge it makes way by moving along it
    positionOffset: root.vertical ? root.makeWay * root.grow.sign : 0
    triggerEnabled: false
    claimKey: ""
    keyboardOnDemand: root.replyable
    // Room for a full stack across a top or bottom edge, so the window
    // never grows while it shows
    maxContentDepth: root.vertical ? NotificationsConfig.width : Widget.px(260) * NotificationsConfig.maxToasts

    content: Component {
      Item {
        id: rows
        // Toasts stay until they time out or are closed, hovered or not
        readonly property bool autoDismiss: false
        implicitWidth: NotificationsConfig.width
        implicitHeight: root.attachedLength
        clip: true

        // Each toast a row of the box, with a divider before all but the
        // first; a leaving one collapses as it slides toward the edge
        Repeater {
          model: ScriptModel {
            values: root.attached || box.occupied ? root.toasts : []
            objectProp: "key"
          }

          Item {
            id: row
            width: rows.width
            required property var modelData
            required property int index
            readonly property string key: row.modelData.key
            // Newest at the edge: first on a top edge or growing down, last else
            readonly property bool fromEnd: root.grow.sign < 0
            readonly property bool leaving: toast.leaving

            // Grows in from nothing and collapses as it leaves: the box's
            // length is the rows', and each row's place follows the heights
            // before it, so the box and the rows move as one
            property bool _born: false
            height: row._born && !row.leaving ? toast.implicitHeight : 0
            clip: true
            Glide on height {
              duration: Appearance.animNormal
            }
            onHeightChanged: root._rowHeights = Utils.withEntry(root._rowHeights, row.key, row.height)
            Component.onCompleted: {
              root._rowHeights = Utils.withEntry(root._rowHeights, row.key, row.height);
              Qt.callLater(() => row._born = true);
            }

            y: {
              void root._rowHeights;
              const before = root.toasts.slice(0, row.index).reduce((sum, t) => sum + (root._rowHeights[t.key] ?? 0), 0);
              return row.fromEnd ? root.attachedLength - before - row.height : before;
            }

            Rectangle {
              visible: row.index > 0
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: Widget.padding
              y: row.fromEnd ? parent.height - height : 0
              height: 1
              color: Qt.alpha(Theme.foreground, 0.25)
            }

            ToastItem {
              id: toast
              width: row.width
              height: implicitHeight
              card: false
              notification: row.modelData.notification
              uid: row.modelData.uid
              slideEdge: root.slideEdge
              motionStyle: NotificationsConfig.motionStyle
              // Out of the row's clip
              hiddenDistance: root.slideEdge === ScreenEdge.Left || root.slideEdge === ScreenEdge.Right ? row.width : toast.implicitHeight
              screenName: root.screenName

              Component.onCompleted: {
                root._rows = Utils.withEntry(root._rows, row.key, toast);
                root._heights = Utils.withEntry(root._heights, row.key, toast.implicitHeight);
              }
              onImplicitHeightChanged: root._heights = Utils.withEntry(root._heights, row.key, toast.implicitHeight)
              // (a row built again for the same toast, as the box comes
              // back, has taken its place by now)
              Component.onDestruction: {
                if (root._rows[row.key] !== toast)
                  return;
                root._rows = Utils.withEntry(root._rows, row.key, undefined);
                root._rowHeights = Utils.withEntry(root._rowHeights, row.key, undefined);
              }
              onFinished: root._drop(row.key)
              onTimedOut: root.hide(row.key)
              onUserClosed: root.userClosed(toast.notification)
            }
          }
        }
      }
    }
  }
  readonly property bool _attachedShowing: root.attached && root.toasts.some(t => root._leaving[t.key] === undefined)
  on_AttachedShowingChanged: {
    if (root._attachedShowing)
      box.show();
    else
      box.hide();
  }
  // The rows' length, a leaving one's as it collapses
  property var _rowHeights: ({})
  readonly property real attachedLength: Object.keys(root._rowHeights).reduce((sum, k) => sum + root._rowHeights[k], 0)
}
