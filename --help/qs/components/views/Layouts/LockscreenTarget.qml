pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.session

// The layouts editor on the built-in lock screen (LockManager's draft of
// Lockscreen.layout).
ScreenLayoutTarget {
  id: root

  screenEditor: LockManager.editor
  fieldGroups: LockscreenConfig.fieldGroups
  icon: "lock"
  title: I18n.tr("Lock screen")
  description: I18n.tr("What the built-in locker shows. Modules here can't open apps or run anything; Power can suspend, restart and shut down.")
  fitText: LockscreenConfig.mode !== "quickshell" ? I18n.tr("Only the built-in locker shows this layout") : root.stretchText
  fitWarning: LockscreenConfig.mode !== "quickshell" || root.screenEditor.shrunk
  fitLink: LockscreenConfig.mode !== "quickshell" ? {
    "setting": "Lockscreen.mode"
  } : root.screenEditor.shrunk ? {
    "setting": "Widget.cardSize"
  } : null
}
