pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable

// A price line over time (the markets popout, module and rows): `points`
// ([unix seconds, price], oldest first) placed by time between `start` and
// `end` (a session: a day under way fills from the left; 0 takes the
// points' own), scaled to the prices and `reference`, the previous close,
// drawn dashed. The area under the line fades out downwards. `detailed`
// adds a crosshair with the price and time under the pointer.
Item {
  id: root

  property var points: []
  property real reference: 0
  property real start: 0
  property real end: 0
  property color lineColor: Theme.accent
  property real lineWidth: Widget.px(2)
  property real fillOpacity: 0.28
  property bool showReference: true
  property bool detailed: false
  // The hover label's currency and whether its time shows the date
  property string currency: ""
  property bool showDate: false

  readonly property var _time: MarketMath.timeSpan(root.points ?? [], root.start, root.end)
  readonly property var _price: MarketMath.priceSpan(root.points ?? [], root.showReference ? root.reference : 0)
  readonly property real _inset: root.lineWidth

  function xOf(t) {
    return root._inset + (root.width - root._inset * 2) * (t - root._time.start) / (root._time.end - root._time.start);
  }

  function yOf(p) {
    return root._inset + (root.height - root._inset * 2) * (1 - (p - root._price.min) / (root._price.max - root._price.min));
  }

  Canvas {
    id: canvas
    anchors.fill: parent

    // Hidden, it skips every change and catches up when shown
    function _repaint() {
      if (root.visible)
        canvas.requestPaint();
    }

    Connections {
      target: root
      function onPointsChanged() {
        canvas._repaint();
      }
      function onReferenceChanged() {
        canvas._repaint();
      }
      function onLineColorChanged() {
        canvas._repaint();
      }
      function onStartChanged() {
        canvas._repaint();
      }
      function onEndChanged() {
        canvas._repaint();
      }
      function onVisibleChanged() {
        canvas._repaint();
      }
    }
    onWidthChanged: _repaint()
    onHeightChanged: _repaint()

    onPaint: {
      const ctx = getContext("2d");
      ctx.reset();
      const pts = root.points ?? [];
      if (width <= 0 || height <= 0)
        return;
      if (root.showReference && root.reference > 0) {
        const y = Math.round(root.yOf(root.reference)) + 0.5;
        ctx.strokeStyle = Qt.alpha(Theme.foregroundInactive, 0.7);
        ctx.lineWidth = 1;
        ctx.setLineDash([3, 3]);
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(width, y);
        ctx.stroke();
        ctx.setLineDash([]);
      }
      if (pts.length < 2)
        return;
      ctx.beginPath();
      pts.forEach((p, i) => i === 0 ? ctx.moveTo(root.xOf(p[0]), root.yOf(p[1])) : ctx.lineTo(root.xOf(p[0]), root.yOf(p[1])));
      const lastX = root.xOf(pts[pts.length - 1][0]);
      const firstX = root.xOf(pts[0][0]);
      if (root.fillOpacity > 0) {
        ctx.save();
        ctx.lineTo(lastX, height);
        ctx.lineTo(firstX, height);
        ctx.closePath();
        const gradient = ctx.createLinearGradient(0, 0, 0, height);
        gradient.addColorStop(0, Qt.alpha(root.lineColor, root.fillOpacity));
        gradient.addColorStop(1, Qt.alpha(root.lineColor, 0));
        ctx.fillStyle = gradient;
        ctx.fill();
        ctx.restore();
        ctx.beginPath();
        pts.forEach((p, i) => i === 0 ? ctx.moveTo(root.xOf(p[0]), root.yOf(p[1])) : ctx.lineTo(root.xOf(p[0]), root.yOf(p[1])));
      }
      ctx.strokeStyle = root.lineColor;
      ctx.lineWidth = root.lineWidth;
      ctx.lineJoin = "round";
      ctx.lineCap = "round";
      ctx.stroke();
      // The latest price, a dot at the line's end
      ctx.fillStyle = root.lineColor;
      ctx.beginPath();
      ctx.arc(lastX, root.yOf(pts[pts.length - 1][1]), root.lineWidth * 1.4, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  // The crosshair: the point nearest the pointer, its price and time
  HoverHandler {
    id: hover
    enabled: root.detailed
  }

  readonly property var _hovered: {
    const pts = root.points ?? [];
    if (!root.detailed || !hover.hovered || pts.length === 0)
      return null;
    const t = root._time.start + (hover.point.position.x - root._inset) / Math.max(1, root.width - root._inset * 2) * (root._time.end - root._time.start);
    let lo = 0, hi = pts.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (pts[mid][0] < t)
        lo = mid;
      else
        hi = mid;
    }
    return Math.abs(pts[lo][0] - t) <= Math.abs(pts[hi][0] - t) ? pts[lo] : pts[hi];
  }

  Rectangle {
    visible: root._hovered !== null
    x: root._hovered ? Math.round(root.xOf(root._hovered[0])) : 0
    width: 1
    height: root.height
    color: Qt.alpha(Theme.foreground, 0.35)
  }

  Rectangle {
    visible: root._hovered !== null
    readonly property real size: root.lineWidth * 4
    x: root._hovered ? root.xOf(root._hovered[0]) - size / 2 : 0
    y: root._hovered ? root.yOf(root._hovered[1]) - size / 2 : 0
    width: size
    height: size
    radius: size / 2
    color: root.lineColor
    border.width: 2
    border.color: Theme.background
  }

  Rectangle {
    id: label
    visible: root._hovered !== null
    readonly property real px: root._hovered ? root.xOf(root._hovered[0]) : 0
    x: Math.max(0, Math.min(root.width - width, px - width / 2))
    y: 0
    width: labelText.implicitWidth + Widget.smallPadding * 2
    height: labelText.implicitHeight + Widget.spacing
    radius: height / 2
    color: Theme.backgroundAlt
    border.width: 1
    border.color: Theme.border

    StyledText {
      id: labelText
      anchors.centerIn: parent
      textSize: Appearance.fontSizeBy(-2)
      text: root._hovered ? I18n.tr("{0} · {1}", MarketMath.formatPrice(root._hovered[1], root.currency), I18n.formatDate(new Date(root._hovered[0] * 1000), root.showDate ? I18n.dateFormat("mediumDate") : I18n.timeFormat("default"))) : ""
    }
  }
}
