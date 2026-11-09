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

  // Its glyphs one per line, laid along the bar: stacked on a vertical
  // one, side by side on a horizontal one (not joined by spaces: the icon
  // font's space is a whole icon wide)
  property string icon: ""
  property string text: ""
  // Text.PlainText for text from outside (an event's title), which
  // mustn't render as styled text or load images
  property int textFormat: Text.AutoText
  property real textScale: 1.0
  property real iconScale: 1.0
  property bool showText: true
  property bool showIcon: true
  property real spacing: 0
  // Between the icon's glyphs side by side (its lines on a horizontal bar)
  property real iconSpacing: 0
  property color foregroundColor: Theme.background
  property color iconColor: foregroundColor
  property int fontSize: 0
  // The label's digits are of equal width (tabular figures), and it takes
  // the room of its text with every digit a 0, never less than
  // `minimumText`'s (its widest usual value, "00%" for a percent: 100%
  // may widen it), centred in that room: a ticking or sampled value never
  // resizes the widget, or the bar around it
  property string minimumText: ""
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
  // Where the icon is drawn, in the widget's coordinates (for a badge on
  // it); empty with no icon
  readonly property rect iconRect: _hasIcon ? Qt.rect(run.x + iconLabel.x, run.y + iconLabel.y, iconLabel.width, iconLabel.height) : Qt.rect(0, 0, 0, 0)
  // The gap between its icon part (the lead graphic and the icon) and its
  // label when they're set apart (a split bar's widget), instead of
  // `spacing`; -1 for none
  property real splitRoom: -1
  // It shows an icon part and a label apart: it has a splitRoom, an icon
  // or a lead graphic, and a label
  readonly property bool splits: splitRoom >= 0 && _hasText && (_hasIcon || _leadRoom > 0)
  readonly property real _splitExtra: splits ? splitRoom - spacing : 0
  // Where the middle of the gap between the two parts is along the bar,
  // in the widget's coordinates (-1 when it doesn't split)
  readonly property real splitAt: splits ? (isVertical ? run.y : run.x) + textSlot.start - splitRoom / 2 : -1
  // What the icon part holds (the lead graphic and the icon) in the
  // widget's coordinates: along the bar from its start to the gap, across
  // it the icon's size round its middle (the run's, with none)
  readonly property rect splitPart: {
    if (!splits)
      return Qt.rect(0, 0, 0, 0);
    const along = textSlot.start - splitRoom;
    const size = fontSize * iconScale;
    const middle = _hasIcon ? (isVertical ? iconLabel.x + iconLabel.width / 2 : iconLabel.y + iconLabel.height / 2) : (isVertical ? run.width : run.height) / 2;
    return isVertical ? Qt.rect(run.x + middle - size / 2, run.y, size, along) : Qt.rect(run.x, run.y + middle - size / 2, along, size);
  }
  readonly property real _textLength: isVertical && uprightLabel ? textLabel.implicitHeight : Math.ceil(Math.max(textLabel.implicitWidth, steadyMetrics.advanceWidth, minimumMetrics.advanceWidth))
  readonly property real _naturalLength: _leadRoom + iconLength + _gap + _splitExtra + (_hasText ? _textLength : 0)

  readonly property real _padding: hidden ? 0 : padding
  // Down to its icon, with a lead graphic drawn before it: the least an
  // elastic widget (Media, Window) is squeezed to
  readonly property real minimumSize: _iconStart + iconLength + _padding * 2

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

    // One Text per line, a column on a vertical bar and a row on a
    // horizontal one, each glyph centred in its cell rather than on the
    // widest line's width
    Grid {
      id: iconLabel
      columns: root.isVertical ? 1 : root._iconLines.length
      columnSpacing: root.iconSpacing
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter
      visible: root._hasIcon
      x: root.isVertical ? Math.round((run.width - width) / 2) : root._iconStart
      y: root.isVertical ? root._iconStart : Math.round((run.height - height) / 2)

      // Modelled by line count, so a changing icon (battery level, volume)
      // updates the text instead of recreating the delegates
      Repeater {
        model: root._iconLines.length

        StyledIcon {
          required property int index
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
      readonly property real start: root._leadRoom + root.iconLength + root._gap + root._splitExtra
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
        // Along the bar, centred in its room (wider than the text when its
        // minimum or its zeros measure wider), on a whole pixel; given less,
        // it fills the room and elides
        readonly property real _alongRoom: root._turned ? textSlot.height : textSlot.width
        x: root._turned ? (textSlot.width - width) / 2 : root.isVertical ? 0 : Math.round((textSlot.width - width) / 2)
        y: root._turned ? (textSlot.height - height) / 2 : root.isVertical ? 0 : Math.round(root.iconMiddle - baselineOffset + _figure.height / 2)
        width: root.isVertical && root.uprightLabel ? textSlot.width : Math.min(Math.ceil(implicitWidth), _alongRoom)
        rotation: root._turned ? -90 : 0
        horizontalAlignment: root.isVertical && root.uprightLabel ? Text.AlignHCenter : Text.AlignLeft
        color: root.foregroundColor
        text: root.displayText
        textFormat: root.textFormat
        elide: root.isVertical && root.uprightLabel ? Text.ElideNone : Text.ElideRight
        font.family: Appearance.fontFamily
        font.pixelSize: root.fontSize * root.textScale
        font.features: {
          "tnum": 1
        }

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

  // The label as it reads (styled text's tags left out), and its minimum,
  // with their digits as zeros
  TextMetrics {
    id: steadyMetrics
    font: textLabel.font
    text: (root.textFormat === Text.PlainText ? root.displayText : root.displayText.replace(/<[^>]*>/g, "")).replace(/[0-9]/g, "0")
  }
  TextMetrics {
    id: minimumMetrics
    font: textLabel.font
    text: root._hasText ? root.minimumText.replace(/[0-9]/g, "0") : ""
  }
}
