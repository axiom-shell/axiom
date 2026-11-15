pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small filled pill with a word: a status (On, Running, Not installed) in
// its tone's container, on the settings page's status cards. A caller's
// `color:` (a data colour: a custom widget's Status element) wins over the
// tone and passes the `ink`.
PopInRectangle {
  id: root

  property string text: ""
  // success | warning | error | info | accent | neutral
  property string tone: "neutral"
  // The word's colour: the tone's ink; a caller passing its own `color:` passes the ink that reads on it
  property color ink: root._ink.text

  readonly property var _ink: root.tone === "neutral" ? Style.inkHighest : Style.inkOf(root.tone + "Container")

  implicitWidth: Math.ceil(label.implicitWidth) + Widget.padding * 2
  implicitHeight: Math.max(Widget.smallHeight, Math.ceil(label.implicitHeight) + Widget.px(2))
  radius: height / 2
  readonly property color _fill: {
    switch (root.tone) {
    case "success":
      return Style.successContainer;
    case "warning":
      return Style.warningContainer;
    case "error":
      return Style.errorContainer;
    case "info":
      return Style.infoContainer;
    case "accent":
      return Style.accentContainer;
    default:
      return Style.surfaceHighest;
    }
  }

  color: root._fill

  ColorGlide on color {
    duration: Appearance.animNormal
  }

  StyledLabel {
    id: label
    anchors.centerIn: parent
    role: "caption"
    overflow: "none"
    text: root.text
    textColor: root.ink
  }
}
