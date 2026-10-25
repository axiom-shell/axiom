pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Wayland

import qs.services.compositor

// A layer-shell `window` with a fixed place in the stack (a bar, the
// border, a dock, an integrated edge menu): bind its `visible` to
// `shown`, and what used to decide it to `wanted`. LayerManager shows it
// once every window ordered before it on its screen and layer
// (LayerStack.layers) has mapped, and maps it again when it lands out of
// place (docs/dev/compositor/layer-arrangement.md).
QtObject {
  id: root

  required property var window
  required property string namespace
  // Its WlrLayershell.layer (an attached property, unreadable from here)
  property int layer: WlrLayer.Top
  // Among windows of its order on its screen and layer, lower maps first
  // (the border's corner pieces after its strips, so they're drawn over
  // the strips' ends: Hyprland breaks ties by map order too)
  property int rank: 0
  // Whether its owner wants it shown
  property bool wanted: true
  // Kept mapped while not wanted, where the compositor stacks by map order
  // alone, so it keeps its place (its owner draws nothing then: `idle`)
  property bool held: false

  property int _uid: 0
  readonly property var _slot: {
    const output = root.window?.screen?.name ?? "";
    if (output === "")
      return null;
    return {
      "output": output,
      "layer": LayerManager.layerName(root.layer),
      "namespace": root.namespace,
      "rank": root.rank,
      "wanted": root.wanted,
      "held": root.held,
      "mapped": root.window?.visible ?? false
    };
  }
  on_SlotChanged: {
    if (root._uid > 0)
      LayerManager.reportSlot(root._uid, root._slot);
  }
  Component.onCompleted: {
    root._uid = LayerManager.register();
    LayerManager.reportSlot(root._uid, root._slot);
  }
  Component.onDestruction: LayerManager.reportSlot(root._uid, null)

  readonly property bool shown: root._uid > 0 && LayerManager.shownSlots[root._uid] === true
  // Mapped only to keep its place: nothing drawn, nothing reserved, no input
  readonly property bool idle: root.shown && !root.wanted
}
