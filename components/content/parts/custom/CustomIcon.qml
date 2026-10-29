pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// A custom widget's Icon element: a Material Symbols name (the widget's icon
// field, else its definition's) or the format-icons glyph, with a badge.
// options: source (material, glyph), color, badge (true: the badge field)
CustomElementBase {
  id: root

  readonly property bool glyph: root.opt("source", "material") === "glyph"
  readonly property string shown: root.bind.icon ? root.text("icon") : root.glyph ? (root.fields?.glyph ?? "") : (root.fields?.icon || root.fallbackIcon)
  readonly property string badge: root.opt("badge", false) ? root.text("badge", "badge") : ""

  StyledIcon {
    anchors.centerIn: parent
    text: root.shown
    textColor: root.colorOf("color", Theme.accent)
    textSize: Math.max(Appearance.fontSizeBy(-4), Math.min(root.width, root.height) * 0.75)
  }

  CountBadge {
    anchors.right: parent.right
    anchors.top: parent.top
    text: root.badge
    shown: root.badge !== "" && root.badge !== "0"
  }
}
