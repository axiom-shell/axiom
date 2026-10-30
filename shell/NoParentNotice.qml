pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.services.core
import qs.components.methods

// What shows instead of the shell when axiom didn't start it (qs run by
// hand, an old autostart line) or was built for other shell files: a
// notice on each screen saying how to start it. It reads no config, so
// it has fixed colors, English text and every monitor (General isn't
// there to ask).
Scope {
  id: root

  // Why not: "" (not started by axiom) or axiom's reason (incompatible)
  readonly property string reason: BackendManager.incompatible
  // The compositor the environment names first (CompositorManager would
  // start its backend)
  readonly property string _compositor: CompositorKind.candidates(CompositorKind.envNames.reduce((env, name) => {
    env[name] = Quickshell.env(name) ?? "";
    return env;
  }, {}))[0]?.kind ?? ""
  // install.sh's autostart line for this compositor
  readonly property string _line: ({
      "hyprland": 'hl.on("hyprland.start", function() hl.exec_cmd("axiom run") end)   (hyprland.lua)',
      "sway": "exec axiom run   (sway's config)",
      "niri": 'spawn-sh-at-startup "axiom run"   (niri\'s config.kdl)'
    })[root._compositor] ?? "axiom run   (from your compositor's autostart)"

  Variants {
    model: Quickshell.screens // allowed: it reads no config, so General isn't there to ask

    PanelWindow {
      id: window

      required property var modelData
      screen: modelData
      anchors.top: true
      margins {
        top: 24
      }
      implicitWidth: Math.min(modelData.width - 48, column.implicitWidth + 48) // fixed px: no config to size by without axiom
      implicitHeight: column.implicitHeight + 32 // fixed px: no config to size by without axiom
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "axiom-notice"
      WlrLayershell.layer: WlrLayer.Overlay

      Rectangle {
        anchors.fill: parent
        radius: 8 // fixed px: no config to size by without axiom
        color: "#282828"
        border.width: 1
        border.color: "#fb4934"

        Column {
          id: column
          anchors.centerIn: parent
          spacing: 8 // fixed px: no config to size by without axiom

          Text {
            color: "#ebdbb2"
            font.pixelSize: 16 // fixed px: no config to size by without axiom
            font.bold: true
            text: root.reason ? "This axiom binary was built for other shell files" : "axiom isn't running this shell"
          }
          Text {
            color: "#d5c4a1"
            font.pixelSize: 14 // fixed px: no config to size by without axiom
            text: root.reason ? root.reason + "\nUpdate axiom (or run the binary built from this checkout)." : "The shell is started by the axiom binary. Start it with:"
          }
          Text {
            visible: !root.reason
            color: "#fabd2f"
            font.pixelSize: 14 // fixed px: no config to size by without axiom
            font.family: "monospace"
            text: root._line
          }
        }
      }
    }
  }
}
