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
  // Its WlrLayershell.layer (an attached property, unreadable from here)
  property int layer: WlrLayer.Top
  // Among windows of its order on its screen and layer, lower maps first
  // (the border's corner pieces after its strips, so they're drawn over
  // the strips' ends)
  property int rank: 0
  // Ranks compare only within one group: windows of one order that never
  // meet keep no order between them (bars on different edges sharing a
  // namespace), so one remade doesn't map the others again
  property string rankGroup: ""
  // Whether its owner wants it shown
  property bool wanted: true
  // Kept mapped while not wanted, so it keeps its place (its owner draws
  // nothing then: `idle`)
  property bool held: false

  readonly property var _slot: {
    const outputName = root.window?.screen?.name ?? "";
    if (outputName === "")
      return null;
    return {
      "outputName": outputName,
      "layer": LayerManager.layerName(root.layer),
      "namespace": root.window?.layerNamespace ?? "",
      "rank": root.rank,
      "rankGroup": root.rankGroup,
      "wanted": root.wanted,
      "held": root.held,
      "mapped": root.window?.visible ?? false
    };
  }
  on_SlotChanged: root._report()
  Component.onCompleted: root._report()
  Component.onDestruction: LayerManager.dropSlot(root)
  function _report() {
    if (root._slot)
      LayerManager.setSlot(root, root._slot);
    else
      LayerManager.dropSlot(root);
  }

  readonly property bool shown: LayerManager.slotOf(root).shown
  // Mapped only to keep its place: nothing drawn, nothing reserved, no input
  readonly property bool idle: root.shown && !root.wanted
}
