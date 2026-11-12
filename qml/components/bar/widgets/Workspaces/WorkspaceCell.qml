pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable
import qs.components.methods
import qs.components.bar.look

// One workspace on the bar, in the bar's widget style (BarsConfig.cellColors): a
// filled, tinted or outlined box inside the widget's own; on a bar whose
// widgets have no boxes, straight on the bar, under a line of its color for
// underline. Its label (`labels`) is its number, a dot or nothing; a
// glyph, text (a label of one's own, an icon, text or the icon before
// the text, or a name: a Material Symbols name the font has draws as that
// icon, anything else as text) or app icons show instead
// when given, in that order (CellContents picks one). An urgent one pulses
// from its `look` toward its `mutedLook` by `pulse` (the core's cell() pulse, composed here), with a dot
// at its corner where an app icon would otherwise hide it. A row with a sliding ActiveCellIndicator draws its
// cells twice, the boxes (`part: "background"`) under the indicator and
// the labels (`"content"`) over it. As a segment of the bar's run (the
// widget's Background off) its box takes the bar's widget shape (`shape`)
// and its content keeps clear of its caps (`room`).
Item {
  id: root

  required property var barConfig
  // How its widget's cells draw on this bar or popout
  required property CellLook cellLook
  // BarsConfig.cellColors for its state (CellLook.workspaceColorsOf)
  required property var look
  required property bool isActive
  // Across the bar, and along it (`restLength` when not widened)
  required property real thickness
  required property real length
  property real restLength: length
  property real radius: cellLook.radius
  // Its shape as a segment of the bar's run (BarCells.cellShape), or
  // null: a box filling it, rounded by `radius`
  property var shape: null
  // The room its content keeps clear of its caps along it (BarCells.cellRoom:
  // { lead, trail }), or null
  property var room: null
  // "numbers", "dots" or "none" (dots where a cell would have neither box
  // nor line to show: `none`'s option is hidden there, but the bar's style
  // can change after)
  property string labels: "numbers"
  readonly property bool _dot: labels === "dots" || labels === "none" && !_framed
  property string label: ""
  // A label of one's own or the compositor's name; `textPlain` (a name, or
  // a label that isn't an icon the font has: CellContents.plain) in the
  // text font
  property string text: ""
  property bool textPlain: false
  // An icon before `text` (a label showing both), and whether it's drawn
  // in the text font (CellContents.leadPlain)
  property string leadIcon: ""
  property bool leadPlain: false
  property string iconPath: ""
  // App icons' paths (`iconPath` alone by default), laid out as
  // `iconLayout` says: "largest" (the first alone), "row" (side by side
  // along the bar) or "square" (up to four in a block the cell's size:
  // WorkspaceCells.squareSlots), of which it has room for `iconSlots`
  property var iconPaths: iconPath !== "" ? [iconPath] : []
  property string iconLayout: "largest"
  property int iconSlots: 1
  property string glyph: ""
  // App icons after a short divider at the end of a glyph or text label (a
  // scratchpad with `scratchpadSplit`), `tailLength` along the bar of
  // `length` (WorkspaceCells.splitTail); `tailEdge` the padding after it,
  // `tailShift` how far the label sits off the centre, `dividerAlong` the
  // divider's size along the bar (all CellContents.ofScratchpad's)
  property var tailPaths: []
  property real tailLength: 0
  property real tailEdge: 0
  property real tailShift: 0
  property real dividerAlong: 0
  readonly property bool _tailed: tailPaths.length > 0 && (_shows === "glyph" || _shows === "text")
  readonly property real _shift: _tailed ? tailShift : 0
  // What it shows: "glyph", "text", "icons" or its "labels"
  readonly property string _shows: glyph !== "" ? "glyph" : text !== "" ? "text" : iconPaths.length > 0 ? "icons" : "labels"
  // A window on it asks for attention (its `look` is the urgent one at rest)
  property bool urgent: false
  // Its look pulses (UrgentPulse): from `look` toward `mutedLook` by `pulse`,
  // each frame, not gliding
  property bool pulsing: false
  // Its muted self (set only while it pulses) and how far toward it (0-1)
  property var mutedLook: null
  property real pulse: 0
  // What each part mixes per frame while it pulses: the fields it draws
  // (null: all of them)
  readonly property var _mixKeys: root.part === "content" ? ["content", "back"] : root.part === "background" ? ["fill", "stroke", "indicator", "hover", "gradient"] : null
  // Its look as shown: the pulse mix while pulsing, else `look`
  readonly property var _shown: root.pulsing && root.mutedLook !== null && root.pulse > 0 ? root._mixed() : root.look
  // Its slice of the bar's gradient for the part `look.gradient` names
  // (CellLook.sliceOf), or null
  property var slice: null
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
  // Its box in the look's hover color (`look.hover`; or, with "Fill on
  // hover", filled: its `look` passes it to BarsConfig.cellColors): when
  // hovered, or for a background layer, when its content layer is
  property bool lit: hovered
  readonly property bool _drawsBox: part !== "content"
  readonly property bool _drawsContent: part !== "background"
  // Its box while the indicator stands for it stays at rest under the
  // indicator, unless its tint would show through
  readonly property bool _clearActive: root.isActive && root.indicated && root.cellLook.clearsActive
  // Its look as its box draws it: cleared under the indicator
  readonly property var _drawn: root._clearActive ? root.cellLook.cleared(root._shown) : root._shown

  signal clicked

  // `look` mixed toward `mutedLook` by `pulse`, in the fields this part draws
  function _mixed() {
    const mixed = BarWidgetStyle.mixColors(root.look, root.mutedLook, root.pulse, root._mixKeys);
    return root._mixKeys === null ? mixed : Object.assign({}, root.look, mixed);
  }

  readonly property bool isVertical: barConfig.vertical
  // A box of its own (in a merged run, which draws its box, only where it
  // still draws one: CellLook.boxed); its state shows in a box or a line,
  // without either in its content
  readonly property bool boxed: cellLook.boxed
  readonly property bool _framed: cellLook.framed
  // On the bar, the widget's hit area (BarWidget.hitArea) sits over the
  // cells and takes the hover, so it's asked whether the pointer is in
  // the cell's pointer area (its box as drawn); elsewhere (a popout), that
  // area itself
  property var hitArea: null
  readonly property bool hovered: hitArea ? hitArea.hovers(cellArea) : cellArea.containsMouse

  width: isVertical ? thickness : length
  height: isVertical ? length : thickness

  // Its box (BarCells.cellBox) and the look's line. Lit, in the hover
  // color, unless its look is filled for the hover already ("Fill on
  // hover": the core's cell() `showsHover`)
  LookBox {
    readonly property var _box: BarCells.cellBox(root.barConfig.look, root.shape, root.radius)

    visible: root._drawsBox
    bar: root.barConfig
    outline: _box.outline
    reach: _box.reach
    strokeWidth: _box.strokeWidth
    strokeStyle: _box.strokeStyle
    fill: root.lit && !root.isActive && !root._shown.showsHover ? root._shown.hover : root._drawn.fill
    stroke: root._drawn.stroke
    line: root._drawn.indicator
    fillSlice: !root._clearActive && root._shown.gradient?.part === "fill" ? root.slice : null
    strokeSlice: !root._clearActive && root._shown.gradient?.part === "stroke" ? root.slice : null
    lineSlice: !root._clearActive && root._shown.gradient?.part === "indicator" ? root.slice : null
    animated: root.animated && !root.pulsing
  }

  // What it shows, centred clear of its caps
  Item {
    readonly property real _lead: root.room?.lead ?? 0
    readonly property real _trail: root.room?.trail ?? 0

    anchors.fill: parent
    anchors.leftMargin: root.isVertical ? 0 : _lead
    anchors.rightMargin: root.isVertical ? 0 : _trail
    anchors.topMargin: root.isVertical ? _lead : 0
    anchors.bottomMargin: root.isVertical ? _trail : 0
    visible: root._drawsContent

    // A dot (a pill when widened), smaller inside a box
    Rectangle {
      readonly property real size: Math.max(4, Math.round(root.thickness * (root.boxed ? 0.28 : 0.35)))
      readonly property real along: size + root.length - root.restLength

      anchors.centerIn: parent
      visible: root._dot && root._shows === "labels"
      width: root.isVertical ? size : along
      height: root.isVertical ? along : size
      radius: size / 2
      color: root._shown.content

      ColorGlide on color {
        enabled: root.animated && !root.pulsing
      }
    }

    StyledIcon {
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.isVertical ? 0 : root._shift
      anchors.verticalCenterOffset: root.isVertical ? root._shift : 0
      visible: root._shows === "glyph"
      text: root.glyph
      font.pixelSize: root.barConfig.fontSize * 1.2
      color: root._shown.content
    }

    // A label of one's own or a name: an icon at the glyph's size, text at
    // the number's, with a label's icon before it (`leadIcon`); the two
    // turned along a vertical bar when wider than the cell is thick (the
    // icon then below the text, where it starts)
    Row {
      id: textRow
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.isVertical ? 0 : root._shift
      anchors.verticalCenterOffset: root.isVertical ? root._shift : 0
      visible: root._shows === "text"
      spacing: WorkspaceCells.iconGap(root.thickness)
      rotation: root.isVertical && !textLabel.symbol && textRow.implicitWidth > root.thickness * 0.8 ? -90 : 0
      // What's drawn as words, the two on one band (TextBand: a plain
      // lead and its text share a baseline)
      readonly property string words: (leadLabel.symbol ? "" : root.leadIcon) + (textLabel.symbol ? "" : root.text)

      StyledIcon {
        id: leadLabel
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -_band.offset
        visible: root.leadIcon !== ""
        readonly property bool symbol: leadLabel.isSymbol && !root.leadPlain
        // As words, centred on their letters
        readonly property TextBandPadding _band: TextBandPadding {
          enabled: !leadLabel.symbol
          label: leadLabel
          text: root.leadIcon
          bandText: textRow.words
        }
        topPadding: _band.top
        bottomPadding: _band.bottom

        // An icon stays upright as the text turns
        rotation: leadLabel.symbol && textRow.rotation !== 0 ? 90 : 0
        text: root.leadIcon
        textFamily: leadLabel.symbol ? Appearance.iconFamily : Appearance.fontFamily
        textSize: leadLabel.symbol ? Math.round(root.barConfig.fontSize * 1.2) : root.barConfig.fontSize - 1
        textColor: root._shown.content
        font.bold: !leadLabel.symbol && root.isActive && !root.boxed

        ColorGlide on color {
          enabled: root.animated && !root.pulsing
        }
      }

      StyledIcon {
        id: textLabel
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -_band.offset
        readonly property bool symbol: textLabel.isSymbol && !root.textPlain
        readonly property TextBandPadding _band: TextBandPadding {
          enabled: !textLabel.symbol
          label: textLabel
          text: root.text
          bandText: textRow.words
        }
        topPadding: _band.top
        bottomPadding: _band.bottom

        text: root.text
        textFamily: textLabel.symbol ? Appearance.iconFamily : Appearance.fontFamily
        textSize: textLabel.symbol ? Math.round(root.barConfig.fontSize * 1.2) : root.barConfig.fontSize - 1
        textColor: root._shown.content
        font.bold: !textLabel.symbol && root.isActive && !root.boxed

        ColorGlide on color {
          enabled: root.animated && !root.pulsing
        }
      }
    }

    // The bar's divider, then the app icons, ending the content before its
    // padding (`tailPaths`). Everything centres on the cell's thickness
    Item {
      id: tail

      visible: root._tailed
      x: root.isVertical ? 0 : parent.width - root.tailEdge - width
      y: root.isVertical ? parent.height - root.tailEdge - height : 0
      width: root.isVertical ? root.thickness : root.tailLength
      height: root.isVertical ? root.tailLength : root.thickness

      Grid {
        anchors.right: root.isVertical ? undefined : parent.right
        anchors.bottom: root.isVertical ? parent.bottom : undefined
        flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight
        rows: root.isVertical ? -1 : 1
        columns: root.isVertical ? 1 : -1
        spacing: WorkspaceCells.iconGap(root.thickness)
        verticalItemAlignment: Grid.AlignVCenter
        horizontalItemAlignment: Grid.AlignHCenter

        // A box the cell's whole thickness across the bar, the divider's
        // size along it at its start and the pad after it (less the Grid's
        // spacing, which comes next)
        Item {
          readonly property real _along: root.dividerAlong + root.tailEdge - WorkspaceCells.iconGap(root.thickness)
          width: root.isVertical ? root.thickness : _along
          height: root.isVertical ? _along : root.thickness

          Item {
            width: root.isVertical ? root.thickness : root.dividerAlong
            height: root.isVertical ? root.dividerAlong : root.thickness

            StripDivider {
              anchors.centerIn: parent
              barConfig: root.barConfig
              cell: root.thickness
            }
          }
        }

        Repeater {
          // The most icons a cell shows (appIconsMax's top), each while it has one
          model: 8

          Image {
            required property int index
            visible: index < root.tailPaths.length
            width: WorkspaceCells.iconSize(root.thickness)
            height: width
            sourceSize: Qt.size(64, 64)
            source: root.tailPaths[index] ?? ""
            opacity: root.boxed || root.isActive ? 1 : 0.7
          }
        }
      }
    }

    // App icons alone or in a row, packed in the middle. The slots come
    // from the layout (config), each shown while it has an icon. Only the
    // line's count across is fixed: the Grid counts the other way from the
    // icons shown, so it's only as long as they are (a set count keeps
    // spacing for an empty column, pushing them off centre, and lags the
    // icons' visibility as one comes, warning that it overflows)
    Grid {
      id: iconRow
      readonly property int _shown: Math.max(1, Math.min(root.iconPaths.length, root.iconLayout === "row" ? root.iconSlots : 1))

      anchors.centerIn: parent
      visible: root._shows === "icons" && root.iconLayout !== "square"
      flow: root.isVertical ? Grid.TopToBottom : Grid.LeftToRight
      rows: root.isVertical ? -1 : 1
      columns: root.isVertical ? 1 : -1
      spacing: WorkspaceCells.iconGap(root.thickness)

      Repeater {
        model: root.iconLayout === "square" ? 0 : root.iconLayout === "row" ? root.iconSlots : 1

        Image {
          required property int index
          width: WorkspaceCells.iconSize(root.thickness)
          height: width
          sourceSize: Qt.size(64, 64)
          source: root._shows === "icons" ? (root.iconPaths[index] ?? "") : ""
          visible: index < iconRow._shown && index < root.iconPaths.length
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

    // Centred on its figures
    StyledLabel {
      anchors.centerIn: parent
      visible: root.labels === "numbers" && root._shows === "labels"
      text: root.label
      textColor: root._shown.content
      textSize: root.barConfig.fontSize - 1
      font.bold: root.isActive && !root.boxed

      ColorGlide on color {
        enabled: root.animated && !root.pulsing
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
      color: root._shown.content
    }
  }

  // In its box as drawn: as a segment, back under the cell before and out
  // to a tab's edge
  CellHitArea {
    id: cellArea
    shape: root.shape
    vertical: root.isVertical
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
