pragma Singleton
import QtQuick

// Stand-in for qs.config Paths in the layout harness (the real one imports
// Quickshell): no path is ever read by a row.
QtObject {
  function expandHome(p) {
    return p;
  }
}
