pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components.hosts.window

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

  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  focusable: root.hasCard
  visible: slot.shown
  WlrLayershell.layer: slot.layer
  // Named for the polkit prompt it began as: the layer rules (and their
  // recorded test cases) know it by that name
  readonly property string layerNamespace: "axiom-polkit"
  WlrLayershell.namespace: root.layerNamespace
  LayerSlot {
    id: slot
    window: root
    wanted: root.shown || dim.opacity > 0
  }
  WlrLayershell.keyboardFocus: root.live ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  Component.onCompleted: {
    // A window made while a request shows (a monitor plugged in, a
    // reload): onRequestChanged never ran for its first value
    root.drawn = root.request;
    // Where the compositor blurs only what a window asks: the whole dimmed
    // screen, while backdrops blur (LayerStack.blurBackdrops)
    if (CompositorManager.supports.blurRegion === true)
      BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.backdropRegionsOn(root.screen) ? dim.blur : null);
  }

  ModalScrim {
    id: dim
    shown: root.shown
  }

  // Modal: the dimmed screen takes clicks; one cancels the request unless
  // it says it doesn't, or its card is still settling (a click meant for
  // something else as the prompt came up)
  MouseArea {
    anchors.fill: parent
    onClicked: {
      if (root.request && root.request.outsideCancels && (loader.item as PromptCard)?.settled === true)
        PromptManager.cancel(root.request.id);
    }
  }

  // Every focus grab lets input through to it while it shows, so a prompt
  // over the overlay (the greeter's install, from Settings) closes nothing
  ModalCard {
    id: card
    window: root
    shown: root.shown

    visible: root.hasCard
    anchors.centerIn: parent
    width: Math.min(Widget.textPx(480), root.width - Widget.px(32))
    height: loader.implicitHeight + card.padding * 2

    Loader {
      id: loader
      width: parent.width
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

      Connections {
        target: root
        function onFocusWanted() {
          own.takeFocus();
        }
      }
    }
  }
}
