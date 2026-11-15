pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Text element: a format or field (the widget's text by
// default), fitted to its box unless a size is set (`fill`: grown to the
// box, uncapped). A bound value is plain text unless the element sets
// markup; the widget's own text keeps Waybar's markup. The font: the
// element's own, else monospace, else the module's, else the shell's.
CustomElementBase {
  id: root

  readonly property string shown: root.bind.text ? root.text("text") : (root.fields?.text ?? "")
  // Markup (Pango turned into Qt's rich text) can't be fitted: it's drawn
  // at a size from the box. A binding's is drawn only when asked
  readonly property bool rich: root.bind.text ? root.options.markup : /<[a-z][^>]*>/i.test(root.shown)
  readonly property bool fill: root.options.size === "fill"
  readonly property int fixedSize: ({
      "small": Style.typeCaption,
      "normal": Style.typeBody,
      "large": Style.typeHeadline,
      "huge": Style.typeBody * 2
    })[root.options.size] ?? 0

  StyledText {
    anchors.fill: parent
    text: root.bind.text && root.options.markup ? CustomWidgetData.pango(root.shown) : root.shown
    textFormat: root.rich ? Text.RichText : Text.PlainText
    textColor: root.colorOf(Style.text)
    textFamily: root.options.font || (root.options.monospace ? "monospace" : root.moduleFont || Appearance.fontFamily)
    font.weight: root.options.bold ? Style.weightStrong : Style.weightNormal
    horizontalAlignment: ({
        "left": Text.AlignLeft,
        "right": Text.AlignRight
      })[root.options.align] ?? Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    overflow: "wrap"
    maxLines: Math.max(1, Math.floor(root.height / Math.max(1, Style.typeMicro * 1.3)))
    // Fitted, it's never larger than a built-in module's figure (StatFigure); `fill` has no cap
    textSize: root.fixedSize || (root.fill ? Math.max(Style.typeMicro, root.height * 0.85) : Math.max(Style.typeMicro, Math.min(Style.typeBody * 2, root.height * 0.7))) // fitted: the element's box
    fontSizeMode: root.fixedSize || root.rich ? Text.FixedSize : Text.Fit
    minimumPixelSize: Style.typeMicro
    clip: true
  }
}
