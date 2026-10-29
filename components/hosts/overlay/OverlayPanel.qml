pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
// Imported (though views load by URL) so qs scans what they import and
// the folders whose files see each other (scripts/check_structure.py)
import qs.components.content.Palette // qmllint disable unused-imports
import qs.components.views.BarEditor // qmllint disable unused-imports
import qs.components.views.CustomWidgets // qmllint disable unused-imports
import qs.components.views.Keybinds // qmllint disable unused-imports
import qs.components.views.Settings // qmllint disable unused-imports

// The overlay's window on one screen (shell/Overlay): opens and closes the
// sliding box that holds OverlayPages, and closes on Escape or a click outside.
ReservedAreaWindow {
  id: root

  property bool isOpen: false
  // Closed, it waits off the edge it slides in from (Overlay.animation),
  // or in place, faded out
  readonly property bool _fades: OverlayConfig.animation === "fade"
  property real slideOffset: isOpen || _fades ? 0 : OverlayConfig.animation === "bottom" ? height : -height
  // The page switcher's on the top edge, not the bottom
  readonly property bool _navigatorTop: OverlayConfig.navigator === "top"

  visible: false
  // Its layer rule arranges it after docks and draws it over them
  // (see render.LayerRulesLua)
  WlrLayershell.namespace: "axiom-overlay"
  // The keyboard exclusively while its grab is one the compositor doesn't
  // have (FocusGrab.exclusive)
  WlrLayershell.keyboardFocus: root.steppedAside ? WlrKeyboardFocus.None : grab.exclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

  function open() {
    visible = true;
    isOpen = true;
    slideContainer.forceActiveFocus();
  }

  function close() {
    isOpen = false;
    hideTimer.start();
  }

  // When the overlay last closed from a click outside it: a click on a
  // button outside the grab (e.g. another monitor's bar) clears the grab
  // (closing it) before the button toggles, which must not reopen it
  property real _outsideCloseTime: 0

  function toggle() {
    if (!isOpen && Date.now() - _outsideCloseTime < 300)
      return;
    if (isOpen) {
      close();
    } else {
      open();
    }
  }

  // Opens on a page by view type (e.g. "BarEditor", "Themes")
  function openPage(type) {
    root.open();
    ShellManager.showOverlayPage(type);
  }

  Timer {
    id: hideTimer
    interval: Appearance.animSlow
    repeat: false
    onTriggered: {
      root.visible = false;
    }
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
    onCleared: {
      if (root.isOpen && !root.steppedAside && OverlayConfig.closeOnOutsideClick) {
        root._outsideCloseTime = Date.now();
        root.close();
      }
    }
  }

  // Where the compositor blurs only what a window asks: the page's box and
  // the navigator, as they slide and resize
  // (attached only there: attached at all, it claims the window's blur, and
  // Hyprland's layer rules no longer blur it)
  Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
    BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regionsOn(root.screen) ? boxesBlur : null)
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
    opacity: root.steppedAside || (root._fades && !root.isOpen) ? 0 : 1
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
      Behavior on y {
        NumberAnimation {
          duration: Appearance.animSlow
          easing.type: Easing.InOutQuad
        }
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

      // The window has no size while it's unmapped (closed, and before
      // it's first mapped): keep the last mapped size, so a page built as
      // it opens is built to fit, not built once more at the real size;
      // until the first map, estimate from the screen less its margins
      property real roomWidth: root.screen.width - root.margins.left - root.margins.right
      property real roomHeight: root.screen.height - root.margins.top - root.margins.bottom - OverlayConfig.navigatorRoom
      onWidthChanged: if (pageArea.width > 0)
        pageArea.roomWidth = pageArea.width
      onHeightChanged: if (pageArea.height > 0)
        pageArea.roomHeight = pageArea.height

      OverlayPages {
        id: overlayPages
        anchors.centerIn: parent
        open: root.visible
        grid: grid
        maxWidth: pageArea.roomWidth - OverlayConfig.cardSpacing * 2
        maxHeight: pageArea.roomHeight - OverlayConfig.cardSpacing * 2
      }
    }

    // This screen's card size, so that a page two cards high fits the
    // space the pages get (maxWidth/Height: the page area less its
    // margin) inside the box's padding unshrunk
    OverlayGrid {
      id: grid
      screen: root.screen
      availableWidth: overlayPages.maxWidth - OverlayConfig.boxPadding * 2
      availableHeight: overlayPages.maxHeight - OverlayConfig.boxPadding * 2

      readonly property string areaKey: [grid.roomWidth, grid.roomHeight, grid.unit].join(",")
      onAreaKeyChanged: report()
      Component.onCompleted: report()
      Component.onDestruction: OverlayManager.clearArea(root.screen?.name ?? "")

      // The room a page has before it's shrunk (OverlayPages.fitScale), in
      // layout px: the layouts editor's "fits" line reads each screen's
      function report() {
        OverlayManager.reportArea(root.screen?.name ?? "", grid.roomWidth, grid.roomHeight, grid.unit);
      }
    }

    OverlayPageNavigator {
      id: navigator
      anchors.horizontalCenter: parent.horizontalCenter
      y: root._navigatorTop ? Widget.padding * 2 : parent.height - height - Widget.padding * 2
      currentIndex: overlayPages.currentIndex
      pages: overlayPages.pages
      labels: OverlayConfig.navigatorLabels
      maxWidth: slideContainer.width - Widget.padding * 4
      onPrevious: overlayPages.step(-1)
      onNext: overlayPages.step(1)
      onSelect: index => overlayPages.goTo(index)
    }
  }
}
