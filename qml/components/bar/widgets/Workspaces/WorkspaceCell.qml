pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// One workspace on the bar, in the bar's widget style (BarsConfig.cellColors): a
// filled, tinted or outlined box inside the widget's own; on a bar whose
// widgets have no boxes, its number (or a dot) straight on the bar, under a
// line of its color for underline. Shows an app icon or a glyph instead of
// the label when given one. A row with a sliding ActiveCellIndicator draws
// its cells twice, the boxes (`part: "background"`) under the indicator and
// the labels (`"content"`) over it.
Item {
  id: root

  required property var barConfig
  // BarsConfig.cellColors for its state
  required property var look
  required property bool isActive
  // Across the bar, and along it (`restLength` when not widened)
  required property real thickness
  required property real length
  property real restLength: length
  property real radius: 0
  // "numbers" or "dots"
  property string labels: "numbers"
  property string label: ""
  property string iconPath: ""
  property string glyph: ""
  property bool clickable: true
  // Off until its inputs have settled (a popout's payload lands after
  // creation), so it doesn't animate from fallbacks
  property bool animated: true
  // Its box and underline while active are drawn by the row's sliding
  // ActiveCellIndicator instead (a "background" part's)
  property bool indicated: false
  // "all", or only its box and underline ("background") or its label, dot
  // or icon and pointer area ("content")
  property string part: "all"
  // Its box in the hover color: when hovered, or for a background layer,
  // when its content layer is
  property bool lit: hovered
  // Its box while lit (BarsConfig.cellHoverColor)
  property color hoverColor: Theme.backgroundHighlight
  readonly property bool _drawsBox: part !== "content"
  readonly property bool _drawsContent: part !== "background"
  // Its box while the indicator stands for it stays at rest under the
  // indicator, unless its tint would show through
  readonly property bool _clearActive: root.isActive && root.indicated && root.barConfig.widgetStyle === "tinted"

  signal clicked

  readonly property bool isVertical: barConfig.vertical
  readonly property bool boxed: barConfig.widgetBoxed
  // On the bar, the widget's hit area (BarWidget.hitArea) sits over the
  // cells and takes the hover, so it's asked; elsewhere (a popout), the
  // cell's own pointer area
  property var hitArea: null
  readonly property bool hovered: hitArea ? hitArea.hovers(root) : cellArea.containsMouse

  width: isVertical ? thickness : length
  height: isVertical ? length : thickness

  Rectangle {
    anchors.fill: parent
    visible: root._drawsBox
    radius: root.radius
    color: root.lit && !root.isActive ? root.hoverColor : root._clearActive ? Qt.alpha(root.look.fill, 0) : root.look.fill
    border.color: root._clearActive ? Qt.alpha(root.look.stroke, 0) : root.look.stroke
    border.width: root.barConfig.widgetStyle === "outline" ? root.barConfig.outlineWidth : 0

    ColorGlide on color {
      enabled: root.animated
    }
    ColorGlide on border.color {
      enabled: root.animated
    }
  }

  // Underline: along the side the bar's widget lines take
  CellUnderline {
    barConfig: root.barConfig
    visible: root._drawsBox && root.barConfig.widgetStyle === "underline"
    color: root._clearActive ? Qt.alpha(root.look.indicator, 0) : root.look.indicator

    ColorGlide on color {
      enabled: root.animated
    }
  }

  // A dot (a pill when widened) for a cell with no box of its own to show
  Rectangle {
    readonly property real size: Math.max(4, Math.round(root.thickness * 0.35))
    readonly property real along: size + root.length - root.restLength

    anchors.centerIn: parent
    visible: root._drawsContent && !root.boxed && root.labels === "dots" && root.iconPath === "" && root.glyph === ""
    width: root.isVertical ? size : along
    height: root.isVertical ? along : size
    radius: size / 2
    color: root.look.content

    ColorGlide on color {
      enabled: root.animated
    }
  }

  StyledIcon {
    anchors.centerIn: parent
    visible: root._drawsContent && root.glyph !== ""
    text: root.glyph
    font.pixelSize: root.barConfig.fontSize * 1.2
    color: root.look.content
  }

  Image {
    anchors.centerIn: parent
    width: root.thickness * 0.65
    height: width
    sourceSize: Qt.size(64, 64)
    source: root.glyph === "" ? root.iconPath : ""
    visible: root._drawsContent && root.glyph === "" && root.iconPath !== ""
    opacity: root.boxed || root.isActive ? 1 : 0.7
  }

  StyledText {
    anchors.centerIn: parent
    visible: root._drawsContent && root.labels === "numbers" && root.glyph === "" && root.iconPath === ""
    text: root.label
    textColor: root.look.content
    textSize: root.barConfig.fontSize - 1
    font.bold: root.isActive && !root.boxed

    ColorGlide on color {
      enabled: root.animated
    }
  }

  MouseArea {
    id: cellArea
    anchors.fill: parent
    enabled: root.clickable && root._drawsContent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  // As the row's ActiveCellIndicator slides, so a widened active cell
  // grows and shrinks under it
  Glide on width {
    enabled: root.animated
    duration: Appearance.animNormal
  }
  Glide on height {
    enabled: root.animated
    duration: Appearance.animNormal
  }
}
