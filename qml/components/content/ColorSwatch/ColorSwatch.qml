pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.content.base

// properties: { color: base00-base0F (or any name Theme.resolveColor accepts), label }
Card {
  id: root

  // Whichever of the theme's foreground and background reads on the swatch
  readonly property bool _foregroundIsLight: !Utils.isColorDark(Theme.foreground)
  readonly property color labelColor: Utils.isColorDark(root.color) === root._foregroundIsLight ? Theme.foreground : Theme.background

  // Both labels where they fit apart, else just the color's name, centred,
  // else none
  readonly property bool bothLabels: root.height >= Appearance.fontSize * 4.5
  readonly property bool nameLabel: root.height >= Appearance.fontSize * 2 && root.width >= Appearance.fontSize * 3

  color: Theme.resolveColor(root.properties.color)
  border.width: Math.max(Appearance.borderWidth, 3)

  component SwatchLabel: StyledText {
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(implicitWidth, root.width - Widget.spacing * 2)
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    textColor: root.labelColor
    textSize: Appearance.fontSizeBy(-4)
    font.bold: true
    opacity: 0.8
  }

  SwatchLabel {
    visible: root.bothLabels
    anchors.top: parent.top
    anchors.topMargin: OverlayConfig.cardSpacing / 2
    text: root.properties.label
  }

  SwatchLabel {
    visible: root.nameLabel
    anchors.bottom: root.bothLabels ? parent.bottom : undefined
    anchors.bottomMargin: OverlayConfig.cardSpacing / 2
    anchors.verticalCenter: root.bothLabels ? undefined : parent.verticalCenter
    text: root.properties.color
  }
}
