pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.content.base

// properties: { color: base00-base0F (or any name `Style.resolve` accepts), label }
Card {
  id: root

  // White or black, whichever reads on the swatch
  readonly property color labelColor: Tone.bestOn(root.color)

  // Both labels where they fit apart, else just the color's name, centred,
  // else none
  readonly property bool bothLabels: root.height >= Appearance.fontSize * 4.5
  readonly property bool nameLabel: root.height >= Appearance.fontSize * 2 && root.width >= Appearance.fontSize * 3

  color: Style.resolve(root.properties.color)
  border.width: Math.max(Appearance.borderWidth, 3)

  component SwatchLabel: StyledText {
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(implicitWidth, root.width - Widget.spacing * 2)
    horizontalAlignment: Text.AlignHCenter
    overflow: "line"
    role: "micro"
    font.weight: Style.weightStrong
    textColor: root.labelColor
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
