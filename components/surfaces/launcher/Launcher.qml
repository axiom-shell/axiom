pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.components.hosts.popout
import qs.components.reusable
import qs.config
import qs.services.core
import qs.services.session
import qs.services.ui

// The search launcher on one screen. LauncherManager builds the rows from
// the text and runs them, LauncherPanel shows them, and this picks the
// host, placed as a dock or OSD is (an edge, a position along it,
// detached or not): detached, a FloatingPopout `distance` across the free
// screen from its edge (FloatPlacement); else an EdgePopout that grows
// out of the border or bar there. Both have the same API
// (show/hide/isOpen/contentItem/window), and only the one in use is
// created.
Scope {
  id: root

  required property ShellScreen screen

  readonly property var host: LauncherConfig.detached ? floatingLoader.item : edgeLoader.item
  readonly property bool shown: root.host?.isOpen ?? false
  // What the panel searches for when it's created (it only exists while
  // the host is open)
  property string _openText: ""

  function open(text) {
    root._openText = text ?? "";
    // Searched first, so instances this opens on other monitors (see
    // SurfaceGroup) show the same text
    LauncherManager.query(root._openText);
    if (!root.host)
      return;
    if (root.host.isOpen)
      root.host.contentItem?.reset(root._openText);
    else
      root.host.show();
  }

  function close() {
    root.host?.hide();
  }

  function toggle() {
    if (root.shown)
      close();
    else
      open("");
  }

  // On every monitor, the instances open and close together
  SurfaceGroup {
    id: group
    kind: "launcher"
    target: LauncherConfig.screen
    screen: root.screen
    window: root.host?.window ?? null
    shown: root.shown
    onSyncRequested: shown => shown ? root.open(LauncherManager.text) : root.close()
  }

  Connections {
    target: ShellManager
    enabled: ShellManager.isTarget(root.screen, LauncherConfig.screen)
    function onToggleAppLauncher() {
      root.toggle();
    }
  }

  // Locking from anywhere closes it, so it isn't still up on unlock
  Connections {
    target: LockManager
    function onLockStarted() {
      root.close();
    }
  }

  IpcTarget {
    target: "appLauncher"
    enabled: ShellManager.isTarget(root.screen, LauncherConfig.screen)

    function toggle(): void {
      root.toggle();
    }
    function open(): void {
      if (!root.shown)
        root.open("");
    }
    function close(): void {
      root.close();
    }
    // Opens with `text` searched, e.g. "/theme " or "="
    function search(text: string): void {
      root.open(text);
    }
  }

  // The dim background, under the bars and border, for either host
  BackdropRequest {
    screen: root.screen
    shown: root.shown && LauncherConfig.showBackdrop
    fillColor: Theme.background
    fillOpacity: LauncherConfig.backdrop
  }

  LazyLoader {
    id: floatingLoader
    active: LauncherConfig.detached

    FloatingPopout {
      id: floating

      // Its centre at `position` along the edge, `distance` across
      readonly property FloatPlacement place: FloatPlacement {
        screen: root.screen
        edge: LauncherConfig.edge
        position: LauncherConfig.position
        distance: LauncherConfig.distance
      }

      screen: root.screen
      xFraction: floating.place.xFraction
      xAlign: floating.place.xAlign
      yFraction: floating.place.yFraction
      yAlign: floating.place.yAlign
      leftMargin: floating.place.leftMargin
      topMargin: floating.place.topMargin
      rightMargin: floating.place.rightMargin
      bottomMargin: floating.place.bottomMargin
      // Resized as results come and go, the box would move
      maxContentHeight: (floating.contentItem as LauncherPanel)?.maxHeight ?? 0
      // The panel's list glides to its rows' height itself
      animateHeight: false
      // Reversed, the search field stays put at the bottom
      growUp: LauncherConfig.reverse
      contentPadding: Appearance.borderWidth
      strokeColor: Theme.border
      closedScale: 0.97
      layerNamespace: "axiom-launcher"
      wantsKeyboardFocus: true
      closeOnClickOutside: true
      grabEnabled: group.ownsGrab
      grabWindows: group.windows.filter(w => w !== floating.window)
      // Closes whatever it covers (PopoutManager), as the attached one does
      claimKey: "launcher:" + (root.screen?.name ?? "")

      content: Component {
        LauncherPanel {
          // Stays open until Esc, a pick or a click elsewhere
          readonly property bool autoDismiss: false
          implicitWidth: Math.min(LauncherConfig.width, root.screen.width - Widget.px(32))
          shown: floating.isOpen
          onCloseRequested: floating.hide()
          Component.onCompleted: reset(root._openText)
        }
      }
    }
  }

  LazyLoader {
    id: edgeLoader
    active: !LauncherConfig.detached

    EdgePopout {
      id: popout
      screen: root.screen
      edge: LauncherConfig.edge
      position: LauncherConfig.position
      triggerEnabled: false
      wantsKeyboardFocus: true
      closeOnClickOutside: true
      grabEnabled: group.ownsGrab
      grabWindows: group.windows.filter(w => w !== popout.window)
      // Resized as results come and go, the window would jump (on a side
      // edge the panel holds its height instead, which runs along it)
      maxContentDepth: popout.vertical ? 0 : (popout.contentItem as LauncherPanel)?.maxHeight ?? 0

      // Closes whatever it covers (PopoutManager), rather than standing
      // over it
      claimKey: "launcher:" + (root.screen?.name ?? "")
      claimKind: "launcher"

      content: Component {
        LauncherPanel {
          // Stays open until Esc, a pick or a click elsewhere
          readonly property bool autoDismiss: false
          implicitWidth: Math.min(LauncherConfig.width, root.screen.width - Widget.px(64))
          holdHeight: popout.vertical
          shown: popout.isOpen
          onCloseRequested: popout.hide()
          Component.onCompleted: reset(root._openText)
        }
      }
    }
  }
}
