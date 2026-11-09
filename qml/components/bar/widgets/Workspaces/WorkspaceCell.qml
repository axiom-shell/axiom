pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable
import qs.components.methods

// One workspace on the bar, in the bar's widget style (BarsConfig.cellColors): a
// filled, tinted or outlined box inside the widget's own; on a bar whose
// widgets have no boxes, straight on the bar, under a line of its color for
// underline. Its label (`labels`) is its number, a dot or nothing; a
// glyph, text (a label of one's own or a name: a Material Symbols name
// draws as that icon, anything else as text) or app icons show instead
// when given, in that order (CellContents picks one). An urgent one fades
// in and out (`pulse`), with a dot at its corner where an app icon would
// otherwise hide it. A row with a sliding ActiveCellIndicator draws its
// cells twice, the boxes (`part: "background"`) under the indicator and
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
  // "numbers", "dots" or "none" (dots where a cell would have neither box
  // nor line to show: `none`'s option is hidden there, but the bar's style
  // can change after)
  property string labels: "numbers"
  readonly property bool _dot: labels === "dots" || labels === "none" && !_framed
  property string label: ""
  // A label of one's own or the compositor's name, the name (`textPlain`)
  // always in the text font
  property string text: ""
  property bool textPlain: false
  property string iconPath: ""
  // App icons' paths (`iconPath` alone by default), laid out as
  // `iconLayout` says: "largest" (the first alone), "row" (side by side
  // along the bar) or "square" (up to four in a block the cell's size:
  // WorkspaceCells.squareSlots), of which it has room for `iconSlots`
  property var iconPaths: iconPath !== "" ? [iconPath] : []
  property string iconLayout: "largest"
  property int iconSlots: 1
  property string glyph: ""
  // What it shows: "glyph", "text", "icons" or its "labels"
  readonly property string _shows: glyph !== "" ? "glyph" : text !== "" ? "text" : iconPaths.length > 0 ? "icons" : "labels"
  // A window on it asks for attention (its `look` is the urgent one)
  property bool urgent: false
  // The urgent fade's opacity (UrgentPulse.value), 1 while still
  property real pulse: 1
  // The corner dot an urgent cell with neither box nor line shows over
  // an app icon
  property color urgentColor: "transparent"
  readonly property real _pulse: urgent && !isActive ? pulse : 1
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
  // `solidBoxes`: a filled box whatever the bar's style (`look` is the
  // solid one)
  property bool solid: false
  readonly property bool boxed: barConfig.widgetBoxed || solid
  // Its state shows in a box or a line; without either, in its content
  readonly property bool _framed: boxed || barConfig.widgetStyle === "underline"
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
    opacity: root._pulse
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
    opacity: root._pulse
    color: root._clearActive ? Qt.alpha(root.look.indicator, 0) : root.look.indicator

    ColorGlide on color {
      enabled: root.animated
    }
  }

  // What it shows, fading with an urgent one's pulse where nothing else
  // carries its state
  Item {
    anchors.fill: parent
    visible: root._drawsContent
    opacity: root._framed ? 1 : root._pulse

    // A dot (a pill when widened), smaller inside a box
    Rectangle {
      readonly property real size: Math.max(4, Math.round(root.thickness * (root.boxed ? 0.28 : 0.35)))
      readonly property real along: size + root.length - root.restLength

      anchors.centerIn: parent
      visible: root._dot && root._shows === "labels"
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
      visible: root._shows === "glyph"
      text: root.glyph
      font.pixelSize: root.barConfig.fontSize * 1.2
      color: root.look.content
    }

    // A label of one's own or a name: an icon at the glyph's size, text at
    // the number's (turned along a vertical bar when wider than the cell is
    // thick)
    StyledIcon {
      id: textLabel
      anchors.centerIn: parent
      visible: root._shows === "text"
      readonly property bool symbol: textLabel.isSymbol && !root.textPlain

      text: root.text
      textFamily: textLabel.symbol ? Appearance.iconFamily : Appearance.fontFamily
      textSize: textLabel.symbol ? Math.round(root.barConfig.fontSize * 1.2) : root.barConfig.fontSize - 1
      textColor: root.look.content
      font.bold: !textLabel.symbol && root.isActive && !root.boxed
      isVertical: root.isVertical && !textLabel.symbol && textLabel.implicitWidth > root.thickness * 0.8

      ColorGlide on color {
        enabled: root.animated
      }
    }

    // App icons alone or in a row, packed in the middle. The slots come
    // from the layout (config), each shown while it has an icon
    Grid {
      anchors.centerIn: parent
      visible: root._shows === "icons" && root.iconLayout !== "square"
      flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight
      rows: root.isVertical ? Math.max(1, root.iconSlots) : 1
      columns: root.isVertical ? 1 : Math.max(1, root.iconSlots)
      spacing: WorkspaceCells.iconGap(root.thickness)

      Repeater {
        model: root.iconLayout === "square" ? 0 : root.iconLayout === "row" ? root.iconSlots : 1

        Image {
          required property int index
          width: WorkspaceCells.iconSize(root.thickness)
          height: width
          sourceSize: Qt.size(64, 64)
          source: root._shows === "icons" ? (root.iconPaths[index] ?? "") : ""
          visible: index < root.iconPaths.length
          opacity: root.boxed || root.isActive ? 1 : 0.7
        }
      }
    }

    // Up to four in a block the cell's own size, in its middle
    Item {
      anchors.centerIn: parent
      visible: root._shows === "icons" && root.iconLayout === "square"
      width: root.thickness
      height: root.thickness

      Repeater {
        model: root.iconLayout === "square" ? 4 : 0

        Image {
          required property int index
          readonly property var slot: WorkspaceCells.squareSlots(root.iconPaths.length)[index] ?? null

          visible: slot !== null
          x: slot ? root.thickness * slot.x - width / 2 : 0
          y: slot ? root.thickness * slot.y - height / 2 : 0
          width: root.thickness * (slot?.size ?? 0)
          height: width
          sourceSize: Qt.size(64, 64)
          source: slot ? root.iconPaths[index] : ""
          opacity: root.boxed || root.isActive ? 1 : 0.7
        }
      }
    }

    StyledText {
      anchors.centerIn: parent
      visible: root.labels === "numbers" && root._shows === "labels"
      text: root.label
      textColor: root.look.content
      textSize: root.barConfig.fontSize - 1
      font.bold: root.isActive && !root.boxed

      ColorGlide on color {
        enabled: root.animated
      }
    }

    // Urgent, where an app icon is all it shows on the bar
    Rectangle {
      readonly property real size: Math.max(4, Math.round(root.thickness * 0.22))

      visible: root.urgent && !root.isActive && !root._framed && root._shows === "icons"
      x: parent.width - size
      y: 0
      width: size
      height: size
      radius: size / 2
      color: root.urgentColor
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
