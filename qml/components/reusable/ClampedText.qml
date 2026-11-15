pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// Muted help text cut to `maxLines`, with a More link that shows the rest
// (and Less to fold it again) only when it's longer
ColumnLayout {
  id: root

  property string text: ""
  property int maxLines: 3
  property bool expanded: false

  // Whether More shows is decided from the text's width alone (the hidden
  // `measure` below), never from `body.truncated`: that depends on the size the
  // layouts hand the body, and showing More changes this item's size, which
  // re-polishes those layouts, which flips `truncated` again - a polish loop
  // that freezes the shell.
  readonly property bool _long: body.width > 0 && measure.lineCount > root.maxLines

  Layout.fillWidth: true
  spacing: 0
  visible: root.text !== ""

  StyledText {
    id: body
    Layout.fillWidth: true
    role: "caption"
    tone: "muted"
    text: root.text
    overflow: "wrap"
    maxLines: root.expanded ? 0 : root.maxLines

    // Hidden measurer: width bound to the body's, a child of the body so the layout doesn't manage it
    Text { // style-exempt: a measurer, never drawn
      id: measure
      visible: false
      width: body.width
      text: root.text
      font: body.font
      wrapMode: Text.Wrap
      renderType: Text.NativeRendering // style-exempt: a measurer, never drawn
    }
  }

  // Built only when it shows
  Loader {
    active: root._long || root.expanded
    visible: active
    sourceComponent: StyledText {
      id: toggle
      role: "caption"
      text: root.expanded ? I18n.tr("Less") : I18n.tr("More")
      // In the accent, so it stands out from the muted text above
      tone: "accent"
      font.underline: toggleArea.containsMouse

      MouseArea {
        id: toggleArea
        anchors.fill: parent
        anchors.margins: -Widget.px(2)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded
      }
    }
  }
}
