pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.services.system
import qs.components.methods
import qs.components.content.base

// A clock as large as its slot allows, in a `style`: "digital" (the time
// in one line, the seconds and AM/PM small beside it), "stacked" (the
// hours over the minutes, the minutes in the accent color) or "analog" (a
// face with hands, the second hand in the accent color). The date and a
// `label` go under it. A `timezone` shows another zone's time
// (TimeZoneManager), the system's until its offset is read.
// properties: { style, use24Hour, showSeconds, showDate, timezone, label,
// color, accentColor }
Card {
  id: root

  readonly property string style: root.properties.style
  readonly property bool use24Hour: root.properties.use24Hour
  readonly property bool showSeconds: root.properties.showSeconds
  readonly property string timezone: root.properties.timezone
  readonly property color textColor: root.properties.color ? Theme.resolveColor(root.properties.color) : Theme.foreground
  readonly property color accentColor: root.properties.accentColor ? Theme.resolveColor(root.properties.accentColor) : Theme.accent

  onTimezoneChanged: TimeZoneManager.acquire(root, root.timezone)
  Component.onCompleted: TimeZoneManager.acquire(root, root.timezone)
  Component.onDestruction: TimeZoneManager.release(root)

  SystemClock {
    id: clock
    precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
  }

  // The time shown, in the clock's zone
  readonly property date now: TimeZones.shift(clock.date, TimeZoneManager.offsetOf(root.timezone))
  readonly property string hours: I18n.formatDate(root.now, root.use24Hour ? "HH" : "h")
  readonly property string minutes: I18n.formatDate(root.now, "mm")
  readonly property string seconds: root.showSeconds ? I18n.formatDate(root.now, "ss") : ""
  readonly property string meridiem: root.use24Hour ? "" : I18n.meridiem(root.now)

  // The lines under the clock: the date (shorter where it's narrow) and
  // the label
  readonly property string dateText: root.properties.showDate ? I18n.formatDate(root.now, I18n.dateFormat(root.innerWidth < Appearance.fontSize * 14 ? "shortDate" : "longDate")) : ""
  readonly property string label: root.properties.label
  readonly property int captionCount: (root.dateText !== "" ? 1 : 0) + (root.label !== "" ? 1 : 0)
  readonly property real captionSize: Math.max(Appearance.fontSizeBy(-2), Math.min(Appearance.fontSize * 1.6, root.innerHeight / 12))
  readonly property real spacing: Widget.spacing / 2
  readonly property real captionsHeight: root.captionCount * (root.captionSize * root.lineRatio + root.spacing)

  // The room the clock itself has
  readonly property real faceWidth: Math.max(0, root.innerWidth)
  readonly property real faceHeight: Math.max(0, root.innerHeight - root.captionsHeight)

  // Measured at 100 px, then scaled to the room
  component Metrics: TextMetrics {
    font.family: Appearance.fontFamily
    font.pixelSize: 100 // fixed px: a measuring font, scaled to the room
    font.bold: true
    font.features: {
      "tnum": 1
    }
  }

  // The font's digits as parts of their size: how tall they are (cap
  // height), and its line
  Metrics {
    id: digitMetrics
    text: "0123456789"
  }
  readonly property real capRatio: Math.max(0.5, digitMetrics.tightBoundingRect.height / 100)
  readonly property real lineRatio: Math.max(1, digitMetrics.height / 100)

  // Large digits: same-width, so the clock doesn't shift as it ticks
  component Digits: Text {
    color: root.textColor
    font.family: Appearance.fontFamily
    font.bold: true
    font.features: {
      "tnum": 1
    }
  }

  // A line of large digits as tall as the digits themselves, plus `pad`
  // of that above and below (a font's line has room for accents and
  // descenders, which digits don't use)
  component CapLine: Item {
    id: capLine
    property alias text: capDigits.text
    property alias color: capDigits.color
    property real size: 10 // fixed px: a placeholder, always set from the room
    property real pad: 0.12
    readonly property real cap: capLine.size * root.capRatio
    implicitWidth: capDigits.implicitWidth
    implicitHeight: capLine.cap * (1 + capLine.pad * 2)

    // (A Digits; one inline component can't hold another here)
    Text {
      id: capDigits
      y: capLine.height - capLine.cap * capLine.pad - capDigits.baselineOffset
      color: root.textColor
      font.family: Appearance.fontFamily
      font.pixelSize: capLine.size
      font.bold: true
      font.features: {
        "tnum": 1
      }
    }
  }

  // An analog clock's hand: `length` and `thickness` in parts of the face
  // (`side` px across), turned to `angle` (always clockwise, so 59 → 0
  // doesn't wind back)
  component Hand: Item {
    id: hand
    property real side: 0
    property real angle: 0
    property real length: 0.4
    property real thickness: 0.03
    property color color: root.textColor
    anchors.fill: parent
    rotation: hand.angle

    Behavior on rotation {
      RotationAnimation {
        direction: RotationAnimation.Clockwise
        duration: Appearance.animFast
        easing.type: Appearance.easing
      }
    }

    Rectangle {
      width: Math.max(1, hand.side * hand.thickness)
      // A short tail past the centre
      height: hand.side * (hand.length + 0.08)
      x: (hand.side - width) / 2
      y: hand.side * (0.5 - hand.length)
      radius: width / 2
      color: hand.color
    }
  }

  Column {
    anchors.centerIn: parent
    width: root.innerWidth
    spacing: root.spacing

    Loader {
      anchors.horizontalCenter: parent.horizontalCenter
      sourceComponent: root.style === "analog" ? analog : root.style === "digital" ? digital : stacked
    }

    Text {
      width: parent.width
      height: root.captionSize * root.lineRatio
      visible: root.dateText !== ""
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.dateText
      color: root.textColor
      opacity: 0.8
      font.family: Appearance.fontFamily
      font.pixelSize: root.captionSize
    }

    Text {
      width: parent.width
      height: root.captionSize * root.lineRatio
      visible: root.label !== ""
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.label
      color: root.accentColor
      font.family: Appearance.fontFamily
      font.pixelSize: root.captionSize * 0.9
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: root.captionSize * 0.08
    }
  }

  // The time in one line, the seconds over AM/PM small beside it
  Component {
    id: digital

    Row {
      id: line
      readonly property bool hasSuffix: root.seconds !== "" || root.meridiem !== ""
      readonly property real suffixScale: 0.34
      // The size that fits the line across and the height
      readonly property real size: Math.max(1, Math.min(root.faceWidth * 100 / Math.max(1, timeMetrics.advanceWidth + (line.hasSuffix ? suffixMetrics.advanceWidth * line.suffixScale + 12 : 0)), root.faceHeight / (root.capRatio * 1.24)) * 0.95)
      spacing: line.size * 0.06

      Metrics {
        id: timeMetrics
        text: root.hours + ":" + root.minutes
      }
      Metrics {
        id: suffixMetrics
        text: root.meridiem.length > 2 ? root.meridiem : "00"
      }

      CapLine {
        id: time
        text: root.hours + ":" + root.minutes
        size: line.size
      }

      Column {
        visible: line.hasSuffix
        anchors.verticalCenter: time.verticalCenter

        Digits {
          visible: root.seconds !== ""
          text: root.seconds
          color: root.accentColor
          font.pixelSize: line.size * line.suffixScale
        }

        Digits {
          visible: root.meridiem !== ""
          text: root.meridiem
          opacity: 0.7
          font.pixelSize: line.size * line.suffixScale * 0.8
        }
      }
    }
  }

  // The hours over the minutes, tight, then AM/PM and the seconds small
  Component {
    id: stacked

    Column {
      id: stack
      readonly property string meta: [root.meridiem, root.seconds].filter(part => part !== "").join(" · ")
      readonly property real metaScale: 0.2
      // The size that fits the wider line across, and both lines (with a
      // little room between) and the small one down
      readonly property real size: Math.max(1, Math.min(root.faceWidth * 100 / Math.max(1, pairMetrics.advanceWidth), root.faceHeight / (root.capRatio * 2.32 + (stack.meta !== "" ? stack.metaScale * root.lineRatio : 0))) * 0.95)

      Metrics {
        id: pairMetrics
        text: root.hours.length > root.minutes.length ? root.hours : root.minutes
      }

      CapLine {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.hours.length < 2 ? "0" + root.hours : root.hours
        size: stack.size
        pad: 0.08
      }

      CapLine {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.minutes
        color: root.accentColor
        size: stack.size
        pad: 0.08
      }

      Digits {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: stack.meta !== ""
        text: stack.meta
        opacity: 0.7
        font.pixelSize: stack.size * stack.metaScale
        font.bold: false
      }
    }
  }

  // A face with twelve marks and the hands
  Component {
    id: analog

    Item {
      id: face
      readonly property real side: Math.max(1, Math.min(root.faceWidth, root.faceHeight))
      readonly property int hour: root.now.getHours() % 12
      readonly property int minute: root.now.getMinutes()
      readonly property int second: root.now.getSeconds()
      width: face.side
      height: face.side

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.alpha(root.textColor, 0.06)
        border.color: Qt.alpha(root.textColor, 0.3)
        border.width: Math.max(1, face.side * 0.012)
      }

      // The marks, longer at the quarters: each turned about the centre
      Repeater {
        model: 12

        Item {
          id: mark
          required property int index
          readonly property bool quarter: mark.index % 3 === 0
          anchors.fill: parent
          rotation: mark.index * 30

          Rectangle {
            x: (face.side - width) / 2
            y: face.side * 0.06
            width: face.side * (mark.quarter ? 0.024 : 0.014)
            height: face.side * (mark.quarter ? 0.09 : 0.05)
            radius: width / 2
            color: root.textColor
            opacity: mark.quarter ? 0.9 : 0.5
          }
        }
      }

      Hand {
        side: face.side
        angle: face.hour * 30 + face.minute * 0.5
        length: 0.26
        thickness: 0.036
      }

      Hand {
        side: face.side
        angle: face.minute * 6 + (root.showSeconds ? face.second * 0.1 : 0)
        length: 0.38
        thickness: 0.024
      }

      Hand {
        visible: root.showSeconds
        side: face.side
        angle: face.second * 6
        length: 0.42
        thickness: 0.01
        color: root.accentColor
      }

      Rectangle {
        anchors.centerIn: parent
        width: face.side * 0.05
        height: width
        radius: width / 2
        color: root.showSeconds ? root.accentColor : root.textColor
      }
    }
  }
}
