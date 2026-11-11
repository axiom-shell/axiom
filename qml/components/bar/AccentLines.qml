pragma ComponentBehavior: Bound

import QtQuick

import qs.config
import qs.components.methods

// A bar's accent line (its look's accentLine: { side, color, fade, width })
// along its inner or outer edge, in from its outer edge inside whatever
// stroke is there (BarEnds.accentInset): along a plain bar, or along each
// pill or island. Fills its bar's container (`bar`, a BarContainer), whose
// sizes, ends and pills it reads.
Item {
  id: root

  required property BarContainer bar
  readonly property var barConfig: root.bar.barConfig
  // The look's line, or null for none
  readonly property var accentLine: root.barConfig.look.accentLine
  readonly property real inset: BarEnds.accentInset(root.barConfig, Appearance.borderWidth)
  readonly property bool pills: root.bar.pills
  readonly property bool islands: root.bar.islands

  // A line along the bar (`bar`), from its color fading into another
  // along it, `inset` in from its outer edge. Inline components can't see
  // this file's ids, hence `bar`, `accent` and `inset`. Where an outer
  // bar's popout lies over it (coveredSpans) it gives way, as the islands
  // and sections do: on a pill bar not, its pills merging with the popout.
  component AccentLine: Rectangle {
    id: line
    required property BarContainer bar
    required property var accent
    required property real inset
    opacity: !line.bar.pills && line.bar.covers(line.start, line.start + line.length) ? 0 : 1
    Behavior on opacity {
      NumberAnimation {
        duration: Appearance.animFast
        easing.type: Appearance.easing
      }
    }
    // Along the bar
    required property real start
    required property real length

    readonly property bool vertical: line.bar.isVertical
    readonly property real thickness: line.accent?.width ?? 0
    readonly property bool far: line.bar.barConfig.right || line.bar.barConfig.bottom
    readonly property real across: line.far ? (line.vertical ? line.bar.width : line.bar.height) - line.inset - line.thickness : line.inset
    readonly property color from: line.accent ? line.bar.barConfig.palette.accentLine.from : "transparent"

    x: line.vertical ? line.across : line.start
    y: line.vertical ? line.start : line.across
    width: line.vertical ? line.thickness : line.length
    height: line.vertical ? line.length : line.thickness
    gradient: Gradient {
      orientation: line.vertical ? Gradient.Vertical : Gradient.Horizontal
      GradientStop {
        position: 0
        color: line.from
      }
      GradientStop {
        position: 1
        color: line.accent ? line.bar.barConfig.palette.accentLine.to : "transparent"
      }
    }
  }

  // Along a plain bar: its whole length, or clear of the border's sides
  // inside the border and of a bar it makes way for
  AccentLine {
    visible: root.accentLine !== null && !root.pills && !root.islands
    bar: root.bar
    accent: root.accentLine
    inset: root.inset
    start: root.barConfig.insideBorder || root.bar.ends.start.held ? root.bar.endMargins[0] : 0
    length: root.bar.length - start - (root.barConfig.insideBorder || root.bar.ends.end.held ? root.bar.endMargins[1] : 0)
  }

  // Along each pill, clear of its rounded corners on the inner side
  Repeater {
    model: root.accentLine !== null && (root.pills || root.islands) ? root.bar.pillRects.length : 0

    AccentLine {
      required property int index
      readonly property var rect: root.bar.pillRects[index] ?? {
        "start": 0,
        "length": 0
      }
      // Pills only round their inner side; islands both
      readonly property real corner: root.islands ? Appearance.borderRadius : root.accentLine.side === "inner" ? root.bar.pillRadii.corner : 0

      bar: root.bar
      accent: root.accentLine
      inset: root.inset
      start: rect.start + (rect.joinStart ? 0 : corner)
      length: Math.max(0, rect.length - (rect.joinStart ? 0 : corner) - (rect.joinEnd ? 0 : corner))
    }
  }
}
