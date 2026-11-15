pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable

// Custom widgets page, Module tab: the layers being edited. "Base" and a
// button per screen (the first whose condition holds is drawn over the base;
// a bookmark marks one with a sample kept; right-click for its menu), then
// "+", which adds a blank screen and selects it at once. A Flow ignores
// Layout.*, so every item is Widget.height tall with the same radius
// (SegmentButton and SquareIconButton both).
Flow {
  id: root

  // The selected definition's screens
  property var views: []

  // A right click on screen `index`'s button, at (x, y) in `item`: the host opens the menu
  signal menuRequested(int index, var item, real x, real y)

  readonly property var editor: CustomWidgetsManager.editor

  Layout.fillWidth: true
  spacing: Widget.spacing

  SegmentButton {
    implicitHeight: Widget.height
    text: I18n.tr("Base")
    active: root.editor.viewIndex < 0
    onClicked: root.editor.selectView(-1)
  }

  Repeater {
    model: root.views.length

    SegmentButton {
      id: chip
      required property int index
      readonly property var view: root.views[chip.index]
      implicitHeight: Widget.height
      iconText: root.editor.selected?.samples?.[chip.view?.id] !== undefined ? "bookmark" : ""
      text: chip.view?.name || chip.view?.id || ""
      active: root.editor.viewIndex === chip.index
      onClicked: root.editor.selectView(chip.index)

      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: point => root.menuRequested(chip.index, chip, point.position.x, point.position.y)
      }
    }
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
