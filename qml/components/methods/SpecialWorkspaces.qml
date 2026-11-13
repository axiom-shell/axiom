pragma Singleton
import QtQuick

// Special workspace ids: what makes one valid (the id of a configured entry,
// a bind's or hot corner's argument). No file access, processes or services.
QtObject {
  id: root

  // The longest id
  readonly property int maxIdLength: 32

  // Whether `id` is a special workspace id: ItemId's pattern (starts with a
  // letter or digit, then letters, digits, ".", "_" or "-"), at most 32
  // characters, case-sensitive, and not "special" (Hyprland's bare special
  // workspace is `special:special`, so that name would mean the unnamed one).
  // "" is not an id: the unnamed special workspace has none.
  function validId(id) {
    if (typeof id !== "string" || id.length > root.maxIdLength || id === "special")
      return false;
    return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id);
  }
}
