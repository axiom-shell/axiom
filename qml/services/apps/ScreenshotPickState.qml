pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods
import qs.config
import qs.services.compositor
import qs.services.ui

// The screenshot picker's state while picking, shared by every screen's
// picker so a selection can cross monitors, all in global logical pixels
// (the compositor's layout); each picker draws its own part of
// `selection` (ScreenRegion.local). A drag stays with the picker it
// started on (the compositor keeps sending it the pointer past its edge),
// which feeds it here. Not a singleton: ScreenshotManager holds one as
// `picker`.
QtObject {
  id: root

  // The selection stays on one screen: a region to share (xdph shares one
  // output's region) or to record (wf-recorder records one output's: a
  // region over two fails). Set by ScreenshotManager
  property bool oneScreen: false
  // The screen whose picker has the pointer (where a drag started, while
  // dragging)
  property string pointerScreen: ""
  property bool dragging: false
  property point dragStart: Qt.point(0, 0)
  property point dragEnd: Qt.point(0, 0)
  // The window under the pointer ({ output, x, y, width, height }), or null
  property var hoveredWindow: null
  // The windows on every screen's shown workspaces, topmost first per
  // screen, as global boxes clipped to the screens' bounds; taken as the
  // picker opens (nothing moves while it's up)
  property var windows: []
  // What a release would capture: the drag, else the window under the
  // pointer; null when neither (a click then takes the screen clicked).
  // Kept to the pointer's screen with oneScreen
  readonly property var selection: {
    const sel = root.dragging ? ScreenRegion.between(root.dragStart, root.dragEnd) : root.hoveredWindow;
    if (!sel || !root.oneScreen)
      return sel;
    const screen = root.screenBoxes().find(s => s.name === root.pointerScreen);
    return screen ? ScreenRegion.intersect(sel, screen) : sel;
  }

  // Every screen the picker shows, as { name, x, y, width, height }
  function screenBoxes() {
    return General.outputs.map(s => ({
          "name": s.name,
          "x": s.x,
          "y": s.y,
          "width": s.width,
          "height": s.height
        }));
  }

  // The pointer, from the picker it's on (a global point)
  function hover(screenName, point) {
    if (root.dragging)
      return;
    root.pointerScreen = screenName;
    root.hoveredWindow = ScreenRegion.boxAt(root.windows, point.x, point.y, screenName);
  }

  function press(screenName, point) {
    root.pointerScreen = screenName;
    root.dragStart = point;
    root.dragEnd = point;
  }

  // A drag past a few pixels is a region, not a click
  function dragTo(point) {
    root.dragEnd = point;
    if (!root.dragging && Math.hypot(point.x - root.dragStart.x, point.y - root.dragStart.y) >= 6)
      root.dragging = true;
  }

  // The drag ended: the selection it takes (a copy, global), or null
  function release() {
    const sel = root.selection;
    root.dragging = false;
    return sel ? ScreenRegion.between(Qt.point(sel.x, sel.y), Qt.point(sel.x + sel.width, sel.y + sel.height)) : null;
  }

  // The size `rect` (global) is captured at, in pixels: at the largest
  // scale among the pickers it's on, as screenshot.stitch makes it
  function pixelSize(rect) {
    const on = ScreenRegion.covered(rect, root.screenBoxes()).map(s => s.name);
    const scale = SurfaceManager.captureWindows.filter(w => on.includes(w.screen?.name)).reduce((max, w) => Math.max(max, w.pixelRatio), 0) || 1;
    return Qt.size(Math.round(rect.width * scale), Math.round(rect.height * scale));
  }

  // The picker opened for `request` ({ kind, screen }): nothing selected,
  // the windows as they are, and the window under the pointer highlighted
  // before it moves (the pointer only reports a position to a picker once
  // it does)
  function start(request) {
    root.clear();
    root.pointerScreen = request?.screen ?? "";
    root.windows = request?.kind === "screen" ? [] : root._snapWindows();
    if (root.windows.length === 0)
      return;
    CompositorManager.withCursorPos(pos => {
      if (!pos || root.dragging || root.hoveredWindow !== null)
        return;
      const screen = root.screenBoxes().find(s => ScreenRegion.contains(s, pos.x, pos.y));
      if (screen)
        root.hover(screen.name, pos);
    });
  }

  // The picker closed
  function clear() {
    root.dragging = false;
    root.hoveredWindow = null;
    root.windows = [];
  }

  // The windows `selection` snaps to; none where the compositor doesn't
  // say where windows are
  function _snapWindows() {
    if (CompositorManager.supports.windowGeometry !== true)
      return [];
    const screens = root.screenBoxes();
    if (screens.length === 0)
      return [];
    const left = Math.min(...screens.map(s => s.x));
    const top = Math.min(...screens.map(s => s.y));
    const bounds = {
      "x": left,
      "y": top,
      "width": Math.max(...screens.map(s => s.x + s.width)) - left,
      "height": Math.max(...screens.map(s => s.y + s.height)) - top
    };
    // Fullscreen, then floating, then most recently focused
    const covers = w => w.fullscreen || w.maximized;
    return [].concat(...screens.map(screen => {
      const output = CompositorManager.output(screen.name);
      const shown = [output?.activeWorkspaceId ?? -1, output?.specialWorkspaceId ?? 0].filter(id => id !== -1 && id !== 0);
      return CompositorManager.windows.filter(w => !w.hidden && shown.includes(w.workspaceId)).sort((a, b) => covers(b) - covers(a) || b.floating - a.floating || (a.focusRank ?? 0) - (b.focusRank ?? 0)).map(w => Object.assign({
          "output": screen.name
        }, ScreenRegion.intersect({
          "x": w.x,
          "y": w.y,
          "width": w.w,
          "height": w.h
        }, bounds)));
    })).filter(box => !ScreenRegion.isEmpty(box));
  }
}
