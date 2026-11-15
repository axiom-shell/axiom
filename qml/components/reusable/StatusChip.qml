pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small filled pill with a word: a status (On, Running, Not installed) in
// its tone's container, on the settings page's status cards. A caller's
// `color:` still wins over the tone until its area is restyled.
PopInRectangle {
  id: root

  property string text: ""
  // success | warning | error | info | accent | neutral
  property string tone: "neutral"

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
    textColor: root._ink.text
  }
}
