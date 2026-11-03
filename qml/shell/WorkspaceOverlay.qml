pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.config
import qs.components.reusable
import qs.components.surfaces.workspaces

// The workspace overview: the hovered monitor's workspace board
// (WorkspacesConfig's layout) with its windows, full screen. Drag a window to move it (onto a side of another
// window), right-drag to resize, middle-click to close. Where the
// compositor has an overview of its own and WorkspaceOverlay's
// compositorOverview is on, everything that opens this opens that instead.
Scope {
  id: root
  objectName: "workspaceOverlay"

  property bool overlayVisible: false
  // Screen it opens on: the one under the cursor, fixed when it opens
  property string openScreen: ""
  // The compositor's own overview stands in for this one
  readonly property bool useCompositor: CompositorManager.supports.overview === true && WorkspaceOverlayConfig.compositorOverview

  function open() {
    if (root.useCompositor)
      CompositorManager.compositorOverview("open");
    if (root.useCompositor || root.overlayVisible)
      return;
    CompositorManager.withHoveredScreen(name => {
      root.openScreen = name;
      root.overlayVisible = true;
      CompositorManager.refresh();
    });
  }

  function toggle() {
    if (root.useCompositor)
      CompositorManager.compositorOverview("toggle");
    else if (root.overlayVisible)
      root.overlayVisible = false;
    else
      root.open();
  }

  Connections {
    target: ShellManager
    function onToggleWorkspaceOverlay() {
      root.toggle();
    }
  }

  IpcTarget {
    target: "workspaceOverlay"

    function toggle(): void {
      root.toggle();
    }

    function open(): void {
      root.open();
    }

    function hide(): void {
      if (root.useCompositor)
        CompositorManager.compositorOverview("close");
      root.overlayVisible = false;
    }
  }

  // On every monitor, whatever General > Monitors says: it opens on the
  // hovered one
  Variants {
    model: General.outputs

    delegate: PanelWindow {
      id: overlayWindow
      required property var modelData

      // The dim background, under the bars and border
      BackdropRequest {
        screen: overlayWindow.modelData
        shown: overlayWindow.shown
        fillColor: Theme.base00
        fillOpacity: WorkspaceOverlayConfig.backdrop
      }

      readonly property bool shown: root.overlayVisible && overlayWindow.modelData.name === root.openScreen
      // Room the controls hint takes under the grid
      readonly property real hintSpace: hint.visible ? hint.height + Widget.spacing : 0

      screen: overlayWindow.modelData
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }
      // Over everything, so window coordinates are the monitor's (the
      // cursor goes back to them after a drop)
      exclusionMode: ExclusionMode.Ignore
      visible: overlayWindow.shown || content.opacity > 0
      color: "transparent"

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "axiom-workspaces"
      // OnDemand, not Exclusive: an exclusive layer makes Hyprland refuse
      // focus to every window, so focusing one (a click, a drop's target)
      // would only switch the workspace, and closing would refocus the old
      // window and switch back. The focus grab keeps the keyboard here.
      WlrLayershell.keyboardFocus: overlayWindow.shown ? (grab.exclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand) : WlrKeyboardFocus.None

      FocusGrab {
        id: grab
        // Off for a moment to take the grab back after a drop moved focus
        property bool rearming: false
        active: overlayWindow.shown && !grab.rearming
        windows: [overlayWindow].concat(SurfaceManager.modalWindows)
        onCleared: {
          if (overview.recentAction()) {
            grab.rearming = true;
            Qt.callLater(() => grab.rearming = false);
          } else {
            root.overlayVisible = false;
          }
        }
      }

      // Where the compositor blurs only what a window asks: the overview's
      // panel
      // (attached only there: attached at all, it claims the window's blur, and
      // Hyprland's layer rules no longer blur it)
      Component.onCompleted: if (CompositorManager.supports.blurRegion === true)
        BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regionsOn(overlayWindow.modelData) ? overviewBlur : null)
      BoxBlurRegion {
        id: overviewBlur
        target: overview
        opacity: content.opacity
      }

      Item {
        id: content
        anchors.fill: parent
        opacity: overlayWindow.shown ? 1 : 0
        focus: overlayWindow.shown

        Glide on opacity {
          duration: Appearance.animNormal
        }

        Keys.onEscapePressed: {
          if (!overview.cancelInteraction())
            root.overlayVisible = false;
        }

        // The empty background (the backdrop shows through it): a click
        // on it closes
        MouseArea {
          anchors.fill: parent
          onClicked: root.overlayVisible = false
        }

        OverviewGrid {
          id: overview
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -overlayWindow.hintSpace / 2
          screen: overlayWindow.modelData
          // Through the fade out too, or the previews drop their frames
          // (and show the app icon) while still on screen
          active: overlayWindow.visible
          availableWidth: parent.width * WorkspaceOverlayConfig.size
          availableHeight: parent.height * WorkspaceOverlayConfig.size - overlayWindow.hintSpace

          onCloseRequested: root.overlayVisible = false
        }

        StyledText {
          id: hint
          visible: WorkspaceOverlayConfig.showHint
          anchors.top: overview.bottom
          anchors.topMargin: Widget.spacing
          anchors.horizontalCenter: parent.horizontalCenter
          text: I18n.tr("Click to go · Drag to move · Right-drag to resize · Middle-click to close")
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-1)
        }
      }
    }
  }
}
