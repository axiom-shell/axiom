pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// A field that takes the next key pressed as its value (a custom widget's
// key: "3", "space", "ctrl+z", CustomWidgetData.keyName): click it, then
// press. Escape, Tab and Shift+Tab are never keys (CustomWidgetData.
// reservedKeys): they pass through, so Tab moves the focus on and Escape
// reaches the page. A key in `taken` (the other rows' keys) is refused, and
// it says so. `captured(name)`.
FocusScope {
  id: root

  property string value: ""
  // The other rows' keys: pressing one is refused
  property var taken: []
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
    // Tab and Escape are not keys: they pass through
    if (CustomWidgetData.mappableKey(name) === "")
      return;
    event.accepted = true;
    root.refused = name !== root.value && root.taken.includes(name);
    if (!root.refused)
      root.captured(name);
  }
  onActiveFocusChanged: root.refused = false

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
      text: root.refused ? I18n.tr("Another row has this key") : root.activeFocus ? I18n.tr("Press a key…") : root.value
      textFamily: root.activeFocus ? Appearance.fontFamily : "monospace"
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
