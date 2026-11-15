pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

// The user's window rules (docs/dev/features/window-rules.md): for now the
// Window rules page's editor and the report on the saved rules; the engine's
// state comes with the part that matches windows.
QtObject {
  id: root

  // The page's draft, selection and edits
  readonly property WindowRulesEditor editor: WindowRulesEditor {}

  // compositor.state's windowRules: the saved rules as the compositor's
  // config takes them, null until known
  readonly property var savedReport: CompositorConfigManager.windowRules
}
