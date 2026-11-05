pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.components.hosts.popout
import qs.components.methods
import qs.components.reusable
import qs.config
import qs.services.core
import qs.services.session
import qs.services.ui

// The search launcher on one screen. LauncherManager builds the rows from
// the text and runs them, LauncherPanel shows them, and this places them
// in an EdgePopout as every detached surface is placed (an edge, a
// position along it, detached or not): detached, held `distance` across
// the free screen from its edge, sliding or fading in; else growing out of
// the border or bar there.
Scope {
  id: root

  required property ShellScreen screen

  readonly property bool shown: popout.isOpen
  // What the panel searches for when it's created (it only exists while
  // the host is open)
  property string _openText: ""

  function open(text) {
    root._openText = text ?? "";
    // Searched first, so instances this opens on other monitors (see
    // SurfaceGroup) show the same text
    LauncherManager.query(root._openText);
    if (popout.isOpen)
      (popout.contentItem as LauncherPanel)?.reset(root._openText);
    else
      popout.show();
  }

  function close() {
    popout.hide();
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
    window: popout.window
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
    // The clipboard history, emoji and calculator rows (keybind actions)
    function clipboard(): void {
      root.open(":");
    }
    function emoji(): void {
      root.open(";");
    }
    function calculator(): void {
      root.open("=");
    }
  }

  // The dim background, under the bars and border
  BackdropRequest {
    screen: root.screen
    shown: root.shown && LauncherConfig.showBackdrop
    fillColor: Theme.background
    fillOpacity: LauncherConfig.backdrop
  }

  EdgePopout {
    id: popout
    screen: root.screen
    edge: LauncherConfig.edge
    position: LauncherConfig.position
    held: LauncherConfig.detached
    distance: LauncherConfig.distance
    fade: LauncherConfig.fade
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
        // On a side edge the panel runs along it; on the top or bottom
        // edge, the box grows from that edge, so a search field at its
        // other end (reversed under the top edge, not reversed over the
        // bottom one) stays put
        holdHeight: popout.vertical || LauncherConfig.reverse === (popout.edge === ScreenEdge.Top)
        shown: popout.isOpen
        onCloseRequested: popout.hide()
        Component.onCompleted: reset(root._openText)
      }
    }
  }
}
