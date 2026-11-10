pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.components.reusable

// The workspace grid's position head, handed to SplitLead as `ownHead`:
// one dot per row (column on a vertical bar) stacked across the bar with
// the shown one filled, or, where the dots don't fit, the arrow glyph for
// that position (GridPosition.head decides). Its wheel steps along its own
// axis, across the one the cells' wheel steps along.
Item {
  id: root

  property var barConfig
  property var properties
  property color color
  property bool vertical: false
  // The shown row (column) and how many there are (config)
  property int line: 0
  property int count: 0
  // A GridPosition.head result
  property var head: ({
      "kind": "none"
    })

  readonly property bool pips: head.kind === "pips"
  // Along the bar: as long as an icon head, so the wheel has room
  readonly property real _along: Math.max(pips ? head.dot : 0, barConfig.fontSize)
  readonly property real _across: pips ? head.length : (vertical ? arrow.implicitWidth : arrow.implicitHeight)

  implicitWidth: vertical ? _across : _along
  implicitHeight: vertical ? _along : _across
  width: implicitWidth
  height: implicitHeight

  Loader {
    anchors.centerIn: parent
    active: root.pips
    sourceComponent: root.vertical ? pipsRow : pipsColumn
  }

  Component {
    id: pipsColumn
    Column {
      spacing: root.head.gap
      Repeater {
        model: root.count
        delegate: Pip {}
      }
    }
  }

  Component {
    id: pipsRow
    Row {
      spacing: root.head.gap
      Repeater {
        model: root.count
        delegate: Pip {}
      }
    }
  }

  component Pip: Rectangle {
    required property int index
    width: root.head.dot
    height: root.head.dot
    radius: root.head.dot / 2
    color: index === root.line ? root.color : Qt.alpha(root.color, 0.35)

    ColorGlide on color {}
  }

  StyledIcon {
    id: arrow
    anchors.centerIn: parent
    visible: !root.pips
    text: root.head.glyph ?? ""
    textSize: root.barConfig.fontSize
    textColor: root.color
  }

  NotchWheel {
    enabled: root.properties.scrollToSwitch
    onStepped: direction => {
      const step = root.properties.scrollReverse ? -direction : direction;
      CompositorManager.stepWorkspace(root.vertical ? (step > 0 ? "right" : "left") : (step > 0 ? "down" : "up"), "go");
    }
  }
}
