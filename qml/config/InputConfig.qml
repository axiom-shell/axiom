pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Input section: the input sources and method, and the
// keyboard, mouse, touchpad and cursor axiom sets on the compositor, a part
// at a time ({ sources, method, keyboard: { enabled, options, … }, mouse,
// touchpad, cursor }, each set only while `enabled`; the sources' layouts
// while the keyboard's is), by the daemon (its config layer, and greeter.compositor for the greeter's).
// Named InputConfig as the section is a whole object.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Input

  // Goes through a string so a reload that leaves it unchanged doesn't
  // apply it again
  readonly property string _inputJson: JSON.stringify(_c)
  readonly property var input: JSON.parse(_inputJson)

  // The input sources ([{ id, kind: "xkb" | "ime", layout, variant, engine
  // }], methods/InputSources)
  readonly property var sources: input.sources
  // The sources as saved (no editor's preview): what the input method
  // framework is given (InputSourceManager)
  readonly property var savedSources: JSON.parse(_savedSourcesJson)
  readonly property string _savedSourcesJson: JSON.stringify(ConfigManager.config.Input.sources)

  // axiom manages the input method framework (Input.method.enabled): off,
  // only the xkb sources count and the framework is left alone
  readonly property bool methodEnabled: _c.method.enabled
  // As saved (no editor's preview): whether the framework is given the
  // sources and options
  readonly property bool savedMethodEnabled: ConfigManager.config.Input.method.enabled

  // The input method framework followed and given the sources, as saved
  // (an editor's preview never reaches the daemon): "fcitx5" (the
  // default), "ibus", "auto" (whichever runs) or "none"
  readonly property string savedFramework: ConfigManager.config.Input.method.framework
  // (autostart and legacyApps are the daemon's managed-mode writer's,
  // read from config.json)
  // The framework's options axiom sets (inputMethod.options: { shareState,
  // verticalCandidates, candidateFont, showSwitchPopup }), as saved (they
  // rewrite the framework's own config), the same object while they're
  // unchanged
  readonly property var savedMethodOptions: JSON.parse(_methodOptionsJson)
  readonly property string _methodOptionsJson: JSON.stringify({
    "shareState": _saved.method.shareState,
    "verticalCandidates": _saved.method.verticalCandidates,
    "candidateFont": _saved.method.candidateFont,
    "showSwitchPopup": _saved.method.showSwitchPopup
  })
  readonly property var _saved: ConfigManager.config.Input

  // The cursor theme picked, set or not ("" for none)
  readonly property string cursorTheme: _c.cursor.theme
}
