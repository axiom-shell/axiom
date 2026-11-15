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
  // The name is an icon of the desktop icon theme, drawn as a picture
  readonly property bool themed: root.options.source === "theme"
  readonly property string shown: root.bind.icon ? root.text("icon") : root.glyph ? (root.fields?.glyph ?? "") : root.themed ? (root.fields?.icon ?? "") : (root.fields?.icon || root.fallbackIcon)
  readonly property string badge: root.options.badge ? root.text("badge", "badge") : ""

  Thumbnail {
    visible: root.themed
    anchors.centerIn: parent
    width: Math.min(root.width, root.height) * 0.75
    height: width
    color: "transparent"
    radius: 0
    fillMode: Image.PreserveAspectFit
    source: root.themed ? root.themeIcon(root.shown) : ""
  }

  StyledIcon {
    id: glyph
    visible: !root.themed
    anchors.centerIn: parent
    text: root.shown
    textColor: root.colorOf(Style.accent)
    textSize: Math.max(Style.typeMicro, Math.min(root.width, root.height) * 0.75) // fitted: the element's box
  }

  // On the icon's corner, wherever the box puts it
  CountBadge {
    anchors.horizontalCenter: root.themed ? root.right : glyph.right
    anchors.verticalCenter: root.themed ? root.top : glyph.top
    text: root.badge
    color: Style.error
    textColor: Style.onError
    shown: root.badge !== "" && root.badge !== "0"
  }
}
