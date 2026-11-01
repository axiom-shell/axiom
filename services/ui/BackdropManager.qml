pragma Singleton
import QtQuick

/**
 * The dim backgrounds full-screen surfaces ask for (the overlay, launcher,
 * power menu, workspace overview, onboarding: reusable/BackdropRequest).
 * Each screen has one backdrop window (surfaces/backdrop/ScreenBackdrop,
 * built by shell/Backdrops), showing the request that showed last there. One
 * window rather than one per surface keeps it in its place in the stack
 * where the compositor stacks by map order alone: it stays mapped there
 * (docs/dev/compositor/layer-arrangement.md). Without a native focus
 * grab, the same windows catch the click outside a grabbing surface
 * (FocusGrab, `catching`).
 */
QtObject {
  id: root

  // { owner uid: { screen, shown, slide, fillColor, fillOpacity, since } }
  property var _requests: ({})
  property int _lastUid: 0
  property int _lastShown: 0

  function register() {
    return ++root._lastUid;
  }

  // A request's state, again whenever it changes; null once it's gone
  function update(uid, request) {
    const requests = Object.assign({}, root._requests);
    if (!request) {
      delete requests[uid];
    } else {
      const was = root._requests[uid];
      requests[uid] = Object.assign({}, request, {
        "since": request.shown && !was?.shown ? ++root._lastShown : (was?.since ?? 0)
      });
    }
    root._requests = requests;
  }

  // What the backdrop on `screenName` shows: the request shown there
  // last, or null when none is
  function requestOn(screenName) {
    let best = null;
    for (const uid in root._requests) {
      const r = root._requests[uid];
      if (r.shown && r.screen === screenName && (!best || r.since > best.since))
        best = r;
    }
    return best;
  }

  // --- Catching clicks for a focus grab the compositor doesn't have ---

  // FocusGrabs without a native grab, active now (uids): every screen's
  // backdrop window then covers its screen, transparent, under the
  // grabbing surface, and a click on it ends their grabs. Not while a
  // modal is up (SurfaceManager.modalShown): it covers every screen, so no
  // click needs catching
  property var _catchers: []
  readonly property bool catching: root._catchers.length > 0 && !SurfaceManager.modalShown
  // A click caught while `catching`: on a backdrop (`window` null), or on
  // a bar above it (`window` its window), outside a grab that doesn't let
  // input through to it (FocusGrab)
  signal clickedOutside(var window)

  // Every FocusGrab active now, native grab or not (uids, oldest first)
  property var _grabs: []
  // The newest of them (0 with none): only its surface asks for the
  // keyboard exclusively (FocusGrab.exclusive), and it holds Hyprland's
  // native grab (one at a time: a newer one starting clears an older one
  // with no click, which takes it back once it's the newest again)
  readonly property int newestGrab: root._grabs.length > 0 ? root._grabs[root._grabs.length - 1] : 0

  function grabbing(uid, on) {
    if (root._grabs.includes(uid) !== on)
      root._grabs = root._listed(root._grabs, uid, on);
  }

  function catchClicks(uid, on) {
    if (root._catchers.includes(uid) !== on)
      root._catchers = root._listed(root._catchers, uid, on);
  }

  // `list` with `uid` last, or without it
  function _listed(list, uid, on) {
    const others = list.filter(c => c !== uid);
    return on ? others.concat([uid]) : others;
  }
}
