pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Text block element: longer output (the tooltip by
// default), top-aligned, scrolling when it doesn't fit; monospace for
// tables (lines not wrapped).
CustomElementBase {
  id: root

  readonly property string shown: root.bind.text ? root.text("text") : (root.fields?.tooltip ?? "")

  StyledScrollView {
    anchors.fill: parent

    StyledText {
      width: root.width
      text: root.shown
      textFormat: Text.RichText
      textColor: root.colorOf(Theme.foreground)
      textFamily: root.options.monospace ? "monospace" : Appearance.fontFamily
      textSize: Appearance.fontSizeBy(-1)
      wrapMode: root.options.monospace ? Text.NoWrap : Text.Wrap
    }
  }
}
