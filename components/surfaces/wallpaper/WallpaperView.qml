pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.services.core

// A wallpaper that changes with a transition (the wallpaper window, the
// lock screen and greeter backdrops): two images, the one shown and the
// one loading the next, drawn through a shader. Once the next has loaded,
// the transition ThemeManager.transition picks plays from the old to it;
// at rest the plain "show" shader draws it.
Item {
  id: root

  // The wallpaper's URL
  required property string source
  // Enlarged by this (>= 1) and slid by shiftX / shiftY (-1 to 1) within
  // what overflows: the workspace parallax
  property real zoom: 1
  property real shiftX: 0
  property real shiftY: 0

  // The image on top, and the one it replaced (what a transition starts
  // from)
  property Image current: null
  property Image previous: null
  // The transition playing: { name, angle, origin, sweep, seed }
  property var _transition: ({
      "name": "show",
      "angle": 0,
      "origin": {
        "x": 0.5,
        "y": 0.5
      },
      "sweep": 0,
      "seed": 0
    })
  // The screen's size, kept while the item is briefly 0 (a screen going
  // away), so the images aren't decoded again meanwhile
  property size _screen: Qt.size(0, 0)

  Binding on _screen {
    when: root.width > 0 && root.height > 0
    value: Qt.size(root.width, root.height)
    restoreMode: Binding.RestoreNone
  }

  onSourceChanged: root._load()
  Component.onCompleted: root._load()

  function _load() {
    // A new wallpaper mid-transition: finish it at once, so the image it
    // started from is free to load into
    if (progress.running) {
      progress.stop();
      root._rest();
    }
    const next = root.current === first ? second : first;
    // Back to the one it held last (dark, light, dark): the same source
    // doesn't load again, so no status change would bring it up
    if (next.source.toString() === root.source && next.status === Image.Ready && root.source !== "")
      Qt.callLater(root._reveal, next);
    else
      next.source = root.source;
  }

  function _reveal(image) {
    if (image === root.current || image.source.toString() !== root.source)
      return;
    root.previous = root.current;
    root.current = image;
    const wanted = ThemeManager.transition;
    const picked = WallpaperTransitions.pick(Appearance.wallpaperTransition, Appearance.wallpaperTransitionPool, wanted.seed, wanted.forced, {
      "direction": Appearance.wallpaperTransitionDirection,
      "position": Appearance.wallpaperTransitionPosition,
      "point": wanted.point ?? null
    });
    // Nothing to move from at the start: the first wallpaper fades in
    // over the background
    const from = root.previous?.status === Image.Ready;
    if (!Appearance.animations || picked.name === "none" || (!from && !wanted.forced && root.previous !== null)) {
      root._rest();
      return;
    }
    root._transition = from ? picked : Object.assign({}, picked, {
      "name": "fade"
    });
    progress.restart();
  }

  function _rest() {
    root._transition = Object.assign({}, root._transition, {
      "name": "show"
    });
    shader.progress = 1;
  }

  function _rect(image) {
    // By its loaded size, not its status: an image decoded again at a new
    // size (the fill, the parallax, the screen) keeps its texture meanwhile
    if (!image || !(image.implicitWidth > 0 && image.implicitHeight > 0))
      return Qt.vector4d(0, 0, 0, 0);
    const r = WallpaperFill.rect(Appearance.wallpaperFill, image.implicitWidth, image.implicitHeight, root._screen.width, root._screen.height, root.zoom, root.shiftX, root.shiftY);
    return Qt.vector4d(r.x, r.y, r.width, r.height);
  }

  // The two images, never drawn themselves: the shader samples them
  component WallpaperImage: Image {
    id: image

    visible: false
    asynchronous: true
    cache: false
    fillMode: WallpaperFill.fillMode(Appearance.wallpaperFill)
    sourceSize: {
      const size = WallpaperFill.decodeSize(Appearance.wallpaperFill, root._screen.width, root._screen.height, root.zoom);
      return size ? Qt.size(size.width, size.height) : undefined;
    }
    onStatusChanged: {
      if (image.status === Image.Ready && image.source.toString() === root.source)
        root._reveal(image);
    }
  }

  WallpaperImage {
    id: first
  }

  WallpaperImage {
    id: second
  }

  ShaderEffect {
    id: shader

    anchors.fill: parent
    visible: root.current !== null
    fragmentShader: Qt.resolvedUrl("shaders/" + root._transition.name + ".frag.qsb")

    property real progress: 1
    property real angle: root._transition.angle
    property real aspect: root._screen.height > 0 ? root._screen.width / root._screen.height : 1
    property vector4d fromRect: root._transition.name === "show" ? Qt.vector4d(0, 0, 0, 0) : root._rect(root.previous)
    property vector4d toRect: root._rect(root.current)
    property color background: Theme.background
    property point origin: Qt.point(root._transition.origin.x, root._transition.origin.y)
    property real sweep: root._transition.sweep
    property real seed: root._transition.seed
    property var fromTex: root.previous ?? root.current
    property var toTex: root.current
  }

  NumberAnimation {
    id: progress

    target: shader
    property: "progress"
    from: 0
    to: 1
    // behaviour timing: the user's transition length (Appearance.wallpaper.transition.duration)
    duration: Appearance.wallpaperTransitionDuration
    easing.type: WallpaperTransitions.easing(Appearance.wallpaperTransitionEasing)
    onFinished: root._rest()
  }
}
