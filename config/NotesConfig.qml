pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Notes section (see NotesManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Notes

  // $XDG_DATA_HOME/axiom/notes/
  readonly property string defaultDirectory: Paths.defaultNotesPath
  readonly property bool linked: _c.directory.trim() !== ""
  // The notes folder, absolute with a trailing slash
  readonly property string directory: {
    let dir = _c.directory.trim();
    if (dir === "")
      return root.defaultDirectory;
    if (dir === "~" || dir.startsWith("~/"))
      dir = Paths.homeDirectory + dir.slice(2);
    return dir.replace(/\/*$/, "/");
  }
  // Without dots, lower case
  readonly property var extensions: _c.extensions.map(ext => ext.trim().replace(/^\.+/, "").toLowerCase()).filter(ext => ext !== "")
  readonly property bool showHidden: _c.showHidden
  readonly property bool confirmDelete: _c.confirmDelete
}
