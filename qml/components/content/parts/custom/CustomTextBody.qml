pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// What a Text and a Text block draw (CustomText, CustomTextBlock fill in
// `shown` and `rich`): the text in its box, placed by `align` and `valign`,
// at the element's size: Fit grows and shrinks with the box (never capped;
// markup can't be fitted, so it is drawn at the one-line size from the box),
// the others are the shell's text sizes. Fit wraps and shrinks, and elides
// its last line at the smallest type. `scrolls` (the Text block) scrolls a
// text at a fixed size that outgrows its box, and keeps it short against the
// side `valign` names. A background colour insets the text and fills the
// box.
CustomElementBase {
  id: root

  // The text to draw (a Pango binding already turned into Qt's rich text)
  property string shown: ""
  // `shown` is rich text (markup), not plain
  property bool rich: false
  // A text at a fixed size scrolls when it is longer than the box
  property bool scrolls: false

  // Its background (picked or by a rule), else null: none
  readonly property var background: root.colorFor("background", null)
  readonly property real innerHeight: Math.max(0, root.height - 2 * root.inset)
  // Fit: not a fixed size, and not markup
  readonly property bool fitting: root.fixedTextSize === 0 && !root.rich
  // The size drawn, and the lines it holds in the box (at least one)
  readonly property real drawnSize: root.textSizeFor(root.innerHeight)
  readonly property int lines: CustomWidgetData.textLines(root.innerHeight, root.fixedTextSize || Style.typeMicro)

  inset: root.background !== null ? Widget.px(4) : 0

  Surface {
    anchors.fill: parent
    visible: root.background !== null
    outlined: false
    radius: Style.radius
    color: root.background ?? "transparent"
  }

  // The text, in a box of its own: both looks draw it the same
  component Body: StyledText {
    text: root.rich && root.options.monospace ? "<span style=\"white-space:pre\">" + root.shown + "</span>" : root.shown
    textFormat: root.rich ? Text.RichText : Text.PlainText
    textColor: root.colorOf(root.background !== null ? root.inkOn(root.background) : Style.text)
    textFamily: root.options.font || (root.options.monospace ? "monospace" : root.moduleFont || Appearance.fontFamily)
    font.weight: root.options.bold ? Style.weightStrong : Style.weightNormal
    textSize: root.drawnSize
    horizontalAlignment: root.hAlign
    verticalAlignment: root.vAlign
    // Monospace keeps its runs of spaces and its lines (tables)
    overflow: root.options.monospace ? "none" : "wrap"
    fontSizeMode: root.fitting ? Text.Fit : Text.FixedSize
    minimumPixelSize: Style.typeMicro
  }

  Loader {
    anchors.fill: parent
    // Fit keeps a margin of the box's height, so its lines never touch the edge
    anchors.margins: root.inset + (root.fitting ? root.innerHeight * 0.04 : 0)
    sourceComponent: root.scrolls && !root.fitting ? scrolling : still
  }

  // One box, the text fitted or cut to it
  Component {
    id: still
    Body {
      maxLines: root.lines
      clip: true
    }
  }

  // Scrolls; the text is at least the viewport tall, so `valign` shows while it is short
  Component {
    id: scrolling
    StyledScrollView {
      id: scroll
      contentPadding: 0

      Body {
        width: scroll.availableWidth
        height: Math.max(implicitHeight, scroll.availableHeight)
      }
    }
  }
}
