pragma Singleton
import QtQuick

// The tone a key shows on a keyboard map for who binds it (KeyMap.occupancy's
// `source`, or KeyMap.labels'): the key map's panel and the reference share it
QtObject {
  function tone(source) {
    switch (source) {
    case "axiom":
      return "accentTint";
    case "both":
      return "errorTint";
    case "paused":
      return "highest";
    case "user":
      return "warningTint";
    }
    return "sunken";
  }
}
