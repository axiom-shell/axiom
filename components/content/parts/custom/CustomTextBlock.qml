pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// A custom widget's Text block element: longer output (the tooltip by
// default), top-aligned, scrolling when it doesn't fit.
// options: monospace, color
CustomElementBase {
  id: root

  readonly property string shown: root.bind.text ? root.text("text") : (root.fields?.tooltip ?? "")

  StyledScrollView {
    anchors.fill: parent

    StyledText {
      width: root.width
      text: root.shown
      textFormat: Text.RichText
      textColor: root.colorOf("color", Theme.foreground)
      textFamily: root.opt("monospace", false) ? "monospace" : Appearance.fontFamily
      textSize: Appearance.fontSizeBy(-1)
      wrapMode: root.opt("monospace", false) ? Text.NoWrap : Text.Wrap
    }
  }
}
