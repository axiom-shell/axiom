import QtQuick
import QtTest
import qs.components.methods
import qs.components.methods.layer
import "layer/LayerStack.js" as Rows

// The stacking order of axiom's layer surfaces (LayerStack)
TestCase {
  id: test
  name: "LayerStack"

  // Records the helpers' calls as shared fixtures for the axiom binary
  Shared {
    id: shared
    testCase: test
  }

  EngineRows {
    id: rows
    testCase: test
    facade: LayerStack
    rows: Rows.rows
  }

  function test_rows_data() {
    return rows.data();
  }

  function test_rows(data) {
    rows.run(data);
  }

  function order(ns) {
    return LayerStack.layers.find(l => l.namespace === ns).order;
  }

  function test_blur_lists() {
    verify(LayerStack.blurChrome.includes("bar-floating-long"), "blur lists take every bar");
  }

  // The chrome slides itself, in every mode: no compositor animation
  function test_chrome_never_animated() {
    const chrome = LayerStack.barLayers.concat(["border", "popout", "edge-popout", "osd", "edge-menu", "menu", "dock", "notifications", "blur-backing", "shadows"]);
    for (const ns of chrome)
      verify(LayerStack.layers.find(l => l.namespace === ns)?.noAnim === true, ns + " has noAnim");
  }

  function test_one_entry_per_namespace() {
    const names = LayerStack.layers.map(l => l.namespace);
    compare(names.length, new Set(names).size);
  }

  // The order BarEnds.rank assumes: solid, the border, pills, floating,
  // transparent, then docks; of a kind, the shorter edge's bar first
  function test_bar_layers_in_corner_order() {
    const chain = ["bar", "bar-long", "border", "bar-pill", "bar-pill-long", "bar-floating", "bar-floating-long", "bar-transparent", "bar-transparent-long", "dock"];
    for (let i = 1; i < chain.length; i++)
      verify(order(chain[i - 1]) > order(chain[i]), chain[i - 1] + " before " + chain[i]);
    compare(LayerStack.barLayers.length, 8);
  }

  // The overlay's page: on Top after the backdrop, before the backing
  // window (and so under the chrome)
  function test_overlay_under_chrome() {
    verify(order("backdrop") > order("overlay"));
    verify(order("overlay") > order("blur-backing"));
  }

  // The overlay blurs itself, but not reduced over a fullscreen window: in
  // blurReduced only, and every such namespace has a row
  function test_blur_reduced() {
    compare(LayerStack.blurReduced, ["overlay"]);
    for (const list of [LayerStack.blurSurfaces, LayerStack.blurBackdrops, LayerStack.blurChrome])
      verify(!list.includes("overlay"), "only in blurReduced");
    for (const ns of LayerStack.blurReduced)
      verify(LayerStack.layers.some(l => l.namespace === ns), ns + " has a row");
  }

  // The shadows apart from the blur (no blurThreshold): where each blur
  // window sits, under the chrome it shades, and never blurred
  function test_shadows_apart_order() {
    verify(order("blur-backing") > order("shadows"));
    for (const ns of ["edge-menu", "bar", "border", "dock"])
      verify(order("shadows") > order(ns), "under " + ns);
    verify(![].concat(LayerStack.blurSurfaces, LayerStack.blurReduced, LayerStack.blurBackdrops).includes("shadows"), "shadows not blurred");
  }

  // A free menu's window: over the windows on Top, under the blur window
  // and the shadows (which draw its fill and shadow), under every popout
  // that can be on Top (the dock, and the rest wherever they are); its fill drawn by the blur window
  // and its popups blurred
  function test_free_menu_order() {
    const menu = order("menu");
    for (const ns of ["blur-backing", "shadows"])
      verify(order(ns) > menu, "over " + ns);
    // Every popout on Top draws over it (one opening over it closes it,
    // or it gives way, pinned: PopoutManager; meanwhile, as its box
    // slides away, the popout is on top)
    for (const ns of ["dock", "popout", "edge-popout", "dock-preview", "osd"])
      verify(menu > order(ns), "under " + ns);
    verify(LayerStack.blurChrome.includes("menu"));
    verify(![].concat(LayerStack.blurSurfaces, LayerStack.blurBackdrops).includes("menu"), "never blurred whole");
  }

  function test_order_of() {
    compare(shared.calls.LayerStack.orderOf("axiom-bar"), 5);
    compare(shared.calls.LayerStack.orderOf("dock"), -7);
    compare(shared.calls.LayerStack.orderOf("axiom-desktop"), 0, "listed at 0");
    compare(shared.calls.LayerStack.orderOf("someone-else"), 0, "not listed");
  }

  function sequenceOf(entries) {
    return LayerArrange.sequence({
      "entries": entries,
      "ordered": false,
      "remappingIds": []
    });
  }

  function entry(id, order, extra) {
    return Object.assign({
      "id": id,
      "outputName": "O",
      "layer": "top",
      "order": order,
      "wanted": true,
      "held": false,
      "mapped": false,
      "seq": 0
    }, extra ?? {});
  }

  // Held windows opening and closing, and a window on the Overlay layer
  // mapping, never put a Top window out of place
  function test_runtime_keeps_top() {
    const held = ["backdrop", "overlay", "blur-backing", "menu", "edge-menu"];
    const entries = [];
    let seq = 1;
    for (const ns of held.concat(["bar", "border", "dock"]))
      entries.push(entry(ns, order(ns), {
        "wanted": !held.includes(ns),
        "held": held.includes(ns),
        "showing": true,
        "mapped": true,
        "seq": seq++
      }));
    compare(sequenceOf(entries).remap, [], "settled: nothing to map again");
    for (const e of entries.filter(x => x.held)) {
      e.wanted = true;
      compare(sequenceOf(entries).remap, [], "opening and closing held windows, and an Overlay window mapping, maps no Top window again");
      e.wanted = false;
      compare(sequenceOf(entries).remap, [], "opening and closing held windows, and an Overlay window mapping, maps no Top window again");
    }
    const all = entries.concat([entry("notifications", order("notifications"), {
        "layer": "overlay",
        "showing": true,
        "mapped": true,
        "seq": seq++
      })]);
    compare(sequenceOf(all).remap, [], "opening and closing held windows, and an Overlay window mapping, maps no Top window again");
  }

  // Every namespace has an order, and the toast stack ties with the popouts
  function test_every_namespace_has_an_order() {
    for (const l of LayerStack.layers)
      verify(typeof l.order === "number", l.namespace + " has an order");
    compare(LayerStack.orderOf("notifications"), LayerStack.orderOf("popout"));
  }

  // Every row states its layer, in the four names
  function test_every_row_has_a_layer() {
    for (const l of LayerStack.layers)
      verify(["top", "overlay", "bottom", "background"].includes(l.layer), l.namespace + " has a layer");
  }

  // Only a row on Top or Overlay over a fullscreen window states it: always,
  // or while shown
  function test_over_fullscreen_values() {
    for (const l of LayerStack.layers)
      verify(l.overFullscreen === undefined || ["always", "whileShown", "never"].includes(l.overFullscreen), l.namespace + " overFullscreen");
  }

  // The instant action surfaces: five rows, one order, all on Overlay (the
  // layer a wait for a modal compares with)
  function test_modal_rows() {
    const modal = LayerStack.layers.filter(l => l.modal === true);
    compare(modal.length, 5);
    compare(new Set(modal.map(l => l.order)).size, 1);
    compare(modal[0].order, -30);
    for (const l of modal)
      compare(l.layer, "overlay", l.namespace);
    verify(LayerStack.isModal("powermenu"));
    verify(LayerStack.isModal("axiom-polkit"));
    verify(!LayerStack.isModal("osd"));
    verify(!LayerStack.isModal("notifications"));
    verify(!LayerStack.isModal("someone-else"));
  }

  // Every row states that the compositor doesn't animate its window
  function test_every_row_is_not_animated() {
    for (const l of LayerStack.layers)
      verify(l.noAnim === true, l.namespace + " has noAnim");
  }
}
