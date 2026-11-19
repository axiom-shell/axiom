pragma Singleton
import QtQuick

// The shape check for state read from a JSON file: a value is kept only
// if it has the kind of the fallback the caller expects (array, plain
// object, or the primitive type), so a hand-edited or old file can't hand
// a string to code that indexes an object. No file access, processes or
// services.
QtObject {
  id: root

  function _kind(value) {
    if (Array.isArray(value))
      return "array";
    if (value === null)
      return "null";
    return typeof value;
  }

  // `value` if its kind matches `fallback`'s, else `fallback`. A null
  // fallback accepts any non-null object or array.
  function accept(value, fallback) {
    const kind = root._kind(value);
    if (fallback === null || fallback === undefined)
      return kind === "object" || kind === "array" ? value : fallback;
    return kind === root._kind(fallback) ? value : fallback;
  }

  // { value, corrupt } for the text of a state file. Empty text (null,
  // undefined, "") is no state: the fallback, not corrupt. Text that isn't
  // JSON is the fallback and corrupt. JSON of the wrong kind is the
  // fallback, not corrupt.
  function parse(text, fallback) {
    if (text === null || text === undefined || text === "")
      return {
        "value": fallback,
        "corrupt": false
      };
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch (e) {
      return {
        "value": fallback,
        "corrupt": true
      };
    }
    return {
      "value": root.accept(parsed, fallback),
      "corrupt": false
    };
  }
}
