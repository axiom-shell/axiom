pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small line graph of `values` (oldest first), filled underneath,
// between `minValue` and `maxValue` (0 scales to the largest value shown).
Canvas {
  id: root

  property var values: []
  property real minValue: 0
  property real maxValue: 100
  property color lineColor: Theme.accent
  property real fillOpacity: 0.2
  property real lineWidth: 2
  // How many samples the width represents, so a short history grows in
  // from the right instead of stretching
  property int capacity: 60
  // A faint line along the bottom, so a graph still growing in (or flat)
  // reads as a graph
  property bool showBaseline: true

  // Hidden (a strip's or full layout's graph not shown), it skips every
  // sample and catches up when shown
  function _repaint() {
    if (root.visible)
      root.requestPaint();
  }

  onValuesChanged: _repaint()
  onLineColorChanged: _repaint()
  onMinValueChanged: _repaint()
  onMaxValueChanged: _repaint()
  onWidthChanged: _repaint()
  onHeightChanged: _repaint()
  onVisibleChanged: _repaint()

  onPaint: {
    const ctx = getContext("2d");
    ctx.reset();
    const vals = root.values ?? [];
    if (width <= 0 || height <= 0)
      return;
    if (root.showBaseline) {
      ctx.globalAlpha = 0.25;
      ctx.fillStyle = root.lineColor;
      ctx.fillRect(0, height - 1, width, 1);
      ctx.globalAlpha = 1;
    }
    if (vals.length < 2)
      return;
    const min = root.minValue;
    const max = root.maxValue > min ? root.maxValue : Math.max(min + 1, ...vals);
    const step = width / Math.max(1, root.capacity - 1);
    const x0 = width - (vals.length - 1) * step;
    const inset = root.lineWidth / 2;
    const y = v => inset + (height - inset * 2) * (1 - Math.min(1, Math.max(0, (v - min) / (max - min))));

    ctx.beginPath();
    vals.forEach((v, i) => i === 0 ? ctx.moveTo(x0, y(v)) : ctx.lineTo(x0 + i * step, y(v)));
    ctx.lineWidth = root.lineWidth;
    ctx.lineJoin = "round";
    ctx.strokeStyle = root.lineColor;
    ctx.stroke();

    ctx.lineTo(width, height);
    ctx.lineTo(x0, height);
    ctx.closePath();
    ctx.globalAlpha = root.fillOpacity;
    ctx.fillStyle = root.lineColor;
    ctx.fill();
  }
}
