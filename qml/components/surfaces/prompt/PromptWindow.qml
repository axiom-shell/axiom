pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.components.reusable
import qs.config
import qs.services.compositor
import qs.services.ui

// The shared prompt on one screen (PromptManager.current): the whole
// screen dimmed, over the bars, and on the screen PromptManager picked,
// the card: polkit's (PolkitCard) or the request's own (PromptCard).
// It's modal: Escape cancels, and a click outside the card cancels too
// unless the request says otherwise (polkit's: clicks there do nothing).
PanelWindow {
  id: root

  readonly property var request: PromptManager.current
  readonly property bool shown: request !== null
  // The card shows here: the picked screen, else (it's gone) the primary
  readonly property bool hasCard: !!screen && General.screensNamed(PromptManager.screenName)[0] === screen
  readonly property bool live: shown && hasCard
  readonly property int pad: Widget.px(18)

  // The request drawn: the shown one, kept while the card fades out after
  // it ends
  property var drawn: null
  readonly property string _requestId: request?.id ?? ""

  onRequestChanged: {
    if (root.request)
      root.drawn = root.request;
  }
  on_RequestIdChanged: Qt.callLater(root.takeFocus)
  onLiveChanged: Qt.callLater(root.takeFocus)

  // The card takes the keyboard (its first field, or itself)
  signal focusWanted

  function takeFocus() {
    if (root.live)
      root.focusWanted();
  }

  // Every focus grab lets input through to it while it shows, so a prompt
  // over the overlay (the greeter's install, from Settings) closes nothing
  Component.onDestruction: SurfaceManager.unregisterModal(root)

  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  focusable: root.hasCard
  visible: shown || dim.opacity > 0

  WlrLayershell.layer: WlrLayer.Overlay
  // Named for the polkit prompt it began as: the layer rules (and their
  // recorded test cases) know it by that name
  WlrLayershell.namespace: "axiom-polkit"
  WlrLayershell.keyboardFocus: root.live ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  Component.onCompleted: {
    SurfaceManager.registerModal(root);
    // Where the compositor blurs only what a window asks: the whole dimmed
    // screen, while backdrops blur (LayerStack.blurBackdrops)
    // (attached only there: attached at all, it claims the window's blur,
    // and Hyprland's layer rules no longer blur it)
    if (CompositorManager.supports.blurRegion === true)
      BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.backdropRegionsOn(root.screen) ? dimBlur : null);
  }
  BoxBlurRegion {
    id: dimBlur
    target: dim
    opacity: dim.opacity
    alpha: dim.color.a
    threshold: 0.01
  }

  Rectangle {
    id: dim
    anchors.fill: parent
    color: Appearance.darkMode ? Theme.background : Theme.foreground
    opacity: root.shown ? 0.75 : 0

    Glide on opacity {
      duration: Appearance.animNormal
    }
  }

  // Modal: the dimmed screen takes clicks; one cancels the request unless
  // it says it doesn't
  MouseArea {
    anchors.fill: parent
    onClicked: {
      if (root.request && root.request.outsideCancels)
        PromptManager.cancel(root.request.id);
    }
  }

  Rectangle {
    id: card

    visible: root.hasCard
    anchors.centerIn: parent
    width: Math.min(Widget.px(480), root.width - Widget.px(32))
    height: loader.implicitHeight + root.pad * 2
    color: Appearance.fill(Theme.background)
    border.color: Theme.border
    border.width: Appearance.borderWidth
    radius: Appearance.borderRadius

    opacity: root.shown ? 1 : 0
    scale: root.shown ? 1 : 0.97
    Glide on opacity {
      duration: Appearance.animNormal
    }
    Glide on scale {
      duration: Appearance.animNormal
    }

    // A click on the card is the card's, never the outside's
    MouseArea {
      anchors.fill: parent
    }

    Loader {
      id: loader
      x: root.pad
      y: root.pad
      width: card.width - root.pad * 2
      active: root.drawn !== null
      sourceComponent: root.drawn?.content === "polkit" ? polkitCard : promptCard
      onLoaded: Qt.callLater(root.takeFocus)
    }
  }

  Component {
    id: polkitCard

    PolkitCard {
      id: polkit
      live: root.live
      pad: root.pad

      Connections {
        target: root
        function onFocusWanted() {
          polkit.takeFocus();
        }
      }
    }
  }

  Component {
    id: promptCard

    PromptCard {
      id: own
      request: root.drawn
      live: root.live
      pad: root.pad

      Connections {
        target: root
        function onFocusWanted() {
          own.takeFocus();
        }
      }
    }
  }
}
