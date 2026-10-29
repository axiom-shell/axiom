pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Icon element: a Material Symbols name (the widget's icon
// field, else its definition's) or the format-icons glyph, with a badge.
CustomElementBase {
  id: root

  readonly property bool glyph: root.options.source === "glyph"
  readonly property string shown: root.bind.icon ? root.text("icon") : root.glyph ? (root.fields?.glyph ?? "") : (root.fields?.icon || root.fallbackIcon)
  readonly property string badge: root.options.badge ? root.text("badge", "badge") : ""

  StyledIcon {
    anchors.centerIn: parent
    text: root.shown
    textColor: root.colorOf(Theme.accent)
    textSize: Math.max(Appearance.fontSizeBy(-4), Math.min(root.width, root.height) * 0.75)
  }

  CountBadge {
    anchors.right: parent.right
    anchors.top: parent.top
    text: root.badge
    shown: root.badge !== "" && root.badge !== "0"
  }
}
