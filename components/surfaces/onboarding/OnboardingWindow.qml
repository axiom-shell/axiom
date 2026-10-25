pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Wayland

import qs.config
import qs.services.session
import qs.components.methods
import qs.components.hosts.overlay
import qs.components.surfaces.onboarding.pages
import qs.components.reusable

// The onboarder (OnboardingManager): one page at a time over the dimmed
// screen, with the step bar where the overlay has its page navigator. It
// sits in the same reserved area as the overlay (ReservedAreaWindow) with the
// same OverlayGrid, so its cards are the size the overlay's will be, and
// the Welcome page's size setting shows on it at once.
ReservedAreaWindow {
  id: root

  WlrLayershell.namespace: "axiom-onboarding"

  // How much the overlay shrinks its first page on this screen (OverlayPages'
  // fitScale): a page wider than the screen shrinks as a whole
  readonly property real overlayFit: {
    const first = OverlayConfig.views.find(view => !OverlayConfig.isTool(view.type));
    return GridPlacement.fitScale(GridPlacement.bounds(first?.layout?.modules), overlayGrid.roomWidth, overlayGrid.roomHeight, OverlayConfig.pageUnit(first, overlayGrid.unit));
  }

  // Esc (or Skip setup) asks first
  property bool confirmingQuit: false

  Item {
    id: content
    anchors.fill: parent
    opacity: root.steppedAside ? 0 : 1
    focus: true
    Keys.onEscapePressed: root.confirmingQuit = !root.confirmingQuit

    // Everything above the step bar, as the overlay's page area
    Item {
      id: pageArea
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
        bottom: stepBar.top
        bottomMargin: Widget.padding * 2
      }

      Loader {
        id: page
        anchors.centerIn: parent
        // Drawn at the overlay's zoom, shrunk by as much as the overlay
        // shrinks its first page, or more if it doesn't fit, so the cards
        // show at the overlay's size. `contentZoom`: see StyledIcon
        scale: overlayGrid.zoom * Math.min(root.overlayFit, (pageArea.width - OverlayConfig.cardSpacing * 2) / Math.max(1, implicitWidth * overlayGrid.zoom), (pageArea.height - OverlayConfig.cardSpacing * 2) / Math.max(1, implicitHeight * overlayGrid.zoom))
        readonly property real contentZoom: scale
        sourceComponent: {
          switch (OnboardingManager.pageId) {
          case "compositor":
            return compositorPage;
          case "monitors":
            return monitorsPage;
          case "apps":
            return appsPage;
          case "workspaces":
            return workspacesPage;
          case "look":
            return lookPage;
          case "integrations":
            return integrationsPage;
          case "checks":
            return checksPage;
          case "finish":
            return finishPage;
          }
          return welcomePage;
        }
        opacity: status === Loader.Ready ? 1 : 0
        Glide on opacity {
          duration: Appearance.animNormal
        }
      }
    }

    // This screen's card size, worked out as the overlay's is
    OverlayGrid {
      id: overlayGrid
      screen: root.screen
      availableWidth: pageArea.width - OverlayConfig.cardSpacing * 2 - OverlayConfig.boxPadding * 2
      availableHeight: pageArea.height - OverlayConfig.cardSpacing * 2 - OverlayConfig.boxPadding * 2
    }

    StepBar {
      id: stepBar
      anchors {
        bottom: parent.bottom
        bottomMargin: Widget.padding * 2
        horizontalCenter: parent.horizontalCenter
      }
      maxWidth: content.width - Widget.padding * 4
      confirmingQuit: root.confirmingQuit
      onQuitRequested: root.confirmingQuit = true
      onQuitCancelled: root.confirmingQuit = false
      onQuitConfirmed: OnboardingManager.close()
    }
  }

  Component {
    id: welcomePage
    WelcomePage {
      grid: overlayGrid
    }
  }
  Component {
    id: compositorPage
    CompositorPage {
      grid: overlayGrid
    }
  }
  Component {
    id: monitorsPage
    MonitorsPage {
      grid: overlayGrid
      screen: root.screen
    }
  }
  Component {
    id: appsPage
    AppsPage {
      grid: overlayGrid
    }
  }
  Component {
    id: workspacesPage
    WorkspacesPage {
      grid: overlayGrid
    }
  }
  Component {
    id: lookPage
    LookPage {
      grid: overlayGrid
      screen: root.screen
    }
  }
  Component {
    id: integrationsPage
    IntegrationsPage {
      grid: overlayGrid
    }
  }
  Component {
    id: checksPage
    ChecksPage {
      grid: overlayGrid
    }
  }
  Component {
    id: finishPage
    FinishPage {
      grid: overlayGrid
    }
  }
}
