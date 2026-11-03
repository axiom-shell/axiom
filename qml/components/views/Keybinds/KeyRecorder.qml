pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts

// A bind's key combo as keycaps; click to record a new one. While it
// records, combos the compositor binds reach it instead of firing: its
// window inhibits the compositor's shortcuts (niri's only way), and
// KeybindEditor holds Hyprland or sway in an empty submap or mode. A wheel
// turn over it records a scroll (SUPER + mouse_down), and a modifier let go
// with no other key between records a tap (Super_L) where the compositor
// binds one. Esc cancels.
StyledContainer {
  id: root

  required property int bindIndex
  required property string combo
  property bool invalid: false
  // Shown while it holds no combo
  property string placeholder: I18n.tr("Click to record")

  readonly property bool recording: KeybindManager.editor.recordingIndex === root.bindIndex
  // Modifiers held so far while recording
  property var held: []
  // The modifier key pressed alone, as a tap ("Super_L"), until another
  // key comes
  property string tap: ""
  readonly property var parts: KeyNames.split(root.combo)

  implicitHeight: Widget.height
  backgroundColor: root.recording ? Theme.background : (area.containsMouse ? Theme.backgroundHighlight : Theme.backgroundAlt)
  borderColor: root.recording ? Theme.accent : (root.invalid ? Theme.error : Theme.border)

  onRecordingChanged: {
    root.held = [];
    root.tap = "";
    if (root.recording)
      catcher.forceActiveFocus();
  }
  // Recording may start before it's built (a bind added and recorded)
  Component.onCompleted: {
    if (root.recording)
      catcher.forceActiveFocus();
  }
  Component.onDestruction: {
    if (root.recording)
      KeybindManager.editor.stopRecording();
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Widget.padding / 2
    anchors.rightMargin: Widget.padding / 2
    spacing: Widget.spacing / 2
    clip: true

    Repeater {
      model: root.recording ? root.held : root.parts.mods

      delegate: KeyCap {
        required property string modelData
        text: KeyNames.modifierLabel(modelData)
      }
    }

    KeyCap {
      visible: !root.recording && root.parts.key !== ""
      text: KeybindManager.displayKey(root.parts.key)
    }

    StyledText {
      visible: root.recording || root.parts.key === ""
      text: root.recording ? I18n.tr("Press a combo…") : root.placeholder
      textColor: root.recording ? Theme.accent : Theme.foreground
      opacity: root.recording ? 1 : 0.5
      textSize: Appearance.fontSizeBy(-1)
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    Item {
      visible: !root.recording && root.parts.key !== ""
      Layout.fillWidth: true
    }

    // Esc cancels a recording
    KeyCap {
      visible: root.recording
      text: "Esc"
      opacity: 0.5
    }

    StyledIcon {
      visible: !root.recording
      text: "keyboard"
      opacity: 0.5
      textSize: Appearance.fontSizeBy(-2)
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.recording)
        KeybindManager.editor.stopRecording();
      else
        KeybindManager.editor.startRecording(root.bindIndex);
    }
    onWheel: wheel => {
      wheel.accepted = root.recording;
      if (!root.recording)
        return;
      const combo = KeyNames.fromWheel(wheel.angleDelta.x, wheel.angleDelta.y, wheel.modifiers, root.held);
      if (combo !== "")
        KeybindManager.editor.finishRecording(combo);
    }
  }

  // The compositor's binds don't fire while recording (on niri, all but
  // its `allow-inhibiting=false` ones), so they reach the catcher
  ShortcutInhibitor {
    window: root.QsWindow.window
    enabled: root.recording
  }

  // Takes every key while recording
  Item {
    id: catcher
    onActiveFocusChanged: {
      if (!activeFocus && root.recording)
        KeybindManager.editor.stopRecording();
    }

    Keys.onPressed: event => {
      event.accepted = true;
      if (!root.recording || event.isAutoRepeat)
        return;
      if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
        KeybindManager.editor.stopRecording();
        return;
      }
      const combo = KeyNames.fromEvent(event.key, event.modifiers, event.nativeScanCode);
      if (combo !== "") {
        KeybindManager.editor.finishRecording(combo);
        return;
      }
      const mods = KeyNames.modifiersOf(event.modifiers);
      const own = KeyNames.modifierFor(event.key);
      root.tap = root.held.length === 0 && CompositorManager.supports.modifierTap ? KeyNames.tapName(event.key, event.nativeScanCode) : "";
      root.held = KeyNames.modifiers.filter(mod => mods.includes(mod) || mod === own);
    }
    Keys.onReleased: event => {
      event.accepted = true;
      if (!root.recording || event.isAutoRepeat)
        return;
      if (root.tap !== "" && KeyNames.tapName(event.key, event.nativeScanCode) === root.tap) {
        KeybindManager.editor.finishRecording(root.tap);
        return;
      }
      const mods = KeyNames.modifiersOf(event.modifiers);
      const own = KeyNames.modifierFor(event.key);
      root.held = KeyNames.modifiers.filter(mod => mods.includes(mod) && mod !== own);
    }
  }
}
