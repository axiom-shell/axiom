pragma ComponentBehavior: Bound
import QtQuick

// A WheelHandler that steps once per wheel notch (120 of angleDelta, its y
// or else its x; a touchpad's scroll adds up to one first): `stepped`'s
// direction is -1 for up or left, 1 for down or right.
WheelHandler {
  id: root

  signal stepped(int direction)

  property real _accumulated: 0

  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
  onWheel: event => {
    root._accumulated += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
    if (Math.abs(root._accumulated) < 120)
      return;
    root.stepped(root._accumulated > 0 ? -1 : 1);
    root._accumulated = 0;
  }
}
