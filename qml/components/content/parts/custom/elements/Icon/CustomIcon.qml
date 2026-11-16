pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Icon element: a Material Symbols name (the widget's icon
// field, else its definition's) or the format-icons glyph, with a badge,
// placed in its box by Across and Down: Fit is three quarters of the box's
// short side, else a shell icon size.
CustomElementBase {
  id: root

  readonly property bool glyph: root.options.source === "glyph"
  // The name is an icon of the desktop icon theme, drawn as a picture
  readonly property bool themed: root.options.source === "theme"
  readonly property string shown: root.bind.icon ? root.text("icon") : root.glyph ? (root.fields?.glyph ?? "") : root.themed ? (root.fields?.icon ?? "") : (root.fields?.icon || root.fallbackIcon)
  readonly property string badge: root.options.badge ? root.text("badge", "badge") : ""
  // Its background (picked or by a rule), else null: none
  readonly property var background: root.colorFor("background", null)
  // The glyph's (or picture's) side
  readonly property real side: root.fixedIconSize || Math.max(Style.typeMicro, Math.min(root.width, root.height) * 0.75) // fitted: the element's box

  Surface {
    anchors.fill: parent
    visible: root.background !== null
    outlined: false
    color: root.background ?? "transparent"
  }

  Thumbnail {
    id: picture
    visible: root.themed
    x: root.placeX(width)
    y: root.placeY(height)
    width: root.side
    height: width
    color: "transparent"
    radius: 0
    fillMode: Image.PreserveAspectFit
    source: root.themed ? root.themeIcon(root.shown) : ""
  }

  StyledIcon {
    id: glyph
    visible: !root.themed
    x: root.placeX(width)
    y: root.placeY(height)
    text: root.shown
    textColor: root.colorOf(root.background !== null ? root.inkOn(root.background) : Style.accent)
    textSize: root.side
  }

  // On the picture's (or glyph's) corner, wherever the box puts it
  CountBadge {
    anchors.horizontalCenter: root.themed ? picture.right : glyph.right
    anchors.verticalCenter: root.themed ? picture.top : glyph.top
    text: root.badge
    color: Style.error
    textColor: Style.onError
    shown: root.badge !== "" && root.badge !== "0"
  }
}
