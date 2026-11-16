import QtQuick
import QtTest

// The settings page's keyboard pattern on the pieces that import services
// (so the layout harness can't build them): each is a Tab stop, runs its
// action on Space and Enter, and draws a FocusRing. The behaviour of the
// loadable one, FoldHeader, is tested in tests-layout/tst_Pieces.
TestCase {
  id: root

  name: "TabFocus"

  RepoFiles {
    id: repo
  }

  readonly property var pieces: [
    {
      "file": "qml/components/views/Settings/SettingsSidebar.qml"
    },
    {
      "file": "qml/components/views/Settings/CommunitySetupsCard.qml"
    },
    {
      "file": "qml/components/views/Keybinds/ActionPicker.qml"
    },
    {
      "file": "qml/components/views/Keybinds/KeyRecorder.qml"
    }
  ]

  function test_pieces_take_tab_and_keys() {
    for (const piece of root.pieces) {
      const text = repo.text(piece.file);
      verify(text.includes("activeFocusOnTab: true"), piece.file + " is a Tab stop");
      verify(text.includes("Keys.onSpacePressed"), piece.file + " acts on Space");
      verify(text.includes("Keys.onReturnPressed"), piece.file + " acts on Return");
      verify(text.includes("FocusRing {"), piece.file + " draws a focus ring");
    }
  }
}
