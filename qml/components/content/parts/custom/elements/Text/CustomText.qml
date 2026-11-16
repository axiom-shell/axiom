pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods
import qs.components.content.parts.custom

// A custom widget's Text element: a format or field (the widget's text by
// default), placed by Across and Down and fitted to its box unless a size
// is set (CustomTextBody). A bound value is plain text unless the element
// sets markup; the widget's own text keeps Waybar's markup. The font: the
// element's own, else monospace, else the module's, else the shell's.
CustomTextBody {
  id: root

  readonly property string raw: root.bind.text ? root.text("text") : (root.fields?.text ?? "")

  shown: root.bind.text && root.options.markup ? CustomWidgetData.pango(root.raw) : root.raw
  // Markup (Pango turned into Qt's rich text) is drawn only when asked for a binding's
  rich: root.bind.text ? root.options.markup : /<[a-z][^>]*>/i.test(root.raw)
  scrolls: false
}
