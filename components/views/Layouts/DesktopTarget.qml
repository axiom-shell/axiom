pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui

// The layouts editor on the desktop (DesktopManager's draft of the Desktop
// section): the layout of the target picked in the side panel (all
// monitors, the primary monitor, or one monitor), fitted inside the bars
// and border of the screen it's laid out on. A monitor without a layout of
// its own has nothing to edit until it's given one.
ScreenLayoutTarget {
  id: root

  // The room its grid is fitted to on the screen it's laid out on, px
  readonly property int roomWidth: DesktopManager.editor.room.width
  readonly property int roomHeight: DesktopManager.editor.room.height
  readonly property var target: DesktopManager.targets.find(t => t.key === DesktopManager.selectedTarget) ?? null

  screenEditor: DesktopManager.editor
  fieldGroups: DesktopConfig.fieldGroups
  icon: "desktop_windows"
  title: root.target ? I18n.tr("Desktop: {0}", root.target.label) : I18n.tr("Desktop")
  description: I18n.tr("Modules on the desktop, under your windows. They take clicks but not typing. A monitor shows its own layout if it has one, else the primary monitor's, else the one for all monitors.")
  emptyText: root.target ? I18n.tr("{0}: give it a layout of its own to edit it here.", root.target.status) : ""
  fitText: !root.layout ? "" : !root.layout.enabled ? I18n.tr("Turned off: the desktop doesn't show it") : root.screenEditor.shrunk ? root.shrinkText : I18n.tr("{0} × {1} units, fitted to {2} × {3} px inside the bars and border; modules keep to their nearest edge on other monitors", root.grid.cols, root.grid.rows, root.roomWidth, root.roomHeight)
  fitWarning: root.layout !== null && (!root.layout.enabled || root.screenEditor.shrunk)
}
