pragma Singleton
import QtQuick

// Stand-in for the shell's KeybindManager in the layout harness: the key
// map's modifier chips toggle the page's modifiers; here that does nothing.
QtObject {
  readonly property QtObject page: QtObject {
    readonly property var keyMapMods: []

    function toggleKeyMapMod(mod) {
    }
  }
}
