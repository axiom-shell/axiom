pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods
import qs.components.content.parts.custom

// A custom widget's Text block element: longer output (the tooltip by
// default), top-left by default, at the Normal size and scrolling when it
// doesn't fit (CustomTextBody; Fit shrinks it instead). Monospace for tables
// (lines not wrapped, runs of spaces kept). A bound value is plain text
// unless the element sets markup; the font as the Text element's.
CustomTextBody {
  id: root

  shown: root.bind.text ? (root.options.markup ? CustomWidgetData.pango(root.text("text")) : root.text("text")) : (root.fields?.tooltip ?? "")
  // The tooltip is markup; a binding's only when asked
  rich: root.bind.text ? root.options.markup : true
  scrolls: true
}
