pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The layouts editor on a screen layout (a ScreenLayoutEditor's draft:
// the desktop's, the lock screen's, the greeter's): its modules on the
// grid that fits the screen it's edited on at its card size, inside that
// screen's outline; other monitors fit their own, the modules keeping to
// their nearest edge. DesktopTarget, LockscreenTarget and GreeterTarget
// name it and hand in its editor and field groups.
EditTarget {
  id: root

  // The ScreenLayoutEditor being edited
  required property var screenEditor
  // What it is, over its fields in the side panel
  property string description: ""
  // Its layout's own fields in groups (`x-group`), for the side panel
  required property var fieldGroups
  // Whether Show on screen is offered (the editor's startPreview): not for
  // a draft that already shows live (`previewSection`)
  readonly property bool canPreview: root.screenEditor.previewSection === ""
  readonly property var layout: root.screenEditor.localLayout
  readonly property var grid: root.screenEditor.grid
  // The fit line for a layout fitted to each monitor, "" without one
  readonly property string stretchText: !root.layout ? "" : root.screenEditor.shrunk ? root.shrinkText : I18n.tr("{0} × {1} units on {2}; modules keep to their nearest edge on other monitors", root.grid.cols, root.grid.rows, root.screenEditor.screen?.name ?? "")
  // When its modules don't fit the screen at their Module size
  readonly property string shrinkText: I18n.tr("Modules shrunk to {0} % to fit {1}: move them closer together or lower Module size", root.screenEditor.shrunkTo, root.screenEditor.screen?.name ?? "")

  editor: root.screenEditor.layout
  modules: root.layout ? root.layout.modules : null
  screenBox: root.layout ? ({
      "x": 0,
      "y": 0,
      "w": root.grid.cols,
      "h": root.grid.rows
    }) : null
  fitText: root.stretchText
  // Smaller cards fit more on the screen
  fitLink: root.screenEditor.shrunk ? {
    "setting": "Widget.cardSize"
  } : null
  editable: root.layout !== null
}
