pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// A themed slider (trough, fill, round handle) that emits moved while
// dragged and released at the end. `value` is only pushed in, never written
// by a drag, so it can stay bound; a new value animates to it.
Item {
  id: root

  // -- Signals --
  signal moved(real value)
  signal released(real value)

  // -- Public API --
  property real value: 0.0
  readonly property bool pressed: mouseArea.isDragging
  // What the slider shows: the drag's place while pressed
  readonly property real position: root._shown

  // -- Configurable Appearance --
  property alias troughColor: troughRect.color
  property alias fillColor: fillRect.color
  property alias handleColor: handleRect.color
  property alias troughHeight: troughRect.height
  property real handleSize: Widget.px(14)

  // -- Implementation --
  property real _shown: root.value

  Binding {
    target: root
    property: "_shown"
    value: mouseArea.dragValue
    when: mouseArea.isDragging
  }

  Glide on _shown {
    duration: Appearance.animNormal
    enabled: !mouseArea.isDragging
  }

  Rectangle {
    id: troughRect
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: Widget.px(6)
    radius: Widget.radius
    color: Theme.backgroundHighlight
  }

  // The handle travels within the trough, so it never sticks out past
  // either end; the fill runs to its centre
  readonly property real _travel: Math.max(0, root.width - handleRect.width)

  Rectangle {
    id: fillRect
    anchors.verticalCenter: parent.verticalCenter
    width: root._shown * root._travel + handleRect.width / 2
    height: troughRect.height
    radius: height / 2
    color: Theme.accent
  }

  Rectangle {
    id: handleRect
    x: fillRect.width - width / 2
    anchors.verticalCenter: parent.verticalCenter
    width: root.handleSize
    height: root.handleSize
    radius: root.handleSize / 2
    color: Theme.foreground
    scale: mouseArea.isDragging ? 1.2 : (mouseArea.containsMouse ? 1.1 : 1.0)

    Glide on scale {
      duration: Appearance.animNormal
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // Inside a Flickable (a scrolling page) the drag would otherwise be
    // taken over as a scroll past its threshold, cancelling this one
    preventStealing: true

    property bool isDragging: false
    property real dragValue: 0
    // Where on the handle it was grabbed, so pressing the handle doesn't
    // jump the value; a press on the trough centres the handle there
    property real grabOffset: handleRect.width / 2

    function ratioAt(x) {
      return root._travel > 0 ? Math.max(0, Math.min(1, (x - grabOffset) / root._travel)) : 0;
    }

    function updatePosition(x) {
      dragValue = ratioAt(x);
      root.moved(dragValue);
    }

    onPressed: mouse => {
      const onHandle = mouse.x >= handleRect.x && mouse.x <= handleRect.x + handleRect.width;
      grabOffset = onHandle ? mouse.x - handleRect.x : handleRect.width / 2;
      isDragging = true;
      updatePosition(mouse.x);
    }

    onPositionChanged: {
      if (isDragging) {
        updatePosition(mouseX);
      }
    }

    // `released` goes out before the drag ends, so a user pushing the
    // released value in has done so when the slider goes back to showing
    // `value`, and it doesn't snap back to the old one first
    onReleased: {
      if (isDragging) {
        dragValue = ratioAt(mouseX);
        root.released(dragValue);
        isDragging = false;
      }
    }

    // Still ends the drag where it got to, so the value is committed
    onCanceled: {
      if (isDragging) {
        root.released(dragValue);
        isDragging = false;
      }
    }
  }
}
