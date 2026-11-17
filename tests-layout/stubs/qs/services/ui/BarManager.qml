pragma Singleton
import QtQuick

// Stand-in for the shell's BarManager in the layout harness: no bars.
QtObject {
  property var localConfig: []

  function barLabel(index) {
    return "Bar " + (index + 1);
  }
}
