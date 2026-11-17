pragma Singleton
import QtQuick

// Stand-in for the shell's EditsManager in the layout harness: the number
// field tells it about typing; here that does nothing.
QtObject {
  // The editor libraries' A-Z / By category choice
  property bool libraryGrouped: true

  function setLibraryGrouped(value) {
    libraryGrouped = value;
  }

  function holdTyping(item, window) {
  }

  function releaseTyping(item) {
  }

  function discardTyping(item) {
  }

  function discardTypingIn(item) {
  }
}
