pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.config
import qs.components.methods

// The one way to draw a box: a Style surface tone, its translucent fill, its
// hairline, and `ink`, the colours that read on it; text and icons inside
// take it by default. Put content inside the Surface it sits on: a sibling
// fill is not inherited. docs/dev/core/style.md.
Rectangle {
  id: root

  // -- Public API --
  // page | sunken | surface | raised | highest | accent | accentContainer |
  // successContainer | warningContainer | errorContainer | infoContainer |
  // accentTint | warningTint | errorTint (the keyboard map's source tints)
  // (success | warning | error | info: the solid status fills)
  property string tone: "surface"
  // A hairline: borderSubtle on page and surface, borderStrong on the rest
  property bool outlined: root.tone === "page" || root.tone === "surface" || root.tone === "raised"
  // Opaque even under translucency (a Popup, where nothing blurs behind it)
  property bool solid: false
  // A soft shadow under the box (a RectangularShadow, never a layer: a layer
  // resamples the text inside it). It paints past the box by its blur, so a
  // clipping parent cuts it
  property bool shadowed: false
  // What reads on this tone (`ink.text`, `ink.muted`, ...)
  readonly property StyleInk ink: Style.inkOf(root.tone)
  // What a StyledText inside it inherits
  readonly property StyleInk inkScope: root.ink
  // The zoom its content is drawn at; the zoom walks of the texts inside
  // stop here, as their ink walks do
  readonly property real drawnZoom: TextRender.zoomAt(root.parent)

  // -- Implementation --
  color: {
    switch (root.tone) {
    case "page":
      return root.solid ? Style.surfacePage : Style.fillPage;
    case "sunken":
      return root.solid ? Style.surfaceSunken : Style.fillSunken;
    case "raised":
      return root.solid ? Style.surfaceRaised : Style.fillRaised;
    case "highest":
      return root.solid ? Style.surfaceHighest : Style.fillHighest;
    case "accent":
      return Style.accent;
    case "accentContainer":
      return Style.accentContainer;
    case "accentTint":
      return Style.accentTint;
    case "warningTint":
      return Style.warningTint;
    case "errorTint":
      return Style.errorTint;
    case "success":
      return Style.success;
    case "successContainer":
      return Style.successContainer;
    case "warning":
      return Style.warning;
    case "warningContainer":
      return Style.warningContainer;
    case "error":
      return Style.error;
    case "errorContainer":
      return Style.errorContainer;
    case "info":
      return Style.info;
    case "infoContainer":
      return Style.infoContainer;
    default:
      return root.solid ? Style.surface : Style.fill;
    }
  }
  radius: root.tone === "page" ? Style.radiusOuter : Style.radius
  border.width: root.outlined ? Style.hairline : 0
  border.color: root.tone === "page" || root.tone === "surface" ? Style.borderSubtle : Style.borderStrong

  // Declared first, under the box
  Loader {
    active: root.shadowed
    anchors.fill: parent
    z: -1

    sourceComponent: RectangularShadow {
      anchors.fill: parent
      radius: root.radius
      color: Style.shadowSoft
      blur: Widget.px(16)
    }
  }
}
