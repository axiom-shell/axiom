pragma Singleton
import QtQuick
import Quickshell.Io

import qs.config
import qs.services.core

// The desktop's file picker (scripts/pick_path.py: xdg-desktop-portal, else
// zenity or kdialog), for a file or a folder: config import, and the
// Browse button of folder settings (the schema's x-control: "folder"). One
// picker at a time; the overlay steps aside while it's open, since the
// picker is an ordinary window under the overlay's layer.
QtObject {
  id: root

  readonly property bool running: _picker.running

  // Opens the picker for owner (see forget). options: { folder (pick a
  // folder, not a file), start (the folder it opens in; ~ works, default
  // home), filter ("NAME:GLOB", files only), shortenHome (hand home back
  // as ~) }. onPicked(path) gets the chosen path; onFailed() runs when no
  // picker could be shown (cancelling calls neither). False if one is
  // already open, or in greeter mode.
  function pick(owner, title, options, onPicked, onFailed) {
    if (_picker.running || Paths.greeter)
      return false;
    _owner = owner;
    const start = Paths.expandHome(options?.start || "~");
    _onPicked = path => onPicked(options?.shortenHome ? Paths.shortenHome(path) : path);
    _onFailed = onFailed ?? null;
    _picker.command = ["python3", Paths.scriptsPath + "pick_path.py"].concat(options?.folder ? ["--folder"] : []).concat(options?.filter ? ["--filter", options.filter] : []).concat([title, start]);
    ShellManager.beginStepAside("filePicker");
    _picker.running = true;
    return true;
  }

  // Drops owner's callbacks (it's going away): its picker stays open, and
  // what's picked in it goes nowhere
  function forget(owner) {
    if (_owner !== owner)
      return;
    _owner = null;
    _onPicked = null;
    _onFailed = null;
  }

  // -- Private --
  property var _owner: null
  property var _onPicked: null
  property var _onFailed: null

  property Process _picker: Process {
    stdout: StdioCollector {
      id: pickedPath
    }
    stderr: StdioCollector {
      onStreamFinished: {
        if (text.trim() !== "")
          console.warn("[FilePickerManager]", text.trim());
      }
    }
    // Not in onExited: a picker that fails to start never exits, and the
    // overlay would stay hidden
    onRunningChanged: {
      if (!running)
        ShellManager.endStepAside("filePicker");
    }
    onExited: code => {
      const picked = root._onPicked;
      const failed = root._onFailed;
      root.forget(root._owner);
      if (code === 0 && pickedPath.text.trim() !== "")
        picked?.(pickedPath.text.trim());
      else if (code !== 1)
        failed?.();
    }
  }
}
