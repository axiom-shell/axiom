pragma Singleton
import QtQuick

import qs.config
import qs.services.core
import qs.services.ui

// The desktop's file picker (axiom's filepicker.pick: xdg-desktop-portal,
// else zenity or kdialog), for a file or a folder: config import, and the
// Browse button of folder settings (the schema's x-control: "folder"). One
// picker at a time; the overlay steps aside while it's open, since the
// picker is an ordinary window under the overlay's layer.
QtObject {
  id: root

  readonly property bool running: root._running

  // Opens the picker for owner (see forget). options: { folder (pick a
  // folder, not a file), start (the folder it opens in; ~ works, default
  // home), filter ("NAME:GLOB", files only), shortenHome (hand home back
  // as ~) }. onPicked(path) gets the chosen path; onFailed() runs when no
  // picker could be shown (cancelling calls neither). False if one is
  // already open, or in greeter mode.
  function pick(owner, title, options, onPicked, onFailed) {
    if (root._running || Paths.greeter)
      return false;
    _owner = owner;
    _onPicked = path => onPicked(options?.shortenHome ? Paths.shortenHome(path) : path);
    _onFailed = onFailed ?? null;
    SurfaceManager.beginStepAside("filePicker");
    root._running = true;
    BackendManager.call("filepicker.pick", {
      "title": title,
      "start": Paths.expandHome(options?.start || "~"),
      "folder": options?.folder === true,
      "filter": options?.filter ?? ""
    }, (error, result) => {
      root._running = false;
      SurfaceManager.endStepAside("filePicker");
      if (error)
        console.warn("[FilePickerManager]", error.message);
      const picked = root._onPicked;
      const failed = root._onFailed;
      root.forget(root._owner);
      if (error)
        failed?.();
      else if (result.path !== "")
        picked?.(result.path);
    });
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
  property bool _running: false
}
