pragma Singleton
import QtQuick

// The polkit agents axiom knows about (PolkitManager): a session has one
// agent, so while axiom is its agent these are stopped and left out of the
// generated autostart. `unit` is the systemd user unit that starts one, ""
// for agents only started directly.
QtObject {
  id: root

  readonly property var agents: [
    {
      "process": "hyprpolkitagent",
      "unit": "hyprpolkitagent.service"
    },
    {
      "process": "polkit-kde-authentication-agent-1",
      "unit": "plasma-polkit-agent.service"
    },
    {
      "process": "polkit-gnome-authentication-agent-1",
      "unit": ""
    },
    {
      "process": "polkit-mate-authentication-agent-1",
      "unit": ""
    },
    {
      "process": "lxqt-policykit-agent",
      "unit": ""
    },
    {
      "process": "lxpolkit",
      "unit": ""
    },
    {
      "process": "xfce-polkit",
      "unit": ""
    },
    {
      "process": "soteria",
      "unit": ""
    }
  ]

  readonly property var units: agents.map(agent => agent.unit).filter(unit => unit !== "")

  // An extended regex (pgrep -f) matching a known agent's command line:
  // its executable, by path or name, then the end or an argument. Anchored
  // to the executable, so pkill never takes a process that only names one
  // in its arguments (an editor on a file called soteria)
  readonly property string processPattern: `^([^ ]*/)?(${agents.map(agent => _escape(agent.process)).join("|")})( |$)`

  function _escape(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }
}
