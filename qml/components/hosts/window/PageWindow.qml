pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.hosts.overlay

// One overlay tool page in a window of its own (PageWindowManager): a
// header with its name, its unsaved dot and the way back into the
// overlay, and the page below, laid out on a grid of the page's own sizing
// on the screen it opened on (so it never stretches with the window),
// filling the window's height and growing wider to a cap
// (BaseView.windowed), shrunk as a whole only below its least size.
FloatingWindow {
  id: root

  // The page's view type
  required property string type
  // Its entry in Overlay.items (null once it's gone: PageWindowManager
  // then closes the window)
  readonly property var _entry: OverlayConfig.viewEntry(root.type)

  readonly property real _padding: Widget.padding * 2
  readonly property real _headerHeight: Widget.height
  // The size it was left at (read as it opens: keepSize doesn't notify),
  // else room for the page at the size it has in the overlay
  readonly property var _kept: PageWindowManager.sizeOf(root.type)

  title: PageWindowManager.titleOf(root.type)
  color: Style.surfacePage
  implicitWidth: root._kept ? root._kept[0] : Math.round(Math.min((root.screen?.width ?? 1920) * 0.75, pageGrid.drawnUnit * 4.2 + root._padding * 2)) // a stand-in screen until it has one
  implicitHeight: root._kept ? root._kept[1] : Math.round(Math.min((root.screen?.height ?? 1080) * 0.85, pageGrid.drawnUnit * 2 + pageGrid.gap + root._headerHeight + root._padding * 3)) // a stand-in screen until it has one
  minimumSize: Qt.size(Math.round(pageGrid.drawnUnit * 1.6), Math.round(pageGrid.drawnUnit + root._headerHeight + root._padding * 3))

  onWidthChanged: root._keep()
  onHeightChanged: root._keep()
  function _keep() {
    if (root.visible && root.width > 0 && root.height > 0)
      PageWindowManager.keepSize(root.type, root.width, root.height);
  }

  // Closed by the compositor (its close button, a close bind): back into
  // the overlay. Not on destruction, which a QML reload does too
  onClosed: PageWindowManager.closed(root.type)

  Component.onDestruction: PageWindowManager.setActive(root.type, false)

  RowLayout {
    id: header
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
      margins: root._padding
    }
    height: root._headerHeight
    spacing: Widget.spacing

    // Which page window has the keyboard: where a link from it came from
    readonly property bool windowActive: Window.active
    onWindowActiveChanged: PageWindowManager.setActive(root.type, header.windowActive)

    StyledIcon {
      text: OverlayConfig.viewIcon(root.type)
      size: "md"
      tone: "accent"
    }

    StyledLabel {
      text: OverlayConfig.viewLabel({
        "type": root.type
      }, 0)
      role: "title"
    }

    UnsavedDot {
      shown: EditsManager.isUnsaved(root.type)
    }

    Item {
      Layout.fillWidth: true
    }

    StyledIconButton {
      iconText: "pip_exit"
      tooltipText: I18n.tr("Open in the overlay")
      onClicked: PageWindowManager.popIn(root.type, true)
    }
  }

  Item {
    id: body
    anchors {
      top: header.bottom
      left: parent.left
      right: parent.right
      bottom: parent.bottom
      margins: root._padding
    }

    OverlayGrid {
      id: pageGrid
      windowed: true
      screen: root.screen
      sizing: root._entry?.viewConfig.sizing ?? null
      availableWidth: body.width
      // Taller by what a page wider than the window is shrunk by, so the
      // shrunk page still fills the window's height
      availableHeight: body.height / pageBox.fitScale
      drawnZoom: pageBox.contentZoom
    }

    // Drawn at the grid's zoom (the page's own sizing), less only when the
    // window is narrower than the page's least width (its height follows:
    // pageHeight fills it)
    PageBox {
      id: pageBox
      zoom: pageGrid.zoom
      roomWidth: body.width
      fitHeight: false
      width: view.implicitWidth
      height: view.implicitHeight

      Loader {
        id: view
        anchors.centerIn: parent
        active: root._entry !== null
        sourceComponent: OverlayView {
          grid: pageGrid
          viewModel: root._entry
        }
      }
    }
  }
}
