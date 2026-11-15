pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A multi-select filter chip: a pill with a word, on the highest surface
// while off and in the accent container, with a leading check, while on (the
// state is never the colour alone). A tap is `toggled`; the page owns
// `checked`, so a binding on it survives.
Surface {
  id: root

  // -- Public API --
  property string text: ""
  property bool checked: false

  signal toggled

  // -- Implementation --
  tone: root.checked ? "accentContainer" : "highest"
  radius: height / 2
  implicitWidth: Math.ceil(content.implicitWidth) + Widget.padding * 2
  implicitHeight: Math.max(Widget.smallHeight, Math.ceil(label.implicitHeight) + Widget.px(2))
  Layout.alignment: Qt.AlignVCenter

  StateLayer {
    hovered: area.containsMouse
    pressed: area.pressed
  }

  RowLayout {
    id: content
    anchors.centerIn: parent
    spacing: Widget.spacing / 2

    StyledIcon {
      visible: root.checked
      text: "check"
      size: "xs"
    }

    StyledLabel {
      id: label
      text: root.text
      role: "label"
      tone: root.checked ? "" : "muted"
      overflow: "none"
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggled()
  }
}
