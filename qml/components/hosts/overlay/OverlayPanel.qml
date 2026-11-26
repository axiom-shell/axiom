pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.hosts.popout
// Imported (though views load by URL) so qs scans what they import and
// the folders whose files see each other (scripts/check_structure.py)
import qs.components.content.Palette // qmllint disable unused-imports
import qs.components.views.BarEditor // qmllint disable unused-imports
import qs.components.views.CustomWidgets // qmllint disable unused-imports
import qs.components.views.Keybinds // qmllint disable unused-imports
import qs.components.views.WindowRules // qmllint disable unused-imports
import qs.components.views.Settings // qmllint disable unused-imports

// The overlay's window on one screen (shell/Overlay): opens and closes the
// sliding box that holds OverlayPages, and closes on Escape or a click outside.
// After a close its pages stay built for `keptFor` (`kept`), so opening
// again slides, with no rebuild. On Top under the chrome (LayerStack: after
// the backdrop, before the backing window), held while closed (a pixel
// drawing nothing); on Overlay over a fullscreen window while shown (its
// slot's layer).
ReservedAreaWindow {
  id: root

  property bool isOpen: false
  // How long it stays kept after closing, in ms
  readonly property int keptFor: 10000
  // Closed, its pages built: from the close until `keptFor` passes, or a
  // fullscreen window shows on its screen
  property bool kept: false
  // Read raw, as the layer service reads it: the keep-warm drop and the reduced
  // latch change in the same deferred batch as LayerManager's pass (the layer
  // service's `hasFullscreen` here would put them a batch later)
  readonly property bool fullscreenNow: CompositorManager.hasFullscreen(root.screen?.name ?? "")
  // Open or closing: its slot's `wanted`
  readonly property bool _wanted: root.isOpen || hideTimer.running
  onFullscreenNowChanged: if (root.fullscreenNow && root.kept) {
    keptTimer.stop();
    root.kept = false;
  }
  // What's open on its screen and would end up under it (a popout keeps
  // its layer while open) closes as it opens
  onIsOpenChanged: if (isOpen)
    PopoutManager.closeOn(root.screen?.name ?? "")
  // This opening draws reduced effects (Overlay.reduceFullscreen): the page's
  // cheaper drawing is decided as it opens; its blur follows the screen live
  // (BlurManager.reduced)
  property ClosedLatch _reduced: ClosedLatch {
    source: OverlayConfig.reduceFullscreen && root.fullscreenNow
    closed: !root._wanted
  }
  readonly property bool reduced: root._reduced.value ?? false
  // Closed, it waits off the edge it slides in from (Overlay.animation),
  // or in place, faded out: also reduced
  readonly property bool fades: OverlayConfig.animation === "fade" || root.reduced
  // The window's height, as last mapped full size (`pageArea.roomHeight`
  // holds it while unmapped)
  readonly property real _slideDistance: pageArea.roomHeight + OverlayConfig.navigatorRoom
  property real slideOffset: isOpen || fades ? 0 : OverlayConfig.animation === "bottom" ? _slideDistance : -_slideDistance
  // The page switcher's on the top edge, not the bottom
  readonly property bool _navigatorTop: OverlayConfig.navigator === "top"

  // Held once the layer rules are in (CompositorManager.surfacesReady), with the
  // chrome it keeps its place among; before that it maps only while open, as a
  // window without a slot (its layer is its row's, LayerStack)
  slotWanted: root._wanted
  slotHeld: CompositorManager.surfacesReady
  // One namespace in every state: a held window whose namespace changed is
  // remade and lands last on its layer (its reduced blur is BlurManager's)
  layerNamespace: "axiom-overlay"
  // Closed (held), a pixel in the corner drawing nothing, taking no input
  // or keys (as ScreenBackdrop)
  anchors {
    right: !slot.idle
    bottom: !slot.idle
  }
  implicitWidth: 1
  implicitHeight: 1
  focusable: !root.steppedAside && !slot.idle
  mask: root.steppedAside || slot.idle ? root._noInput : null
  // The keyboard exclusively while its grab is one the compositor doesn't
  // have (FocusGrab.exclusive)
  WlrLayershell.keyboardFocus: slot.idle || root.steppedAside ? WlrKeyboardFocus.None : grab.exclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

  function open() {
    isOpen = true;
    hideTimer.stop();
    keptTimer.stop();
    // After it's wanted: `built` would drop between and unload the kept pages
    root.kept = false;
    slideContainer.forceActiveFocus();
  }

  function close() {
    // (closing a closed one, kept or not, changes nothing)
    if (!root.isOpen)
      return;
    hideTimer.start();
    isOpen = false;
    // Not while a fullscreen window is up: the pages would keep polling over a game
    root.kept = !root.fullscreenNow;
    if (root.kept)
      keptTimer.restart();
  }

  function toggle() {
    if (isOpen) {
      close();
    } else {
      open();
    }
  }

  // Opens on a page by view type (e.g. "BarEditor", "Themes"); a page
  // that's in a window of its own is gone to there instead
  function openPage(type) {
    if (PageWindowManager.opened(type))
      return;
    root.open();
    ShellManager.showOverlayPage(type);
  }

  Timer {
    id: hideTimer
    interval: Appearance.animSlow
    repeat: false
  }

  Timer {
    id: keptTimer
    interval: root.keptFor
    repeat: false
    onTriggered: root.kept = false
  }

  Connections {
    target: ShellManager
    function onToggleOverlay() {
      if (ShellManager.isTarget(root.screen, OverlayConfig.screen))
        root.toggle();
    }
    function onOpenOverlayPage(type) {
      if (ShellManager.isTarget(root.screen, OverlayConfig.screen))
        root.openPage(type);
    }
    function onCloseOverlay() {
      if (root.isOpen)
        root.close();
    }
  }

  IpcTarget {
    target: "overlay"
    // One handler per target name: the target screen's
    enabled: ShellManager.isTarget(root.screen, OverlayConfig.screen)

    function open() {
      root.open();
    }

    function close() {
      root.close();
    }

    function toggle() {
      root.toggle();
    }

    function page(type: string) {
      root.openPage(type);
    }
  }

  // On every monitor, the instances open and close together
  SurfaceGroup {
    id: group
    kind: "overlay"
    target: OverlayConfig.screen
    screen: root.screen
    window: root
    shown: root.isOpen
    onSyncRequested: shown => shown ? root.open() : root.close()
  }

  FocusGrab {
    id: grab
    // Only while open: a grab held through the close animation would be
    // cleared by any click then, for nothing
    active: root.isOpen && group.ownsGrab && !root.steppedAside
    // This screen's bars and their popouts stay usable while it's open
    // (every screen's, and the other instances, when it's on all of them)
    windows: group.windows.concat(SurfaceManager.grabPartnersFor(group.everywhere ? null : root.screen), SurfaceManager.modalWindows)
    // Nothing closes it as its grab ends (that's also focus leaving, as a
    // polkit prompt closes, or another surface's grab starting over it):
    // only a click on its own empty background (backgroundClicks)
  }

  // Where the compositor blurs only what a window asks: the page's box and
  // the navigator, as they slide and resize
  // (attached only there: attached at all, it claims the window's blur, and
  // Hyprland's layer rules no longer blur it)
  Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
    BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regionsOn(root.screen) && !BlurManager.reducedOn(root.screen) ? boxesBlur : null)
  Region {
    id: boxesBlur

    BoxBlurRegion {
      target: overlayPages.box
      moving: [slideTranslate.y, overlayPages.x, overlayPages.y, overlayPages.width, overlayPages.height]
      opacity: slideContainer.opacity
    }
    BoxBlurRegion {
      target: navigator
      moving: slideTranslate.y
      opacity: slideContainer.opacity
    }
  }

  Item {
    id: slideContainer
    anchors.fill: parent
    // Held and idle it is a pixel: a kept page's changes draw no frames
    visible: !root.slot.idle
    opacity: root.steppedAside || (root.fades && !root.isOpen) ? 0 : 1
    Glide on opacity {
      duration: Appearance.animNormal
    }
    // Keys nothing inside the overlay handled end up here
    focus: true
    Keys.onEscapePressed: event => {
      if (OverlayConfig.closeOnEscape && root.isOpen)
        root.close();
      else
        event.accepted = false;
    }

    transform: Translate {
      id: slideTranslate
      y: root.slideOffset
      Glide on y {
        duration: Appearance.animSlow
      }
    }

    // The empty background (the backdrop shows through it): a click on
    // it, outside the page and the navigator, closes. Declared first, so it
    // only gets clicks nothing over it takes.
    MouseArea {
      id: backgroundClicks
      anchors.fill: parent
      enabled: OverlayConfig.closeOnOutsideClick && root.isOpen
      onClicked: mouse => {
        const inside = item => {
          const p = backgroundClicks.mapToItem(item, mouse.x, mouse.y);
          return item.contains(p);
        };
        if (!inside(overlayPages) && !inside(navigator))
          root.close();
      }
    }

    // Where pages go: everything beside the navigator, so a page never
    // sits under it. Placed by y, not anchors: switching which edge an
    // item anchors to leaves it stretched between both for a moment
    Item {
      id: pageArea
      x: 0
      y: root._navigatorTop ? OverlayConfig.navigatorRoom : 0
      width: parent.width
      height: parent.height - OverlayConfig.navigatorRoom

      // The window has no size while it's idle (closed, and before
      // it's first shown): keep the last full size, so a page built as
      // it opens is built to fit, not built once more at the real size;
      // until the first map, estimate from the screen less its margins
      property real roomWidth: root.screen.width - root.margins.left - root.margins.right
      property real roomHeight: root.screen.height - root.margins.top - root.margins.bottom - OverlayConfig.navigatorRoom
      onWidthChanged: if (!root.slot.idle && pageArea.width > 0)
        pageArea.roomWidth = pageArea.width
      onHeightChanged: if (!root.slot.idle && pageArea.height > 0)
        pageArea.roomHeight = pageArea.height

      OverlayPages {
        id: overlayPages
        anchors.centerIn: parent
        open: root.isOpen
        built: root._wanted || root.kept
        reduced: root.reduced
        screen: root.screen
        maxWidth: pageArea.roomWidth - OverlayConfig.cardSpacing * 2
        maxHeight: pageArea.roomHeight - OverlayConfig.cardSpacing * 2
      }
    }

    // The room a page has before it's shrunk (PageBox.fitScale), in drawn
    // px, and the screen's size: the layouts editor's "fits" line works
    // each page's fit from them (OverlayManager.fitOf)
    QtObject {
      id: area
      readonly property string key: [overlayPages.roomWidth, overlayPages.roomHeight, root.screen?.width, root.screen?.height].join(",")
      onKeyChanged: report()
      Component.onCompleted: report()
      Component.onDestruction: OverlayManager.clearArea(root.screen?.name ?? "")

      function report() {
        OverlayManager.reportArea(root.screen?.name ?? "", overlayPages.roomWidth, overlayPages.roomHeight, root.screen?.width ?? 0, root.screen?.height ?? 0);
      }
    }

    OverlayPageNavigator {
      id: navigator
      anchors.horizontalCenter: parent.horizontalCenter
      y: root._navigatorTop ? Widget.padding * 2 : parent.height - height - Widget.padding * 2
      currentIndex: overlayPages.currentIndex
      pages: overlayPages.pages
      labels: OverlayConfig.navigatorLabels
      maxWidth: pageArea.roomWidth - Widget.padding * 4
      onPrevious: overlayPages.step(-1)
      onNext: overlayPages.step(1)
      onSelect: index => overlayPages.goTo(index)
    }
  }
}
