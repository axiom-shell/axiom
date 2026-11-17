pragma Singleton
import QtQuick

// Stand-in for the shell's OverlayManager in the layout harness: the menu
// editor's answers MenuOpening reads, all fixed (nothing previewing, nothing
// referencing the menu, saved).
QtObject {
  function pageLinkAvailable(page) {
    return false;
  }

  function pageLinkIcon(page) {
    return "";
  }

  function pageLinkLabel(page) {
    return "";
  }

  function openedBy(widget) {
    return null;
  }

  readonly property QtObject menus: QtObject {
    property string previewing: ""
    property bool showingOthers: false

    function canPreview(menu) {
      return true;
    }

    function references(id) {
      return [];
    }

    function submenuParentOf(id) {
      return null;
    }

    function isSaved(menu) {
      return true;
    }

    function togglePreviewing() {
    }

    function toggleShowingOthers() {
    }

    function goToReference(ref) {
    }

    function addBarButton(index, zone) {
    }

    function addKeybind() {
    }
  }
}
