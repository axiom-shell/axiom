pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.components.reusable

// An icon followed by a label, laid along the bar's main axis (the label is
// rotated on a vertical bar, or upright under the icon with uprightLabel).
// The label's figures are centred on the icon's middle, on whole pixels. Reports the size it needs to show everything
// as its implicit size; given less, the label elides to fit, so its length
// is decided by the bar layout rather than by character counts.
BaseWidget {
  id: root

  property string icon: ""
  property string text: ""
  property real textScale: 1.0
  property real iconScale: 1.0
  property bool showText: true
  property bool showIcon: true
  property real spacing: Widget.spacing * 1.5
  property color foregroundColor: Theme.background
  property color iconColor: foregroundColor
  property int fontSize: Appearance.fontSize
  // Digits of equal width (tabular figures), the label taking the room of
  // its text with every digit a 0: a ticking time keeps its size, changing
  // only when it gains or drops a digit (passing an hour)
  property bool steadyDigits: false
  // Draws nothing and takes no room, padding included (a widget with
  // nothing to show). Not `visible: false`, which would still be measured.
  property bool hidden: false
  // On a vertical bar, the label upright under the icon instead of turned
  // along the bar (SystemStats' small values)
  property bool uprightLabel: false
  readonly property bool _turned: isVertical && !uprightLabel

  readonly property bool _hasIcon: !hidden && showIcon && icon !== ""
  readonly property var _iconLines: icon.split("\n")
  readonly property string displayText: !hidden && showText ? (text || "—") : ""
  readonly property bool _hasText: displayText !== ""
  readonly property real _gap: _hasIcon && _hasText ? spacing : 0
  // Room along the main axis for a graphic the widget draws before the
  // icon (a custom widget's ring or meter) in `lead`, its first child
  property real leadLength: 0
  readonly property real _leadRoom: hidden || leadLength <= 0 ? 0 : leadLength + (_hasIcon || _hasText ? spacing : 0)
  // Where that graphic goes: the run's start, leadLength long, across the
  // bar's whole cross size
  readonly property alias lead: leadSlot
  // The graphic after the icon instead, where a label would be (a custom
  // widget's ticker or stacked text)
  property bool leadAfterIcon: false
  readonly property real _leadStart: leadAfterIcon ? iconLength + (_hasIcon ? spacing : 0) : 0
  readonly property real _iconStart: leadAfterIcon ? 0 : _leadRoom

  // Across a bar, where the icon's middle is (the run's, with none): what
  // the label's figures and a lead graphic centre on, in the lead slot's
  // coordinates as in the run's
  readonly property real iconMiddle: _hasIcon ? iconLabel.y + iconLabel.height / 2 : run.height / 2

  // Icon footprint along the main axis; the label's is its (unrotated) width
  readonly property real iconLength: _hasIcon ? (isVertical ? iconLabel.implicitHeight : iconLabel.implicitWidth) : 0
  readonly property real _textLength: isVertical && uprightLabel ? textLabel.implicitHeight : steadyDigits ? Math.max(textLabel.implicitWidth, Math.ceil(steadyMetrics.advanceWidth)) : textLabel.implicitWidth
  readonly property real _naturalLength: _leadRoom + iconLength + _gap + (_hasText ? _textLength : 0)

  readonly property real _padding: hidden ? 0 : padding

  implicitWidth: isVertical ? root.crossSize : _naturalLength + _padding * 2
  implicitHeight: isVertical ? _naturalLength + _padding * 2 : root.crossSize

  // Centered run of icon + label, at most the space inside the padding
  Item {
    id: run
    anchors.centerIn: parent
    readonly property real available: (root.isVertical ? root.height : root.width) - root.padding * 2
    readonly property real length: Math.max(0, Math.min(root._naturalLength, available))
    width: root.isVertical ? root.width : length
    height: root.isVertical ? length : root.height

    Item {
      id: leadSlot
      visible: root._leadRoom > 0
      x: root.isVertical ? 0 : root._leadStart
      y: root.isVertical ? root._leadStart : 0
      width: root.isVertical ? run.width : root.leadLength
      height: root.isVertical ? root.leadLength : run.height
    }

    // One Text per line, so stacked glyphs (a multi-line icon on a vertical
    // bar) each centre on their own width rather than the widest line's
    Column {
      id: iconLabel
      visible: root._hasIcon
      x: root.isVertical ? Math.round((run.width - width) / 2) : root._iconStart
      y: root.isVertical ? root._iconStart : Math.round((run.height - height) / 2)

      // Modelled by line count, so a changing icon (battery level, volume)
      // updates the text instead of recreating the delegates
      Repeater {
        model: root._iconLines.length

        StyledIcon {
          required property int index
          x: Math.round((iconLabel.width - width) / 2)
          textColor: root.iconColor
          text: root._iconLines[index] ?? ""
          textSize: root.fontSize * root.iconScale

          ColorGlide on color {}
        }
      }
    }

    // Space left for the label along the main axis
    Item {
      id: textSlot
      visible: root._hasText
      readonly property real start: root._leadRoom + root.iconLength + root._gap
      x: root.isVertical ? 0 : start
      y: root.isVertical ? start : 0
      width: root.isVertical ? run.width : Math.max(0, run.length - start)
      height: root.isVertical ? Math.max(0, run.length - start) : run.height

      Text {
        id: textLabel
        // Across a bar, its figures (a digit's height) centred where the
        // icon's middle is (the run's, with none) on a whole pixel: centred
        // as a box, a label sits high, its box holding the descent
        readonly property rect _figure: figureMetrics.tightBoundingRect
        x: root._turned ? (textSlot.width - width) / 2 : 0
        y: root._turned ? (textSlot.height - height) / 2 : root.isVertical ? 0 : Math.round(root.iconMiddle - baselineOffset + _figure.height / 2)
        width: root._turned ? textSlot.height : textSlot.width
        rotation: root._turned ? -90 : 0
        horizontalAlignment: root.isVertical && root.uprightLabel ? Text.AlignHCenter : Text.AlignLeft
        color: root.foregroundColor
        text: root.displayText
        elide: root.isVertical && root.uprightLabel ? Text.ElideNone : Text.ElideRight
        font.family: Appearance.fontFamily
        font.pixelSize: root.fontSize * root.textScale
        font.features: root.steadyDigits ? ({
            "tnum": 1
          }) : ({})

        ColorGlide on color {}
      }
    }
  }

  // A digit's ink, measured again with the font (FontMetrics'
  // tightBoundingRect() is a call, which a binding never re-runs)
  TextMetrics {
    id: figureMetrics
    font: textLabel.font
    text: "0"
  }

  // The label with its digits as zeros, for steadyDigits
  TextMetrics {
    id: steadyMetrics
    font: textLabel.font
    text: root.steadyDigits ? root.displayText.replace(/[0-9]/g, "0") : ""
  }
}
