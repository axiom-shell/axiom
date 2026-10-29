pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable
import qs.components.content.parts.custom

// A custom widget's Bar element: the value between min and max as a
// LevelMeter, across or up by its shape. With a change command it's a
// StyledSlider (turned upright in a tall box): releasing runs the command
// with {value} (between min and max, rounded to the step), and the slider
// holds the value until the next sample.
CustomElementBase {
  id: root

  readonly property bool interactive: root.actionsEnabled && root.actions.change !== ""
  readonly property real share: Math.max(0, root.ratio())
  readonly property real thickness: Math.max(Widget.px(4), Math.min(Widget.px(14), root.vertical ? root.width : root.height))
  // The share just set, until the next sample (-1: none)
  property real held: -1
  onFieldsChanged: root.held = -1

  function valueOf(share) {
    const step = root.options.step;
    const v = root.range.min + share * (root.range.max - root.range.min);
    return step > 0 ? Math.round(v / step) * step : v;
  }

  Loader {
    anchors.fill: parent
    sourceComponent: root.interactive ? slider : meter
  }

  Component {
    id: meter
    LevelMeter {
      share: root.share
      vertical: root.vertical
      thickness: root.thickness
      fillColor: root.colorOf(Theme.accent)
    }
  }

  Component {
    id: slider
    Item {
      StyledSlider {
        anchors.centerIn: parent
        width: root.vertical ? parent.height : parent.width
        height: Math.max(Widget.px(16), root.thickness)
        rotation: root.vertical ? -90 : 0
        troughHeight: root.thickness
        handleWidth: Widget.px(14)
        handleHeight: Widget.px(14)
        handleRadius: Widget.px(7)
        handleColor: Theme.foreground
        fillColor: root.colorOf(Theme.accent)
        // Not `value`: dragging assigns that, which would drop the binding
        targetValue: root.held >= 0 ? root.held : root.share
        onReleased: ratio => {
          root.held = ratio;
          root.act("change", root.valueOf(ratio));
        }
      }
    }
  }
}
