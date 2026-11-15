pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Text block element: longer output (the tooltip by
// default), top-aligned, scrolling when it doesn't fit; monospace for
// tables (lines not wrapped, runs of spaces kept: rich text would collapse
// them). A bound value is plain text unless the element sets markup; the
// font as the Text element's.
CustomElementBase {
  id: root

  // Rich text: the tooltip's markup as is; a binding's escaped unless markup
  readonly property string shown: {
    const body = root.bind.text ? (root.options.markup ? CustomWidgetData.pango(root.text("text")) : CustomWidgetData.escapeText(root.text("text")).replace(/\n/g, "<br>")) : (root.fields?.tooltip ?? "");
    return root.options.monospace ? "<span style=\"white-space:pre\">" + body + "</span>" : body;
  }

  StyledScrollView {
    anchors.fill: parent

    StyledText {
      width: root.width
      text: root.shown
      textFormat: Text.RichText
      textColor: root.colorOf(Style.text)
      textFamily: root.options.font || (root.options.monospace ? "monospace" : root.moduleFont || Appearance.fontFamily)
      role: "caption"
      overflow: root.options.monospace ? "none" : "wrap"
    }
  }
}
