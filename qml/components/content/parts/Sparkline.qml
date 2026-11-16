pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small line graph of `values` (oldest first), filled underneath,
// between `minValue` and `maxValue` (0 scales to the largest value shown).
// `style: "bars"` draws a bar per value (70 % of its step, from the
// baseline) instead; `values2` adds a second line in `lineColor2`, on the
// same range (the scale covers both).
Canvas {
  id: root

  property var values: []
  // A second series, drawn as a line over the first
  property var values2: []
  // "line" (filled underneath) or "bars"
  property string style: "line"
  property real minValue: 0
  property real maxValue: 100
  property color lineColor: Style.accent
  property color lineColor2: Style.series[1]
  property real fillOpacity: 0.2 // style-exempt: the chart fill fades its data colour
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
  onValues2Changed: _repaint()
  onStyleChanged: _repaint()
  onLineColorChanged: _repaint()
  onLineColor2Changed: _repaint()
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
    const vals2 = root.values2 ?? [];
    const bars = root.style === "bars";
    // The bars' step is a slot of the width; a line's, the gap between points
    if (vals.length < (bars ? 1 : 2) && vals2.length < 2)
      return;
    const min = root.minValue;
    const max = root.maxValue > min ? root.maxValue : Math.max(min + 1, ...vals, ...vals2);
    const step = width / Math.max(1, root.capacity - (bars ? 0 : 1));
    const x0 = width - (vals.length - (bars ? 0 : 1)) * step;
    const inset = root.lineWidth / 2;
    const y = v => inset + (height - inset * 2) * (1 - Math.min(1, Math.max(0, (v - min) / (max - min))));

    if (bars) {
      const barWidth = step * 0.7;
      ctx.fillStyle = root.lineColor;
      vals.forEach((v, i) => ctx.fillRect(x0 + i * step + (step - barWidth) / 2, y(v), barWidth, height - y(v)));
    } else if (vals.length >= 2) {
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
      ctx.globalAlpha = 1;
    }

    if (vals2.length >= 2) {
      // The second line ends at the right edge on its own length, over the
      // bars' slot centres or the first line's points
      const second = width - (vals2.length - 1) * step - (bars ? step / 2 : 0);
      ctx.beginPath();
      vals2.forEach((v, i) => i === 0 ? ctx.moveTo(second, y(v)) : ctx.lineTo(second + i * step, y(v)));
      ctx.lineWidth = root.lineWidth;
      ctx.lineJoin = "round";
      ctx.strokeStyle = root.lineColor2;
      ctx.stroke();
    }
  }
}
