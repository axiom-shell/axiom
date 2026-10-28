pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Compositor section: how axiom sets the compositor up
// (CompositorConfigManager)
QtObject {
  readonly property var _c: ConfigManager.live.Compositor

  // "detached" | "included" | "managed"
  readonly property string mode: _c.mode
  // How sway shows a special group: "scratchpad" (its windows float over
  // the workspace) or "workspace" (a workspace of its own)
  readonly property string swaySpecial: _c.sway.specialWorkspaces
}
