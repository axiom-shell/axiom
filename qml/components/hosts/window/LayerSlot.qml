pragma ComponentBehavior: Bound
import QtQuick

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
  // Its window's layer now, as the layer service answers it from its row:
  // bind WlrLayershell.layer and LayerOrigin.layer to it
  readonly property int layer: LayerManager.wlrLayerOf(LayerManager.slotOf(root).layer)
  // Its window is on the Overlay layer now (BlurManager.backsOn's second
  // argument; a host's `onOverlayLayer` reads it)
  readonly property bool onOverlayLayer: LayerManager.slotOf(root).layer === "overlay"
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
  // Lets go of its window first: the dying window's last changes (it
  // unmaps as its answer goes) must not report it again
  Component.onDestruction: {
    root.window = null;
    LayerManager.dropSlot(root);
  }
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
