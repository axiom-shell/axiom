pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A popout switching to another payload in place (PopoutWrapperBase's
// canSwitchTo/prepareSwitch: BarPopouts, SubPopout): the content
// switched away from, as a still the host places where that content was
// (from `held`), fading out over the new. From the switch until the new
// content is ready (`holding`), the host keeps its window up and its box as
// it was (`held`: what `snapshot` returned as the switch began), and hides
// the new content, which then fades in by `contentOpacity`. Asked again
// mid-switch, the latest payload wins.
// A host that also gives it `occupied` (BarPopouts) gets `showing` (open
// with something to show: ready content, or a switch held) and `settled`
// (set a tick after it first shows, so the box opens at its size and only
// animates after), and the still ends itself as the host closes.
Image {
  id: root

  // The host's content is ready to show
  required property bool contentReady
  // A hook: what the host keeps of its box as a switch begins
  property var snapshot: () => null

  readonly property bool switching: _switching
  readonly property bool holding: _switching && !contentReady
  readonly property var held: _held
  readonly property real contentOpacity: _contentOpacity

  // The host is open
  property bool occupied: false
  readonly property bool showing: occupied && (contentReady || _switching)
  readonly property bool settled: _settled
  property bool _settled: false
  function _settle() {
    root._settled = root.showing;
  }
  onShowingChanged: {
    if (!root.showing)
      root._settled = false;
    else
      Qt.callLater(root._settle);
  }
  onOccupiedChanged: {
    if (!root.occupied)
      root.end();
  }

  property bool _grabbing: false
  // Bumped by end(), so a grab still in flight when the host closed (or
  // one whose window hid before it rendered) is dropped, not applied
  property int _generation: 0
  property bool _switching: false
  property var _held: null
  property real _contentOpacity: 1
  // Keeps the grab's image alive while shown
  property var _grab: null

  // The host's prepareSwitch: `item` is the content shown. Without
  // animations, or mid-switch, there's no still to take.
  function prepare(item, done) {
    if (root._grabbing)
      return;
    if (root._switching || !item || !Appearance.animations) {
      root._swap(done);
      return;
    }
    const dpr = Screen.devicePixelRatio;
    const generation = root._generation;
    root._grabbing = item.grabToImage(result => {
      if (generation !== root._generation)
        return;
      root._grabbing = false;
      // A switch still fading gives way to this one
      fade.stop();
      root._grab = result;
      root.source = result.url;
      root.width = item.width;
      root.height = item.height;
      root.opacity = 1;
      root._swap(done);
    }, Qt.size(Math.ceil(item.width * dpr), Math.ceil(item.height * dpr)));
    if (!root._grabbing)
      root._swap(done);
  }

  // The host closed: nothing left to switch
  function end() {
    root._generation++;
    root._grabbing = false;
    fade.stop();
    root._switching = false;
    root._contentOpacity = 1;
    root._release();
  }

  function _swap(done) {
    fade.stop();
    if (!root._switching)
      root._held = root.snapshot();
    root._switching = true;
    root._contentOpacity = 0;
    done();
  }

  function _release() {
    root.opacity = 0;
    root.source = "";
    root._grab = null;
  }

  // The new content is in: it fades in as the still fades out
  onContentReadyChanged: {
    if (root.contentReady && root._switching) {
      root._switching = false;
      fade.restart();
    }
  }

  visible: opacity > 0
  opacity: 0
  cache: false

  ParallelAnimation {
    id: fade
    onFinished: root._release()
    NumberAnimation {
      target: root
      property: "opacity"
      to: 0
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
    NumberAnimation {
      target: root
      property: "_contentOpacity"
      to: 1
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
  }
}
