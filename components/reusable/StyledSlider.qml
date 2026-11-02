pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// A themed slider (trough, fill, handle) that emits moved while dragged
// and released at the end; a value pushed in animates to it.
Item {
  id: root

  // -- Signals --
  signal moved(real value)
  signal released(real value)

  // -- Public API --
  property real value: 0.0
  property real targetValue: value
  property real _internalValue: value
  property bool pressed: mouseArea.isDragging

  // -- Configurable Appearance --
  property alias troughColor: troughRect.color
  property alias fillColor: fillRect.color
  property alias handleColor: handleRect.color
  property alias handleRadius: handleRect.radius

  property alias handleWidth: handleRect.width
  property alias handleHeight: handleRect.height
  property alias troughHeight: troughRect.height

  // -- Implementation --
  Binding {
    target: root
    property: "_internalValue"
    value: root.targetValue
    when: !mouseArea.isDragging
  }

  Glide on _internalValue {
    duration: Appearance.animNormal
    enabled: !mouseArea.isDragging
  }

  Rectangle {
    id: troughRect
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    height: Widget.px(4)
    radius: Widget.radius
    color: Theme.backgroundHighlight
  }

  // The handle travels within the trough, so it never sticks out past
  // either end; the fill runs to its centre
  readonly property real _travel: Math.max(0, root.width - handleRect.width)
  readonly property real _shown: mouseArea.isDragging ? root.value : root._internalValue

  Rectangle {
    id: fillRect
    anchors.verticalCenter: parent.verticalCenter
    width: root._shown * root._travel + handleRect.width / 2
    height: troughRect.height
    radius: height / 2
    color: Theme.foreground

    Behavior on width {
      enabled: !mouseArea.isDragging
      NumberAnimation {
        duration: Appearance.animNormal
        easing.type: Easing.OutQuad
      }
    }
  }

  Rectangle {
    id: handleRect
    x: fillRect.width - width / 2
    anchors.verticalCenter: parent.verticalCenter
    width: Widget.px(24)
    height: Widget.px(14)
    radius: Widget.radius
    color: Theme.backgroundAlt
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
    // Where on the handle it was grabbed, so pressing the handle doesn't
    // jump the value; a press on the trough centres the handle there
    property real grabOffset: handleRect.width / 2

    function ratioAt(x) {
      return root._travel > 0 ? Math.max(0, Math.min(1, (x - grabOffset) / root._travel)) : 0;
    }

    function updatePosition(x) {
      const ratio = ratioAt(x);
      root.value = ratio;
      root.moved(ratio);
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

    onReleased: {
      if (isDragging) {
        isDragging = false;
        const ratio = ratioAt(mouseX);
        root.value = ratio;
        root.released(ratio);
      }
    }

    // Still ends the drag where it got to, so the value is committed
    onCanceled: {
      if (isDragging) {
        isDragging = false;
        root.released(root.value);
      }
    }
  }
}
