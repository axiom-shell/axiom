pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// Reader for the Lockscreen section: which locker locks the session, and
// what the built-in one shows (`layout`, as saved: the lock never shows
// the layouts editor's unsaved draft, LockManager.editor.localLayout).
// Named LockscreenConfig because `Lockscreen` is the shell entry type.
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Lockscreen

  // "quickshell" (built-in) | "none"
  readonly property string mode: _c.mode
  // What lock buttons run in "none" mode
  readonly property string lockCommand: _c.lockCommand

  // The built-in lock screen, a ScreenLayout: { grid: { columns, rows,
  // fine } (fitted to each monitor; `fine` splits its units in two),
  // moduleScale, moduleBorders, modules, otherScreens ("layout": the
  // modules without the password | "background"), backdrop: { source
  // ("wallpaper" | "color"), blur, color, dim (%) }, borders: { password,
  // greeting } }. LockSurface takes it whole, so the layouts editor's
  // preview can hand it the draft instead
  readonly property var layout: _c.layout
  // The layout's own fields in groups (`x-group`), for the layouts editor
  readonly property var fieldGroups: SchemaLayout.objectGroups(ConfigManager.configSchema.definitions.ScreenLayout, ["modules"])
}
