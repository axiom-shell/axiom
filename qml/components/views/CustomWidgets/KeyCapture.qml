pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// A field that takes the next key pressed as its value (a custom widget's
// key: "3", "space", "ctrl+z", CustomWidgetData.keyName): click it, then
// press. Escape, Tab and Shift+Tab are never keys (CustomWidgetData.
// reservedKeys): they are refused, and it says so. `captured(name)`.
FocusScope {
  id: root

  property string value: ""
  // The last key refused
  property bool refused: false

  signal captured(string name)

  implicitHeight: Widget.height
  implicitWidth: Widget.textPx(120)
  activeFocusOnTab: true

  Keys.onPressed: event => {
    const name = CustomWidgetData.keyName(event.key, event.text, event.modifiers, event.isAutoRepeat);
    // A modifier alone, or a repeat, is no key
    if (name === "")
      return;
    event.accepted = true;
    root.refused = CustomWidgetData.mappableKey(name) === "";
    if (!root.refused)
      root.captured(name);
  }
  onActiveFocusChanged: {
    if (root.activeFocus)
      root.refused = false;
  }

  Surface {
    anchors.fill: parent
    tone: root.activeFocus ? "accentContainer" : "highest"
    radius: Widget.radius

    StateLayer {
      hovered: area.containsMouse
      pressed: area.pressed
    }

    StyledText {
      anchors.fill: parent
      anchors.margins: Widget.padding
      verticalAlignment: Text.AlignVCenter
      text: root.refused ? I18n.tr("Not a key a widget can use") : root.activeFocus ? I18n.tr("Press a key…") : root.value
      textFamily: root.activeFocus ? "" : "monospace"
      overflow: "line"
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.forceActiveFocus()
    }
  }
}
