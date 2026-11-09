pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Notes section (see NotesManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Notes

  readonly property bool linked: _c.directory.trim() !== ""
  // The notes folder, absolute with a trailing slash ($XDG_DATA_HOME/axiom/notes/
  // when none is linked)
  readonly property string directory: root.linked ? Paths.expandHome(_c.directory).replace(/\/*$/, "/") : Paths.defaultNotesPath
  // Without dots, lower case
  readonly property var extensions: _c.extensions.map(ext => ext.trim().replace(/^\.+/, "").toLowerCase()).filter(ext => ext !== "")
  readonly property bool showHidden: _c.showHidden
  readonly property bool confirmDelete: _c.confirmDelete
}
