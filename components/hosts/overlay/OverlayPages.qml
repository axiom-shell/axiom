pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.compositor
import qs.components.reusable
import qs.components.views.Layouts
import qs.services.ui

// The overlay's pages on one screen: a view per Overlay.views entry, the
// current one and its neighbours loaded, sliding between them.
Item {
  id: root
  // This screen's card grid (OverlayGrid), handed to every view
  required property OverlayGrid grid
  // The most room a page's box may take; a page bigger than that is
  // shrunk (fitScale) so any config fits any screen
  property real maxWidth: 0
  property real maxHeight: 0
  // Whether the overlay window is showing; pages unload when it isn't
  property bool open: false
  property var viewsConfig: OverlayConfig.views || []
  // Every config change is a new views array, so the pages are keyed by
  // their JSON: a string only notifies when it really changes, and pages
  // aren't rebuilt by edits elsewhere (e.g. each settings change)
  readonly property string _viewsKey: JSON.stringify(viewsConfig)
  property var viewsModel: buildViewsModel(JSON.parse(_viewsKey))
  property int currentIndex: 0
  // Which way the last navigation went (1 forward, -1 back): the side the
  // new page slides in from, so wrapping past the end still slides onward
  property int direction: 1

  // The user's own navigation (the navigator): a link's way back is gone
  function step(by) {
    ShellManager.setLinkOrigin("");
    root.direction = by;
    root.currentIndex = (root.currentIndex + by + root.pageCount) % root.pageCount;
  }

  function goTo(index) {
    ShellManager.setLinkOrigin("");
    root._show(index);
  }

  function _show(index) {
    root.direction = index < root.currentIndex ? -1 : 1;
    root.currentIndex = index;
  }

  // The configured views, then the pages that aren't in config
  readonly property var pinnedPages: OverlayConfig.pinnedPages
  readonly property int editorIndex: viewsModel.length
  readonly property int pageCount: viewsModel.length + pinnedPages.length
  // What the navigator shows for each page: the views, then the pinned ones
  readonly property var pages: viewsModel.map(view => ({
        "type": view.viewConfig.type,
        "icon": OverlayConfig.pageIcon(view.viewConfig),
        "label": OverlayConfig.viewLabel(view.viewConfig, view.index),
        "tool": OverlayConfig.isTool(view.viewConfig.type)
      })).concat(pinnedPages.map(page => ({
        "type": page.type,
        "icon": page.icon,
        "label": I18n.tr(page.label),
        "tool": true
      })))
  // itemAt() isn't a notifying read: `count` makes this re-evaluate once
  // the Repeater has created its pages (on launch they don't exist yet)
  readonly property Item currentPage: root.currentIndex >= root.editorIndex ? editorPage : (viewsRepeater.count > root.currentIndex ? viewsRepeater.itemAt(root.currentIndex) : null)

  // A new launch opens on the first page; closing and re-opening keeps the
  // page (this item lives as long as the overlay window). The views
  // rebuild whenever Overlay.views changes, including saves from the
  // overlay editor: stay on a pinned page if the user is on one, otherwise
  // keep the index valid. Tracked from real navigation only: while the
  // views are still loading the pinned pages briefly sit at the start,
  // which isn't the user being on them.
  // Which pinned page the user is on (index into pinnedPages), or -1
  property int _onPinned: -1
  onCurrentIndexChanged: {
    root._onPinned = root.viewsModel.length > 0 && root.currentIndex >= root.editorIndex ? root.currentIndex - root.editorIndex : -1;
    if (root.open)
      settleTimer.restart();
  }
  onPageCountChanged: {
    if (root._onPinned >= 0)
      root.currentIndex = root.editorIndex + root._onPinned;
    else
      root.currentIndex = Math.max(0, Math.min(root.currentIndex, root.editorIndex - 1));
  }

  Connections {
    target: ShellManager
    function onShowOverlayPage(type) {
      const pinned = root.pinnedPages.findIndex(page => page.type === type);
      const index = pinned >= 0 ? root.editorIndex + pinned : root.viewsModel.findIndex(view => view.viewConfig.type === type || view.viewConfig.name === type);
      if (index < 0)
        return;
      // A link keeps the page it left, for the navigator's way back; any
      // other switch (IPC, a keybind, a module's button) drops it. A link
      // within a page keeps the way back it already has
      const from = root.pages[root.currentIndex]?.type ?? "";
      if (!ShellManager.followingLink)
        ShellManager.setLinkOrigin("");
      else if (root.open && index !== root.currentIndex)
        ShellManager.setLinkOrigin(from);
      root._show(index);
    }
  }

  implicitWidth: currentViewWidth * contentZoom + OverlayConfig.boxPadding * 2
  implicitHeight: currentViewHeight * contentZoom + OverlayConfig.boxPadding * 2

  // Store current view dimensions to avoid binding loops
  property real currentViewWidth: root.currentPage ? root.currentPage.implicitWidth : 0
  property real currentViewHeight: root.currentPage ? root.currentPage.implicitHeight : 0

  // The grid already sizes cards to the screen; this is the last resort
  // for a page that still doesn't fit (many columns, a page more than two
  // cards high). Item.scale doesn't feed back into implicit sizes, so no
  // binding loop.
  readonly property real fitScale: {
    const room = OverlayConfig.boxPadding * 2;
    const width = root.currentViewWidth * root.grid.zoom;
    const height = root.currentViewHeight * root.grid.zoom;
    const scaleW = width > 0 && root.maxWidth > room ? (root.maxWidth - room) / width : 1;
    const scaleH = height > 0 && root.maxHeight > room ? (root.maxHeight - room) / height : 1;
    return Math.min(1, scaleW, scaleH);
  }
  // What the pages, laid out at the grid's unit, are drawn at
  readonly property real contentZoom: root.grid.zoom * root.fitScale
  onFitScaleChanged: console.log(`Overlay page ${root.currentIndex} scaled to ${root.fitScale.toFixed(3)} (card unit ${root.grid.unit})`)
  Connections {
    target: root.grid
    function onDrawnUnitChanged() {
      console.log(`Overlay card unit ${root.grid.unit} drawn at ${root.grid.drawnUnit} (zoom ${root.grid.zoom.toFixed(3)}) for ${root.maxWidth}x${root.maxHeight}`);
    }
  }

  // Only the current page and its neighbours (navigation wraps around) are
  // loaded, and only while the overlay is open, so hidden pages don't keep
  // polling. Neighbours stay loaded so the slide in has something to show.
  // They follow the page the user settled on (`_settled`, a slide after
  // opening or navigating), so opening or switching builds only the page
  // shown, and its neighbours once it has slid in
  property int _settled: -1
  onOpenChanged: {
    root._settled = -1;
    if (root.open) {
      settleTimer.restart();
    } else {
      settleTimer.stop();
      // Closing ends a link's way back too
      ShellManager.setLinkOrigin("");
    }
  }
  Timer {
    id: settleTimer
    interval: Appearance.animSlow
    onTriggered: root._settled = root.currentIndex
  }

  function isLoaded(pageIndex) {
    if (!root.open)
      return false;
    if (pageIndex === root.currentIndex)
      return true;
    if (root._settled < 0)
      return false;
    const distance = Math.abs(pageIndex - root._settled);
    return Math.min(distance, root.pageCount - distance) <= 1;
  }

  // The shown views, the user's own pages first, then the tool pages, each
  // in config order. `index` is the view's place in config.
  // Whether the compositor does what a page type needs (`x-needs`)
  function _supported(type) {
    const needs = OverlayConfig.viewInfo(type)?.needs ?? "";
    return needs === "" || CompositorManager.supports[needs] === true;
  }

  function buildViewsModel(viewConfigArray) {
    const shown = (viewConfigArray || []).map((viewConf, index) => ({
          // views/<type>.qml; unknown types are rejected by schema validation
          "component": Paths.viewUrl(viewConf.type),
          "viewConfig": viewConf,
          "index": index
        })).filter(view => view.viewConfig.visible !== false && root._supported(view.viewConfig.type));
    return shown.filter(view => !OverlayConfig.isTool(view.viewConfig.type)).concat(shown.filter(view => OverlayConfig.isTool(view.viewConfig.type)));
  }

  // The box the pages are drawn in (the overlay's blur region)
  readonly property Item box: mainContentBox

  // The box grows and shrinks about its centre to the page's size as the
  // pages change. Centred, not anchored to the sides, which would override
  // the animated width (and snap the box's edges to the new page's).
  Item {
    id: contentContainer
    anchors.centerIn: parent
    height: root.implicitHeight
    width: root.implicitWidth
    clip: true

    Glide on height {
      duration: Appearance.animNormal
    }

    Glide on width {
      duration: Appearance.animNormal
    }

    Rectangle {
      id: mainContentBox
      anchors.centerIn: parent
      width: contentContainer.width
      height: contentContainer.height
      radius: Appearance.borderRadius
      color: Appearance.fill(Theme.backgroundAlt)
      border.color: Theme.foreground
      border.width: Appearance.borderWidth

      // Laid out at the grid's unit and scaled as a whole, so the box's
      // own border and radius stay crisp. `contentZoom`: what StyledIcon
      // looks for to draw its glyphs for a scaled page
      Item {
        id: viewsContainer
        anchors.centerIn: parent
        width: root.currentViewWidth
        height: root.currentViewHeight
        scale: root.contentZoom
        readonly property real contentZoom: root.contentZoom

        Repeater {
          id: viewsRepeater
          model: root.viewsModel

          OverlayPage {
            id: viewPage
            required property int index
            required property var modelData
            pageIndex: index
            currentIndex: root.currentIndex
            direction: root.direction
            loaded: root.isLoaded(index)

            OverlayView {
              anchors.centerIn: parent
              grid: root.grid
              viewModel: viewPage.modelData
            }
          }
        }

        OverlayPage {
          id: editorPage
          pageIndex: root.editorIndex
          currentIndex: root.currentIndex
          direction: root.direction
          loaded: root.isLoaded(root.editorIndex)

          Layouts {
            anchors.centerIn: parent
            grid: root.grid
          }
        }
      }
    }
  }
}
