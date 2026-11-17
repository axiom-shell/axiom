pragma Singleton
import QtQuick

// Stand-in for the shell's CompositorManager in the layout harness: what a
// compositor can't do (`supports`) and the words for it.
QtObject {
  property var supports: ({})

  function unsupportedNote(capability) {
    return "Not supported here";
  }
}
