pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Apps section: the apps axiom opens (keybinds, the
// launcher's terminal apps and Shift+Enter commands, the network
// editor)
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Apps

  // Commands in place of the default apps (Settings › Default apps, the
  // mimeapps lists): "" uses the default
  readonly property string terminal: _c.terminal
  readonly property string fileManager: _c.fileManager
  readonly property string browser: _c.browser
  // The connection editor the Wi-Fi menu and VPN module open ("" hides
  // their buttons)
  readonly property string networkEditor: _c.networkEditor
  // Desktop entry ids every dock shows first, unless it has its own
  // (DockConfig.pinnedOf). Through a string, like DockConfig.docks
  readonly property string _pinnedJson: JSON.stringify(_c.pinned)
  readonly property var pinned: JSON.parse(_pinnedJson)
  // What a bind (or the onboarder) runs to open each: `axiom open`, which
  // starts the command above or else the default app when the key is
  // pressed, so a new default needs no new compositor config
  readonly property string terminalCommand: `${Paths.shellCommand} open terminal`
  readonly property string fileManagerCommand: `${Paths.shellCommand} open fileManager "$HOME"`
  readonly property string browserCommand: `${Paths.shellCommand} open browser`
  // `argv` run in a terminal: `terminal` (a widget's own, which may carry
  // arguments of its own) as `terminal -e argv`, else the terminal
  // `axiom open` starts (Apps.terminal, else the default terminal)
  function inTerminal(argv, terminal) {
    const term = String(terminal ?? "").trim();
    return term ? ["sh", "-c", term + ' -e "$@"', "sh"].concat(argv) : [Paths.axiomBin, "open", "terminal", "--"].concat(argv);
  }
}
