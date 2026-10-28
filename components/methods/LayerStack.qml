pragma Singleton
import QtQuick

// The order axiom's layer surfaces stack and reserve their space in, on
// every compositor (pure). Within a layer, a compositor arranges and draws
// its surfaces in the order they mapped: the first reserves its space
// nearest the screen edge, takes a shared corner and is drawn underneath
// (docs/dev/compositor/layer-arrangement.md). Hyprland sorts them by a
// layer rule's `order` first (render.LayerRulesLua), higher first; on
// the others axiom maps them in this order.
QtObject {
  id: root

  // One entry per axiom namespace (without its "axiom-" prefix), highest
  // order first; `bar` marks a bar's (BarsConfig.layerNamespace), `noAnim` one
  // Hyprland shouldn't animate, `why` says why it sits there. Kept as
  // plain JSON: scripts/gen_docs.py reads it into
  // docs/dev/generated/layers.md.
  readonly property var layers: [
    {
      "namespace": "border-shadow",
      "order": 11,
      "why": "The border's inward shadow window: under every other axiom surface, the overlay backdrop included."
    },
    {
      "namespace": "backdrop",
      "order": 10,
      "why": "Each screen's backdrop window (ScreenBackdrop: full-screen surfaces' dim background): on Top, under the bars and border. Without layer rules it stays mapped (held), so it keeps its place before them."
    },
    {
      "namespace": "blur-backing",
      "order": 9,
      "why": "The blur window (BlurManager, shell/BlurBacking), drawing the chrome's fills under it. Held (a pixel while nothing blurs) where layers stack by map order."
    },
    {
      "namespace": "shadows",
      "order": 8,
      "why": "The chrome's shadows, apart from the blur window where its blur has no alpha threshold (SwayFX, no supports.blurThreshold), so they aren't blurred: over the fills (they never meet) and under the chrome. Held as the blur window is."
    },
    {
      "namespace": "edge-menu",
      "order": 7,
      "why": "An integrated edge menu: arranged before the bars and border, so it sits at the screen edge and pushes them and the windows inwards."
    },
    {
      "namespace": "popout-under",
      "order": 6,
      "why": "Detached popouts and floating edge menus: drawn under the bars and border, so they slide out from beneath them. Only with layer rules (supports.layerOrder): elsewhere they open over the bar, as over the overlay."
    },
    {
      "namespace": "bar",
      "order": 5,
      "bar": true,
      "why": "Solid bars, on the screen's shorter edge: arranged before the border, whose strip then lands on the bar's inner part. Of two bars at a corner the one arranged first takes it (BarEnds)."
    },
    {
      "namespace": "bar-long",
      "order": 4,
      "bar": true,
      "why": "Solid bars on the screen's longer edge: after the shorter edge's, so they make way at a shared corner."
    },
    {
      "namespace": "border",
      "order": 0,
      "why": "The screen border (Hyprland's default order, written for the record)."
    },
    {
      "namespace": "bar-pill",
      "order": -1,
      "bar": true,
      "why": "Pill bars: after the border (inside it, drawn over its stroke), before every other kind of bar."
    },
    {
      "namespace": "bar-pill-long",
      "order": -2,
      "bar": true,
      "why": "Pill bars on the longer edge."
    },
    {
      "namespace": "bar-transparent",
      "order": -3,
      "bar": true,
      "why": "Transparent bars: make way for solid and pill bars."
    },
    {
      "namespace": "bar-transparent-long",
      "order": -4,
      "bar": true,
      "why": "Transparent bars on the longer edge."
    },
    {
      "namespace": "bar-floating",
      "order": -5,
      "bar": true,
      "why": "Floating bars and floating pills: make way for every other bar."
    },
    {
      "namespace": "bar-floating-long",
      "order": -6,
      "bar": true,
      "why": "Floating bars on the longer edge: the last bar."
    },
    {
      "namespace": "dock",
      "order": -7,
      "why": "Docks: after every bar and the border on their edge, so they sit inside them."
    },
    {
      "namespace": "overlay",
      "order": -8,
      "why": "The overlay's panel: after docks, inside an always-shown dock's zone and over a hover or intellihide one."
    },
    {
      "namespace": "blur-backing-overlay",
      "order": -9,
      "noAnim": true,
      "why": "The blur window over the overlay (shell/BlurBacking, while the overlay is open on its screen), drawing the fills of the Overlay-layer surfaces above it: after the overlay, before them. Mapped at once, so the fills it draws under content already showing don't fade in."
    },
    {
      "namespace": "shadows-overlay",
      "order": -9,
      "noAnim": true,
      "why": "The shadows of the Overlay-layer surfaces over the overlay, apart from their blur window as `shadows` is: beside it (they never meet), before those surfaces."
    },
    {
      "namespace": "osd",
      "order": -10,
      "why": "The OSD: after the overlay, so a volume or brightness change shows over it."
    },
    {
      "namespace": "dock-preview",
      "order": -10,
      "why": "A dock's preview (the settings card's Show): after the overlay, so it shows over the settings page."
    },
    {
      "namespace": "edge-popout",
      "order": -11,
      "why": "Edge popouts (floating edge menus): after the dock and the OSD, so a menu opened over the overlay draws over both."
    },
    {
      "namespace": "popout",
      "order": -11,
      "why": "Bar popouts: over the bars they open from."
    },
    {
      "namespace": "screenshot",
      "order": -20,
      "noAnim": true,
      "why": "The screenshot picker's frozen frame: appears and goes at once, no fade, over everything (popups can't be ordered: see captureFrozen)."
    },
    {
      "namespace": "monitor-prompt",
      "order": -25,
      "why": "The monitor layout prompt (Keep / Revert): after the picker, over the overlay the Monitors page opened it from."
    },
    {
      "namespace": "polkit",
      "order": -30,
      "why": "The polkit prompt: after everything, so nothing of axiom's draws over a password prompt."
    },
    {
      "namespace": "desktop",
      "noAnim": true,
      "why": "Desktop widgets: no fade in or out."
    }
  ]
  // The bars' namespaces (without "axiom-")
  readonly property var barLayers: root.layers.filter(l => l.bar).map(l => l.namespace)

  // --- What blurs behind axiom (the compositor's, by namespace; the daemon's
  // layer rules and sway's layer effects) ---

  // Layers blurred whole, their transparent pixels left out: the blur
  // window (drawing the chrome's fills: the chrome doesn't blur itself)
  // and the big surfaces that blur themselves
  readonly property var blurSurfaces: ["blur-backing", "dock-preview", "overlay", "launcher", "switcher", "floating-popout", "notifications", "powermenu", "workspaces", "monitor-prompt"]
  // Backdrops (and the polkit prompt, whose window holds its own dim),
  // only when asked: the whole screen, at every alpha
  readonly property var blurBackdrops: ["backdrop", "polkit"]
  // The blur window over the overlay: what it blurs is the overlay, so
  // never see-through (xray would blur the wallpaper in its place)
  readonly property var blurOverOverlay: ["blur-backing-overlay"]
  // The chrome's own windows, for their popups alone (tooltips, the dock's
  // menu): the chrome doesn't blur itself, its popups do
  readonly property var blurChrome: root.barLayers.concat(["popout", "popout-under", "edge-popout", "edge-menu", "dock"])
  // The windows whose fill, blur and shadow the blur window draws: not
  // animated by the compositor while it does (they slide themselves), or
  // their stroke and content fade or pop in and out while what the blur
  // window draws for them doesn't
  readonly property var blurBacked: root.barLayers.concat(["border", "popout", "popout-under", "edge-popout", "osd", "edge-menu", "dock"])

  // A namespace's order (with or without its "axiom-" prefix); 0 (where
  // Hyprland puts a surface without a rule) for one not listed or without
  // an order
  function orderOf(namespace) {
    const name = String(namespace).replace(/^axiom-/, "");
    return root.layers.find(l => l.namespace === name)?.order ?? 0;
  }

  /**
   * Which of the windows axiom maps in order may show now, and which
   * have to map again. `entries`: { id, output, layer, order, rank (among
   * windows of one order, lower first: optional, 0), wanted (its
   * owner wants it shown), held (kept mapped even when not wanted, where
   * the compositor stacks by map order alone), showing (visible now),
   * mapped (shown long enough for the compositor to have mapped it), seq
   * (when it mapped) }.
   * On each output and layer a window shows once every window ordered
   * before it there that shows is mapped, so they map highest order
   * first. One already showing stays (a window ordered before it starting
   * to show, a backdrop, doesn't take it down). Unless the compositor
   * sorts by order itself (`ordered`), a mapped window that one ordered
   * before it mapped after is out of place: it maps again (`remap`), and
   * so lands after it.
   * Returns { show: [ids], remap: [ids] }.
   */
  function sequence(entries, ordered) {
    const wants = e => e.wanted || (!ordered && e.held);
    const peers = e => entries.filter(o => o !== e && o.output === e.output && o.layer === e.layer);
    // `o` belongs before `e`: a higher order, or a lower rank of the same
    // (the border's corners after its strips, drawn over their ends)
    const before = (o, e) => o.order > e.order || (o.order === e.order && (o.rank ?? 0) < (e.rank ?? 0));
    const remap = ordered ? [] : entries.filter(e => e.mapped && peers(e).some(o => o.mapped && before(o, e) && o.seq > e.seq)).map(e => e.id);
    const show = entries.filter(e => wants(e) && !remap.includes(e.id) && (e.showing || peers(e).every(o => !wants(o) || !before(o, e) || o.mapped))).map(e => e.id);
    return {
      "show": show,
      "remap": remap
    };
  }
}
