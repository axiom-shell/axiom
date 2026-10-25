pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui

// The layouts editor on an overlay page (OverlayManager's selected view):
// a Custom page's modules, with how they fit each monitor's overlay. A
// tool page has nothing to edit.
// i18n: keys from the schema (view labels)
EditTarget {
  id: root

  readonly property var view: OverlayManager.selectedView()
  readonly property bool isCustom: root.view?.type === "Custom"

  // How the page fits each monitor's overlay
  readonly property var fits: root.isCustom ? OverlayManager.fitOf(root.view) : []
  readonly property var shrunk: root.fits.filter(fit => fit.scale < 0.999)

  editor: OverlayManager.layout
  modules: root.isCustom ? root.view.modules : null
  icon: root.view ? OverlayConfig.pageIcon(root.view) : "dashboard"
  title: root.view ? OverlayConfig.viewLabel(root.view, OverlayManager.selectedViewIndex) : I18n.tr("No pages")
  emptyText: I18n.tr(root.view ? "A tool page: it has no layout to edit. Drag it in the list to reorder it." : "No pages yet: add one with New page.")
  fitText: {
    if (root.fits.length === 0)
      return "";
    if (root.shrunk.length === 0)
      return I18n.tr("Fits {0}", root.fits.map(fit => fit.screen).join(", "));
    return root.shrunk.map(fit => I18n.tr("Shrunk to {0}% on {1}", Math.round(fit.scale * 100), fit.screen)).join(" · ");
  }
  fitWarning: root.shrunk.length > 0
  fitLink: root.shrunk.length > 0 ? {
    "setting": "Overlay.moduleScale"
  } : null
  editable: root.isCustom
  notEditableHint: I18n.tr("Pick one of your pages to add modules to it")
}
