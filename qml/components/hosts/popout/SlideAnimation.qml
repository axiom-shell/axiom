pragma ComponentBehavior: Bound
import QtQuick
import qs.config

/**
 * Reusable slide animation container
 * Supports sliding from any direction
 */
Item {
  id: root

  property bool active: false

  // Direction flags (only one should be true)
  property bool slideFromRight: false
  property bool slideFromLeft: false
  property bool slideFromTop: false
  property bool slideFromBottom: false

  property int animationDuration: Appearance.animNormal

  default property alias content: contentArea.children

  // Room past its bounds where its content may still draw (a shadow), on
  // every side but the one it slides in from: only that side
  // is cut, hiding the content until it has slid out
  property real overflow: 0
  // Where the content is, from its place, as it slides (the blur window
  // draws a copy there, see BlurShape)
  readonly property real slideX: contentWrapper.slideX
  readonly property real slideY: contentWrapper.slideY
  readonly property real _left: root.slideFromLeft ? 0 : root.overflow
  readonly property real _top: root.slideFromTop ? 0 : root.overflow

  Item {
    id: clipper
    clip: true
    x: -root._left
    y: -root._top
    width: root.width + root._left + (root.slideFromRight ? 0 : root.overflow)
    height: root.height + root._top + (root.slideFromBottom ? 0 : root.overflow)

    Item {
      id: contentWrapper
      width: root.width
      height: root.height
      // Where it slides, from its place in the root
      property real slideX: 0
      property real slideY: 0
      x: root._left + slideX
      y: root._top + slideY

      readonly property real hiddenX: {
        if (root.slideFromRight)
          return root.width;
        if (root.slideFromLeft)
          return -root.width;
        return 0;
      }

      readonly property real hiddenY: {
        if (root.slideFromBottom)
          return root.height;
        if (root.slideFromTop)
          return -root.height;
        return 0;
      }

      states: [
        State {
          name: "visible"
          when: root.active
          PropertyChanges {
            contentWrapper.slideX: 0
            contentWrapper.slideY: 0
          }
        },
        State {
          name: "hidden"
          when: !root.active
          PropertyChanges {
            contentWrapper.slideX: contentWrapper.hiddenX
            contentWrapper.slideY: contentWrapper.hiddenY
          }
        }
      ]

      transitions: Transition {
        NumberAnimation {
          properties: "slideX,slideY"
          duration: root.animationDuration
          easing.type: Appearance.easing
        }
      }

      Item {
        id: contentArea
        anchors.fill: parent
      }
    }
  }

  Component.onCompleted: {
    Qt.callLater(function () {
      // Gone already: a surface built and dropped in one pass (a bar
      // switching to or from pills remakes its window)
      if (!root)
        return;
      contentWrapper.slideX = root.active ? 0 : contentWrapper.hiddenX;
      contentWrapper.slideY = root.active ? 0 : contentWrapper.hiddenY;
    });
  }
}
