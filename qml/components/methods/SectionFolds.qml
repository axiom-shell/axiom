pragma Singleton
import QtQuick

// The open or closed state of an editor's foldable list sections (the layouts
// editor's Overlay pages, Tools, Menus and Screens), kept as an object of
// stable section id to a boolean the user chose. A section nobody has
// toggled is open, except the ids in `closedByDefault`. `clean` makes the
// object read back from a saved file safe to use. No files, processes or
// services: EditsManager holds the state and saves it.
QtObject {
  id: root

  // Sections that start closed (Tools: a fixed set of pages most never touch)
  readonly property var closedByDefault: ["tools"]

  // Whether section `id` is open, given the choices made so far
  function isOpen(folds, id) {
    if (folds && Object.prototype.hasOwnProperty.call(folds, id))
      return folds[id] === true;
    return !root.closedByDefault.includes(id);
  }

  // The choices with `id` set to `open` (a new object; the argument is kept)
  function withOpen(folds, id, open) {
    const next = Object.assign({}, folds ?? {});
    next[id] = open === true;
    return next;
  }

  // The choices read from a saved file: only boolean values of own keys
  function clean(saved) {
    const out = {};
    if (!saved || typeof saved !== "object" || Array.isArray(saved))
      return out;
    for (const id of Object.keys(saved))
      if (typeof saved[id] === "boolean")
        out[id] = saved[id];
    return out;
  }

  // The choices from a whole saved state, read back from the shapes before
  // the one object: `sectionFolds`, else `layoutsFolds` (the same object);
  // `keybindsFolded` (an array of shut section names) adds "bind:<name>"
  // closed for any not chosen already
  function fromSaved(saved) {
    saved = saved ?? {};
    let folds = root.clean(saved.sectionFolds ?? saved.layoutsFolds);
    if (Array.isArray(saved.keybindsFolded))
      for (const section of saved.keybindsFolded)
        if (typeof section === "string" && !Object.prototype.hasOwnProperty.call(folds, "bind:" + section))
          folds = root.withOpen(folds, "bind:" + section, false);
    return folds;
  }
}
