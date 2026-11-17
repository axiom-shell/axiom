pragma Singleton
import QtQuick

// Stand-in for the shell's SurfaceManager in the layout harness: the modal
// registry ModalCard reports to, kept as a list a test reads.
QtObject {
  property var modals: []

  function registerModal(window) {
    modals = modals.filter(w => w !== window).concat([window]);
  }

  function unregisterModal(window) {
    modals = modals.filter(w => w !== window);
  }
}
