pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.compositor
import qs.components.reusable
import qs.components.hosts.popout
import qs.components.views.Layouts
import qs.services.ui

// The overlay's pages on one screen: a view per Overlay.views entry, the
// current one and its neighbours loaded, sliding between them. Each page
// has its own card grid and PageBox (OverlayPage), from its own sizing.
Item {
  id: root
  // The screen whose card size the pages start from
  property var screen: null
  // The most room a page's box may take; a page bigger than that is
  // shrunk (PageBox.fitScale) so any config fits any screen
  property real maxWidth: 0
  property real maxHeight: 0
  // The drawn px a page may take inside the box's padding
  readonly property real roomWidth: root.maxWidth - OverlayConfig.boxPadding * 2
  readonly property real roomHeight: root.maxHeight - OverlayConfig.boxPadding * 2
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

  // The configured views, then the Layouts page (not in config)
  readonly property int editorIndex: viewsModel.length
  readonly property int pageCount: viewsModel.length + 1
  // What the navigator shows for each page: the views, then Layouts
  readonly property var pages: viewsModel.map(view => ({
        "type": view.viewConfig.type,
        "icon": OverlayConfig.pageIcon(view.viewConfig),
        "label": OverlayConfig.viewLabel(view.viewConfig, view.index),
        "tool": OverlayConfig.isTool(view.viewConfig.type)
      })).concat([
    {
      "type": OverlayConfig.layoutsPage.type,
      "icon": OverlayConfig.layoutsPage.icon,
      "label": I18n.tr(OverlayConfig.layoutsPage.label),
      "tool": true
    }
  ])
  // itemAt() isn't a notifying read: `count` makes this re-evaluate once
  // the Repeater has created its pages (on launch they don't exist yet)
  readonly property OverlayPage currentPage: root.currentIndex >= root.editorIndex ? editorPage : (viewsRepeater.count > root.currentIndex ? (viewsRepeater.itemAt(root.currentIndex) as OverlayPage) : null)

  // A new launch opens on the first page; closing and re-opening keeps the
  // page (this item lives as long as the overlay window). The views
  // rebuild whenever Overlay.views changes, including saves from the
  // overlay editor: stay on Layouts if the user is on it, otherwise keep
  // the index valid. Tracked from real navigation only: while the views
  // are still loading Layouts briefly sits at the start, which isn't the
  // user being on it.
  property bool _onLayouts: false
  onCurrentIndexChanged: {
    root._onLayouts = root.viewsModel.length > 0 && root.currentIndex >= root.editorIndex;
    if (root.open)
      settleTimer.restart();
  }
  onPageCountChanged: {
    if (root._onLayouts)
      root.currentIndex = root.editorIndex;
    else
      root.currentIndex = Math.max(0, Math.min(root.currentIndex, root.editorIndex - 1));
  }

  Connections {
    target: ShellManager
    function onShowOverlayPage(type) {
      const index = type === OverlayConfig.layoutsPage.type ? root.editorIndex : root.viewsModel.findIndex(view => view.viewConfig.type === type || view.viewConfig.name === type);
      if (index < 0)
        return;
      // A link keeps the page it left, for the navigator's way back; any
      // other switch (IPC, a keybind, a module's button) drops it. A link
      // within a page keeps the way back it already has
      // A link from a page window goes back to that window
      const from = root.pages[root.currentIndex]?.type ?? "";
      if (!ShellManager.followingLink)
        ShellManager.setLinkOrigin("");
      else if (ShellManager.linkFromWindow !== "")
        ShellManager.setLinkOrigin("window:" + ShellManager.linkFromWindow);
      else if (root.open && index !== root.currentIndex)
        ShellManager.setLinkOrigin(from);
      root._show(index);
    }
  }

  implicitWidth: (root.currentPage?.drawnWidth ?? 0) + OverlayConfig.boxPadding * 2
  implicitHeight: (root.currentPage?.drawnHeight ?? 0) + OverlayConfig.boxPadding * 2

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

  // The page box's soft shadow (D-26), drawn from the box's size and
  // radius (ShapeShadow; capturing the box would redraw the whole page
  // every frame it changes). Under the box, past its clip; off with the
  // shell's shadow switch and where the compositor's blur would frost it
  ShapeShadow {
    box: contentContainer
    radius: Style.radiusOuter
    active: root.open
    shadowColor: Style.shadowSoft
    look: ({
        "shadow": BarStyle.look.shadow && !(Appearance.blur && BlurManager.shadowsApart),
        "shadowSize": Widget.px(16)
      })
  }

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

    Surface {
      id: mainContentBox
      tone: "page"
      anchors.centerIn: parent
      width: contentContainer.width
      height: contentContainer.height

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
          screen: root.screen
          roomWidth: root.roomWidth
          roomHeight: root.roomHeight
          sizing: viewPage.modelData.viewConfig.sizing
          // A page in a window of its own is built there, not here
          readonly property string type: viewPage.modelData.viewConfig.type
          content: PageWindowManager.isOpen(viewPage.type) ? viewPage._poppedOut : viewPage._view

          readonly property Component _view: Component {
            OverlayView {
              anchors.centerIn: parent
              grid: viewPage.grid
              viewModel: viewPage.modelData
            }
          }

          readonly property Component _poppedOut: Component {
            PoppedOutCard {
              anchors.centerIn: parent
              grid: viewPage.grid
              type: viewPage.type
            }
          }
        }
      }

      OverlayPage {
        id: editorPage
        pageIndex: root.editorIndex
        currentIndex: root.currentIndex
        direction: root.direction
        loaded: root.isLoaded(root.editorIndex)
        screen: root.screen
        roomWidth: root.roomWidth
        roomHeight: root.roomHeight

        Layouts {
          anchors.centerIn: parent
          grid: editorPage.grid
        }
      }
    }
  }
}
