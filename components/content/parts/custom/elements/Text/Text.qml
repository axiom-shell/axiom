pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Text element: a format or field (the widget's text by
// default), fitted to its box unless a size is set.
CustomElementBase {
  id: root

  readonly property string shown: root.bind.text ? root.text("text") : (root.fields?.text ?? "")
  // Markup (Pango turned into Qt's rich text) can't be fitted: it's drawn
  // at a size from the box
  readonly property bool rich: /<[a-z][^>]*>/i.test(root.shown)
  readonly property int fixedSize: ({
      "small": Appearance.fontSizeBy(-2),
      "normal": Appearance.fontSize,
      "large": Appearance.fontSizeLarge,
      "huge": Appearance.fontSize * 2
    })[root.options.size] ?? 0

  StyledText {
    anchors.fill: parent
    text: root.shown
    textFormat: root.rich ? Text.RichText : Text.PlainText
    textColor: root.colorOf(Theme.foreground)
    textFamily: root.options.monospace ? "monospace" : Appearance.fontFamily
    font.bold: root.options.bold
    horizontalAlignment: ({
        "left": Text.AlignLeft,
        "right": Text.AlignRight
      })[root.options.align] ?? Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    wrapMode: Text.Wrap
    elide: Text.ElideRight
    maximumLineCount: Math.max(1, Math.floor(root.height / Math.max(1, Appearance.fontSizeBy(-4) * 1.3)))
    textSize: root.fixedSize || Math.max(Appearance.fontSizeBy(-4), Math.min(Appearance.fontSize * 4, root.height * 0.7))
    fontSizeMode: root.fixedSize || root.rich ? Text.FixedSize : Text.Fit
    minimumPixelSize: Appearance.fontSizeBy(-4)
    clip: true
  }
}
