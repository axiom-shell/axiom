pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A ring gauge: a thin track with a round-capped arc over it, like a
// StyledSlider bent into a circle, and an icon in the middle. `sweep`
// below 360 opens it at the bottom (a gauge: 240)
Item {
  id: root

  property real percentage: 0
  property string iconText: "●"
  property color iconColor: Theme.background
  property color fillColor: Theme.accentAlt
  property color trackColor: Theme.backgroundHighlight
  // The stroke, as a share of the side, but never thinner than a slider's trough
  property real thickness: Math.max(Widget.px(4), side * 0.07)
  // Degrees the track spans, centred on the top
  property real sweep: 360

  readonly property real side: Math.min(root.width, root.height)

  implicitWidth: Widget.px(120)
  implicitHeight: Widget.px(120)

  Canvas {
    id: ring
    anchors.centerIn: parent
    width: root.side
    height: root.side

    onPaint: {
      const ctx = getContext("2d");
      const centre = width / 2;
      const radius = centre - root.thickness / 2;
      ctx.clearRect(0, 0, width, height);
      if (radius <= 0)
        return;
      ctx.lineWidth = root.thickness;

      const span = Math.max(1, Math.min(360, root.sweep)) * Math.PI / 180;
      const start = -Math.PI / 2 - span / 2 + (root.sweep >= 360 ? span / 2 : 0);
      ctx.beginPath();
      ctx.arc(centre, centre, radius, start, start + span, false);
      ctx.lineCap = root.sweep >= 360 ? "butt" : "round";
      ctx.strokeStyle = root.trackColor;
      ctx.stroke();

      // A round cap would draw a dot at zero
      const share = Math.max(0, Math.min(1, root.percentage / 100));
      if (share <= 0)
        return;
      ctx.beginPath();
      ctx.arc(centre, centre, radius, start, start + share * span, false);
      ctx.lineCap = "round";
      ctx.strokeStyle = root.fillColor;
      ctx.stroke();
    }

    Connections {
      target: root
      function onPercentageChanged() {
        ring.requestPaint();
      }
      function onFillColorChanged() {
        ring.requestPaint();
      }
      function onTrackColorChanged() {
        ring.requestPaint();
      }
      function onThicknessChanged() {
        ring.requestPaint();
      }
      function onSweepChanged() {
        ring.requestPaint();
      }
    }
  }

  StyledIcon {
    anchors.centerIn: parent
    text: root.iconText
    textColor: root.iconColor
    textSize: root.side * 0.3
  }

  Behavior on percentage {
    NumberAnimation {
      duration: Appearance.animSlow
      easing.type: Easing.OutCubic
    }
  }
}
