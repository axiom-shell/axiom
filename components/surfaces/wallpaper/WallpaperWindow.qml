pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.core

// A screen's wallpaper, crossfading to a new one once it has loaded
PanelWindow {
  id: root

  readonly property string source: ThemeManager.wallpaperFor(screen?.name ?? "")
  // The image shown on top; the other one loads the next wallpaper
  property Image current: first

  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.namespace: "axiom-wallpaper"
  exclusionMode: ExclusionMode.Ignore
  color: Theme.background
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  onSourceChanged: {
    const next = current === first ? second : first;
    // Back to the one it held last (dark, light, dark): the same source
    // doesn't load again, so no status change would bring it up
    if (next.source.toString() === source && next.status === Image.Ready)
      next.reveal();
    else
      next.source = source;
  }
  Component.onCompleted: first.source = source

  // The new image fades in over the old, which stays opaque underneath
  component WallpaperImage: Image {
    id: image

    required property ShellScreen screenInfo
    // The wallpaper wanted on screen, and whether this image shows it
    required property string wanted
    required property bool shown
    signal ready

    function reveal() {
      image.ready();
      fadeIn.restart();
    }

    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    // The screen's size, kept while Hyprland briefly has no output (the
    // screen is null then), so the image isn't decoded again meanwhile
    Binding on sourceSize {
      when: image.screenInfo !== null
      value: Qt.size(image.screenInfo?.width ?? 0, image.screenInfo?.height ?? 0)
      restoreMode: Binding.RestoreNone
    }
    z: image.shown ? 1 : 0
    onStatusChanged: {
      if (image.status !== Image.Ready || image.source.toString() !== image.wanted || image.shown)
        return;
      image.reveal();
    }

    NumberAnimation {
      id: fadeIn
      target: image
      property: "opacity"
      from: 0
      to: 1
      duration: Appearance.animSlow
      easing.type: Appearance.easing
    }
  }

  WallpaperImage {
    id: first
    screenInfo: root.screen
    wanted: root.source
    shown: root.current === first
    onReady: root.current = first
  }

  WallpaperImage {
    id: second
    screenInfo: root.screen
    wanted: root.source
    shown: root.current === second
    onReady: root.current = second
  }
}
