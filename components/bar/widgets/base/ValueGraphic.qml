pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable
import qs.components.content.parts

// The graphic of a bar widget's display style (docs/dev/bar/display-styles.md):
// ring, fill, segments, sparkline, ticker or stacked, the length along the
// bar it wants in `length`. Placed by ValueStyleWidget in its lead slot, or
// by a widget drawing several values (SystemStats) once per value. Sizes
// from the bar's font, as a bar's pieces are. Other styles draw nothing.
Item {
  id: root

  property string style: "label"
  // 0-1, for ring, fill and segments
  property real ratio: 0
  // Oldest first, for the sparkline, between graphMin and graphMax
  property var history: []
  property real graphMin: 0
  property real graphMax: 1
  // The ticker's text, and stacked's two lines
  property string text: ""
  property string subtext: ""
  // Stacked's widest value (IconTextWidget's minimumText): the value never
  // takes less room, so a changing one doesn't resize the widget
  property string minimumText: ""
  property int segmentCount: 5
  // The graphic's length along the bar; 0 picks one
  property real preferredLength: 0
  property bool vertical: false
  property real crossSize: 0
  property int fontSize: Appearance.fontSize
  property color color: "white"
  property color textColor: "white"
  // Across a bar, where the icon beside it has its middle (IconTextWidget's
  // iconMiddle), in this item's coordinates; below 0, its own middle
  property real middle: -1
  readonly property color trackColor: Qt.alpha(root.textColor, 0.2)

  // Whether this style draws anything here
  readonly property bool drawn: ["ring", "fill", "segments", "sparkline", "ticker", "stacked"].includes(root.style)
  // Ticker and stacked sit where a label would, after the icon
  readonly property bool afterIcon: ["ticker", "stacked"].includes(root.style)
  readonly property real length: {
    switch (root.style) {
    case "ring":
      return root.crossSize * 0.62;
    case "fill":
    case "segments":
    case "sparkline":
      return root.preferredLength > 0 ? root.preferredLength : root.fontSize * (root.vertical ? 2.5 : 4);
    case "ticker":
      // As long as its text, up to its room: it scrolls past that
      return Math.min((loader.item as Item)?.implicitWidth ?? 0, root.preferredLength > 0 ? root.preferredLength : root.fontSize * 12);
    case "stacked":
      return (loader.item as Item)?.implicitWidth ?? 0;
    }
    return 0;
  }

  // Only the shown one is built
  Loader {
    id: loader
    anchors.fill: parent
    sourceComponent: ({
        "ring": ring,
        "fill": fill,
        "segments": segments,
        "sparkline": sparkline,
        "ticker": ticker,
        "stacked": stacked
      })[root.style] ?? null
  }

  Component {
    id: ring
    Item {
      id: ringBox
      // On whole pixels, centred exactly on the icon's middle beside it (on
      // a whole or a half pixel, as the icon snapped): its side's parity
      // follows. Centred by anchors, it was drawn a pixel off the icon
      readonly property real centre: root.middle >= 0 && !root.vertical ? root.middle : height / 2
      readonly property int side: {
        const side = Math.floor(Math.min(width, height));
        return (side % 2 === 0) === Number.isInteger(centre) ? side : side - 1;
      }

      PercentageCircle {
        x: Math.round((ringBox.width - ringBox.side) / 2)
        y: Math.round(ringBox.centre - ringBox.side / 2)
        width: ringBox.side
        height: ringBox.side
        percentage: root.ratio * 100
        thickness: Math.max(2, width * 0.16)
        trackColor: root.trackColor
        fillColor: root.color
        iconText: ""
      }
    }
  }

  Component {
    id: fill
    LevelMeter {
      share: root.ratio
      vertical: root.vertical
      thickness: Math.max(3, root.fontSize * 0.35)
      trackColor: root.trackColor
      fillColor: root.color
    }
  }

  Component {
    id: segments
    SegmentMeter {
      count: root.segmentCount
      share: root.ratio
      vertical: root.vertical
      across: root.fontSize * 0.7
      gap: 2
      cornerRadius: 2
      litColor: root.color
      offColor: root.trackColor
    }
  }

  Component {
    id: sparkline
    Item {
      Sparkline {
        anchors.fill: parent
        anchors.topMargin: root.crossSize * 0.2
        anchors.bottomMargin: root.crossSize * 0.2
        values: root.history
        minValue: root.graphMin
        maxValue: root.graphMax
        lineColor: root.color
        showBaseline: false
      }
    }
  }

  // Ticker: the text scrolling when it's longer than its room, turned
  // along a vertical bar as a label is
  Component {
    id: ticker
    Item {
      id: tickerBox
      // Its length along the bar
      implicitWidth: tickerText.implicitWidth
      clip: true

      Item {
        id: strip
        anchors.centerIn: parent
        width: root.vertical ? tickerBox.height : tickerBox.width
        height: root.vertical ? tickerBox.width : tickerBox.height
        rotation: root.vertical ? -90 : 0

        Text {
          id: tickerText
          anchors.verticalCenter: parent.verticalCenter
          text: root.text
          color: root.textColor
          font.family: Appearance.fontFamily
          font.pixelSize: root.fontSize
          font.features: {
            "tnum": 1
          }
          readonly property real overflow: Math.max(0, implicitWidth - strip.width)
          x: 0

          // The pauses and the scroll's speed are behaviour, not motion.
          // Stopped (the text now fits), it's back at the start
          SequentialAnimation on x {
            running: tickerText.overflow > 0 && Appearance.animations
            loops: Animation.Infinite
            onRunningChanged: {
              if (!running)
                tickerText.x = 0;
            }
            PauseAnimation {
              duration: 1500 // behaviour timing: the ticker rests at each end
            }
            NumberAnimation {
              from: 0
              to: -tickerText.overflow
              duration: tickerText.overflow * 30
            }
            PauseAnimation {
              duration: 1500 // behaviour timing: the ticker rests at each end
            }
            NumberAnimation {
              from: -tickerText.overflow
              to: 0
              duration: Appearance.animSlow
              easing.type: Appearance.easing
            }
          }
        }
      }
    }
  }

  // Stacked: the value over its caption
  Component {
    id: stacked
    Item {
      implicitWidth: Math.ceil(Math.max(stack.implicitWidth, valueMetrics.advanceWidth))

      // The room of the longer of the value and its minimum, digits as zeros
      TextMetrics {
        id: valueMetrics
        font: value.font
        text: (root.minimumText.length > root.text.length ? root.minimumText : root.text).replace(/[0-9]/g, "0")
      }

      Column {
        id: stack
        anchors.centerIn: parent
        spacing: 0

        Text {
          id: value
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.text
          color: root.textColor
          font.family: Appearance.fontFamily
          font.pixelSize: root.fontSize * 0.8
          font.bold: true
          font.features: {
            "tnum": 1
          }
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: text !== ""
          text: root.subtext
          color: Qt.alpha(root.textColor, 0.7)
          font.family: Appearance.fontFamily
          font.pixelSize: root.fontSize * 0.6
        }
      }
    }
  }
}
