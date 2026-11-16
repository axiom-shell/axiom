import QtQuick
import QtTest

// The settings page's keyboard pattern on the pieces that import services
// (so the layout harness can't build them): each takes its Tab stop, Space and
// Enter and FocusRing from Pressable, whose behaviour is tested in
// tests-layout/tst_Pieces.
TestCase {
  id: root

  name: "TabFocus"

  RepoFiles {
    id: repo
  }

  // A hand-drawn rail and label over a Pressable (the sidebar's card links)
  readonly property var railed: ["qml/components/views/Settings/SettingsSidebar.qml"]

  // Their triggers are a Pressable (Tab stop, Space/Return/Enter, FocusRing,
  // tested in tests-layout/tst_Pieces) inside a FieldFrame
  readonly property var pressables: ["qml/components/views/Keybinds/ActionPicker.qml", "qml/components/views/Keybinds/KeyRecorder.qml"]

  function test_rails_take_keys_from_pressable() {
    for (const file of root.railed) {
      const text = repo.text(file);
      verify(text.includes("Pressable {"), file + " takes its keys from Pressable");
      verify(!text.includes("Keys.onSpacePressed") && !text.includes("FocusRing {"), file + " has no key handling of its own");
    }
  }

  function test_field_triggers_are_pressables() {
    for (const file of root.pressables) {
      const text = repo.text(file);
      verify(text.includes("Pressable {"), file + " takes its keys from Pressable");
      verify(text.includes("FieldFrame {"), file + " is a FieldFrame");
    }
  }

  // The tile pages draw their tiles as PreviewTile, which owns the click and
  // the Tab stop: none has a MouseArea of its own
  readonly property var tiles: ["qml/components/views/Settings/CommunitySetupsCard.qml", "qml/components/surfaces/onboarding/pages/LookPage.qml", "qml/components/views/CustomWidgets/GalleryForm.qml"]

  function test_tiles_are_preview_tiles() {
    for (const file of root.tiles) {
      const text = repo.text(file);
      verify(text.includes("PreviewTile {"), file + " draws PreviewTile tiles");
      verify(!text.includes("MouseArea {"), file + " has no MouseArea of its own");
    }
  }
}
