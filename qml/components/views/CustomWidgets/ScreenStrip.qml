pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable

// Custom widgets page, Module tab: the layers being edited. SegmentTabs of
// "Base" and a tab per screen (the first whose condition holds is drawn over
// the base; a bookmark marks one with a sample kept; right-click for its
// menu), then "+", which adds a blank screen and selects it at once.
RowLayout {
  id: root

  // The selected definition's screens
  property var views: []

  // A right click on screen `index`'s tab, at (x, y) in `item`: the host opens the menu
  signal menuRequested(int index, var item, real x, real y)

  readonly property var editor: CustomWidgetsManager.editor

  Layout.fillWidth: true
  spacing: Widget.spacing

  // Tab 0 is the base, tab n + 1 is screen n; the "+" follows the last tab
  SegmentTabs {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    menus: true
    count: root.views.length + 1
    current: root.editor.viewIndex + 1
    labelAt: i => i === 0 ? I18n.tr("Base") : (root.views[i - 1]?.name || root.views[i - 1]?.id || "")
    iconAt: i => i > 0 && root.editor.selected?.samples?.[root.views[i - 1]?.id] !== undefined ? "bookmark" : ""
    tipAt: i => i > 0 ? I18n.tr("Right-click to rename, duplicate, move or remove") : ""
    onPicked: i => root.editor.selectView(i - 1)
    onMenuRequested: (i, item, x, y) => {
      if (i > 0)
        root.menuRequested(i - 1, item, x, y);
    }

    // A blank screen over the base, named "Screen n", its Name focused: it is
    // shown by a Go to action until its condition is set
    SquareIconButton {
      iconText: "add"
      tooltipText: I18n.tr("Add a screen")
      enabled: root.editor.selected !== null
      onClicked: {
        root.editor.addView(I18n.tr("Screen {0}", root.views.length + 1));
        root.editor.focusScreenName = true;
      }
    }
  }
}
