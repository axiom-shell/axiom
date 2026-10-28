import QtQuick
import QtTest
import qs.components.methods

// The stacking order of axiom's layer surfaces (LayerStack)
TestCase {
  id: test
  name: "LayerStack"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  function order(ns) {
    return LayerStack.layers.find(l => l.namespace === ns).order;
  }

  function test_blur_lists() {
    verify(LayerStack.blurChrome.includes("bar-floating-long") && LayerStack.blurBacked.includes("bar-pill"), "blur lists take every bar");
  }

  function test_one_entry_per_namespace() {
    const names = LayerStack.layers.map(l => l.namespace);
    compare(names.length, new Set(names).size);
  }

  // The order BarEnds.rank assumes: solid, the border, pills, transparent,
  // floating, then docks; of a kind, the shorter edge's bar first
  function test_bar_layers_in_corner_order() {
    const chain = ["bar", "bar-long", "border", "bar-pill", "bar-pill-long", "bar-transparent", "bar-transparent-long", "bar-floating", "bar-floating-long", "dock"];
    for (let i = 1; i < chain.length; i++)
      verify(order(chain[i - 1]) > order(chain[i]), chain[i - 1] + " before " + chain[i]);
    compare(LayerStack.barLayers.length, 8);
  }

  // The blur window over the overlay sits strictly between the overlay and
  // every Overlay-layer surface it draws fills for
  function test_blur_over_overlay_order() {
    const backing = order("blur-backing-overlay");
    verify(order("overlay") > backing);
    for (const ns of ["osd", "dock-preview", "edge-popout", "popout"])
      verify(backing > order(ns), "under " + ns);
    verify(LayerStack.layers.find(l => l.namespace === "blur-backing-overlay").noAnim);
  }

  // The shadows apart from the blur (no blurThreshold): where each blur
  // window sits, under the chrome it shades, and never blurred
  function test_shadows_apart_order() {
    verify(order("blur-backing") > order("shadows"));
    for (const ns of ["edge-menu", "popout-under", "bar", "border", "dock"])
      verify(order("shadows") > order(ns), "under " + ns);
    verify(order("overlay") > order("shadows-overlay"));
    for (const ns of ["osd", "dock-preview", "edge-popout", "popout"])
      verify(order("shadows-overlay") > order(ns), "under " + ns);
    for (const ns of ["shadows", "shadows-overlay"])
      verify(![].concat(LayerStack.blurSurfaces, LayerStack.blurBackdrops, LayerStack.blurOverOverlay).includes(ns), ns + " not blurred");
  }

  function test_orderOf() {
    compare(shared.calls.LayerStack.orderOf("axiom-bar"), 5);
    compare(shared.calls.LayerStack.orderOf("dock"), -7);
    compare(shared.calls.LayerStack.orderOf("axiom-desktop"), 0, "listed without an order");
    compare(shared.calls.LayerStack.orderOf("someone-else"), 0, "not listed");
  }

  function entry(id, order, extra) {
    return Object.assign({
      "id": id,
      "output": "O",
      "layer": "top",
      "order": order,
      "wanted": true,
      "held": false,
      "mapped": false,
      "seq": 0
    }, extra ?? {});
  }

  // Highest order first: each waits for those before it to have mapped
  function test_sequence_stages() {
    const shadow = entry("shadow", 11), bar = entry("bar", 5), border = entry("border", 0), pill = entry("pill", -1);
    compare(shared.calls.LayerStack.sequence([border, pill, bar, shadow], false).show, ["shadow"]);
    shadow.mapped = true;
    compare(shared.calls.LayerStack.sequence([border, pill, bar, shadow], false).show, ["bar", "shadow"]);
    bar.mapped = true;
    compare(shared.calls.LayerStack.sequence([border, pill, bar, shadow], false).show.sort(), ["bar", "border", "shadow"]);
    border.mapped = true;
    compare(shared.calls.LayerStack.sequence([border, pill, bar, shadow], false).show.length, 4);
  }

  // Not wanted, a window doesn't hold the others back; equal orders don't
  // wait for each other; other outputs and layers don't count
  function test_sequence_independent() {
    const off = entry("off", 5, {
      "wanted": false
    });
    const a = entry("a", 0), b = entry("b", 0);
    const elsewhere = entry("elsewhere", 9, {
      "output": "P"
    });
    const above = entry("above", 9, {
      "layer": "overlay"
    });
    compare(shared.calls.LayerStack.sequence([off, a, b, elsewhere, above], false).show.sort(), ["a", "above", "b", "elsewhere"]);
  }

  // A bar remade (mapped after the border) puts the border out of place
  // where the compositor stacks by map order alone
  function test_sequence_remap() {
    const bar = entry("bar", 5, {
      "mapped": true,
      "seq": 3
    });
    const border = entry("border", 0, {
      "mapped": true,
      "seq": 1
    });
    const dock = entry("dock", -7, {
      "mapped": true,
      "seq": 4
    });
    const result = shared.calls.LayerStack.sequence([bar, border, dock], false);
    compare(result.remap, ["border"]);
    verify(!result.show.includes("border"), "hidden to map again");
    compare(shared.calls.LayerStack.sequence([bar, border, dock], true).remap, [], "Hyprland sorts by order itself");
  }

  // Held windows map at their place even unwanted, without layer order only
  function test_sequence_held() {
    const menu = entry("menu", 7, {
      "wanted": false,
      "held": true
    });
    const bar = entry("bar", 5);
    compare(shared.calls.LayerStack.sequence([menu, bar], false).show, ["menu"]);
    compare(shared.calls.LayerStack.sequence([menu, bar], true).show, ["bar"]);
  }

  // A window ordered before others starting to show (a backdrop, opening
  // with the overlay) doesn't take down those already showing
  function test_sequence_showing_stays() {
    const backdrop = entry("backdrop", 10);
    const bar = entry("bar", 5, {
      "showing": true,
      "mapped": true,
      "seq": 1
    });
    const border = entry("border", 0);
    const result = shared.calls.LayerStack.sequence([backdrop, bar, border], true);
    compare(result.show.sort(), ["backdrop", "bar"], "the bar stays; the border, not shown yet, still waits");
  }

  // Of one order, a higher rank waits for the lower ones, and maps again
  // if it mapped before one
  function test_sequence_rank() {
    const strip = entry("strip", 0);
    const corner = entry("corner", 0, {
      "rank": 1
    });
    compare(shared.calls.LayerStack.sequence([strip, corner], true).show, ["strip"]);
    strip.mapped = true;
    strip.seq = 2;
    corner.mapped = true;
    corner.seq = 1;
    compare(shared.calls.LayerStack.sequence([strip, corner], false).remap, ["corner"]);
  }
}
