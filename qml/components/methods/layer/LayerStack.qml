pragma Singleton
import QtQuick

// Where every axiom layer-shell window stands, on every compositor (pure):
// the table is where each window's place is stated, one row per namespace.
// Within a layer, a compositor arranges and draws its surfaces in the order
// they mapped: the first reserves its space nearest the screen edge, takes
// a shared corner and is drawn underneath (docs/dev/compositor/
// layer-arrangement.md). `order` is axiom's map sequence: LayerManager maps
// the windows in it on every compositor, and Hyprland's `order` rules are
// written from it (the daemon writes them from this table). The daemon
// parses this file's plain JSON (backend/internal/compositor/render/
// tables.go, ParseTables, from the constant LayerStackFile): the property
// names `layers`, `blurSurfaces`, `blurBackdrops`, `blurReduced` and
// `blurChrome` are its contract.
QtObject {
  id: root

  // One entry per axiom namespace (without its "axiom-" prefix), highest
  // order first; `layer` is its window's layer (top, overlay, bottom,
  // background); `overFullscreen` how it stands over a fullscreen window
  // ("always": on Overlay there, "whileShown": on Overlay there while shown,
  // "never": hidden while one is up; none: stays); `modal` an instant action
  // surface (last on Overlay, never mapped again, nothing moves onto its layer
  // while it shows); `bar` marks a bar's (BarsConfig.layerNamespace), `noAnim`
  // one Hyprland shouldn't animate, `why` says why it sits there. Kept as
  // plain JSON: scripts/gen_docs.py reads it into docs/dev/generated/layers.md.
  readonly property var layers: [
    {
      "namespace": "backdrop",
      "order": 11,
      "layer": "top",
      "overFullscreen": "always",
      "noAnim": true,
      "why": "Each screen's backdrop window (ScreenBackdrop: full-screen surfaces' dim background): on Top, under the bars and border. Mapped, so it keeps its place before them."
    },
    {
      "namespace": "overlay",
      "order": 10,
      "layer": "top",
      "overFullscreen": "whileShown",
      "noAnim": true,
      "why": "The overlay's page: on Top, after the backdrop and before the backing window, so the backing window draws every chrome fill over it and every chrome window is over it; on Overlay while a fullscreen window is on its screen (still before the backing window). Mapped while closed (a pixel drawing nothing), so it keeps that place. One namespace in every state: its reduced blur is a rule turned off (blurReduced), never a namespace change, which would remake it and map every window after it again."
    },
    {
      "namespace": "blur-backing",
      "order": 9,
      "layer": "top",
      "overFullscreen": "always",
      "noAnim": true,
      "why": "The backing window (BlurManager, shell/BlurBacking), drawing the chrome's fills under it. Mapped (a pixel while nothing blurs)."
    },
    {
      "namespace": "shadows",
      "order": 8,
      "layer": "top",
      "overFullscreen": "always",
      "noAnim": true,
      "why": "The chrome's shadows, apart from the blur window where its blur has no alpha threshold (SwayFX, no supports.blurThreshold), so they aren't blurred: over the fills (they never meet) and under the chrome. Mapped as the blur window is."
    },
    {
      "namespace": "edge-menu",
      "order": 7,
      "layer": "top",
      "noAnim": true,
      "why": "An integrated edge menu: arranged before the bars and border, so it sits at the screen edge and pushes them and the windows inwards."
    },
    {
      "namespace": "menu",
      "order": 7,
      "layer": "top",
      "noAnim": true,
      "why": "Free menus (FreeMenu): on Top over the windows, under every popout: the dock on Top, and the Overlay layer's. Their full-screen window reserves nothing and keeps clear of what's reserved, so it never meets an integrated menu of its order. Mapped, drawing and taking nothing while closed."
    },
    {
      "namespace": "bar",
      "order": 5,
      "layer": "top",
      "bar": true,
      "noAnim": true,
      "why": "Solid bars, on the screen's shorter edge: arranged before the border, whose strip then lands on the bar's inner part. Of two bars at a corner the one arranged first takes it (BarEnds)."
    },
    {
      "namespace": "bar-long",
      "order": 4,
      "layer": "top",
      "bar": true,
      "noAnim": true,
      "why": "Solid bars on the screen's longer edge: after the shorter edge's, so they make way at a shared corner."
    },
    {
      "namespace": "border",
      "order": 0,
      "layer": "top",
      "noAnim": true,
      "why": "The screen border after the solid bars, before the pill bars."
    },
    {
      "namespace": "bar-pill",
      "order": -1,
      "layer": "top",
      "bar": true,
      "noAnim": true,
      "why": "Pill bars: after the border (inside it, drawn over its stroke), before every other kind of bar."
    },
    {
      "namespace": "bar-pill-long",
      "order": -2,
      "layer": "top",
      "bar": true,
      "noAnim": true,
      "why": "Pill bars on the longer edge."
    },
    {
      "namespace": "bar-floating",
      "order": -3,
      "layer": "top",
      "bar": true,
      "noAnim": true,
      "why": "Floating bars and floating pills: make way for solid and pill bars."
    },
    {
      "namespace": "bar-floating-long",
      "order": -4,
      "layer": "top",
      "bar": true,
      "noAnim": true,
      "why": "Floating bars on the longer edge."
    },
    {
      "namespace": "bar-transparent",
      "order": -5,
      "layer": "top",
      "bar": true,
      "noAnim": true,
      "why": "Transparent bars: make way for every other bar, so one is laid inside them all (and its edge popouts open past them)."
    },
    {
      "namespace": "bar-transparent-long",
      "order": -6,
      "layer": "top",
      "bar": true,
      "noAnim": true,
      "why": "Transparent bars on the longer edge: the last bar."
    },
    {
      "namespace": "dock",
      "order": -7,
      "layer": "top",
      "noAnim": true,
      "why": "Docks: after every bar and the border on their edge, so they sit inside them."
    },
    {
      "namespace": "osd",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "The OSD: on the Overlay layer, so a volume or brightness change shows over the overlay's page and the chrome."
    },
    {
      "namespace": "dock-preview",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "A dock's preview (the settings card's Show): after the OSD's order, as the dock it previews."
    },
    {
      "namespace": "edge-popout",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "Edge popouts (floating edge menus, the launcher, the window switcher): after the dock and the OSD, so a menu draws over both."
    },
    {
      "namespace": "popout",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "Bar popouts: over the bars they open from."
    },
    {
      "namespace": "hot-corner",
      "order": -12,
      "layer": "overlay",
      "overFullscreen": "never",
      "noAnim": true,
      "why": "Hot corners' pixel windows (shell/HotCorners): on Overlay after the overlay's page and the -10 group, before the modals, so a corner stays live over the overlay and over popouts; never shown over a fullscreen window."
    },
    {
      "namespace": "screenshot",
      "order": -30,
      "layer": "overlay",
      "modal": true,
      "noAnim": true,
      "why": "An instant action surface: last on the Overlay layer, over everything of axiom's, never mapped again; nothing moves onto its layer on its screen while it shows, where a move lands on top"
    },
    {
      "namespace": "monitor-prompt",
      "order": -30,
      "layer": "overlay",
      "modal": true,
      "noAnim": true,
      "why": "An instant action surface: last on the Overlay layer, over everything of axiom's, never mapped again; nothing moves onto its layer on its screen while it shows, where a move lands on top"
    },
    {
      "namespace": "screenshare",
      "order": -30,
      "layer": "overlay",
      "modal": true,
      "noAnim": true,
      "why": "An instant action surface: last on the Overlay layer, over everything of axiom's, never mapped again; nothing moves onto its layer on its screen while it shows, where a move lands on top"
    },
    {
      "namespace": "polkit",
      "order": -30,
      "layer": "overlay",
      "modal": true,
      "noAnim": true,
      "why": "An instant action surface: last on the Overlay layer, over everything of axiom's, never mapped again; nothing moves onto its layer on its screen while it shows, where a move lands on top"
    },
    {
      "namespace": "powermenu",
      "order": -30,
      "layer": "overlay",
      "modal": true,
      "noAnim": true,
      "why": "An instant action surface: last on the Overlay layer, over everything of axiom's, never mapped again; nothing moves onto its layer on its screen while it shows, where a move lands on top"
    },
    {
      "namespace": "notifications",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "The toast stack (ToastStack): no fade in or out, the cards slide themselves. With the on-demand windows (order -10, ties by map order): nothing maps again on any compositor."
    },
    {
      "namespace": "desktop",
      "order": 0,
      "layer": "bottom",
      "noAnim": true,
      "why": "Desktop widgets: no fade in or out."
    },
    {
      "namespace": "workspaces",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "The workspace overview: an on-demand full-screen window on the Overlay layer, over the chrome and the overlay's page."
    },
    {
      "namespace": "onboarding",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "The first-run guide: an on-demand full-screen window on the Overlay layer, over the chrome."
    },
    {
      "namespace": "notice",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "The no-parent notice: an on-demand window on the Overlay layer, over the chrome."
    },
    {
      "namespace": "lock-preview",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "The lock screen's preview (the settings card's Show): an on-demand window on the Overlay layer."
    },
    {
      "namespace": "greeter-preview",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "The login screen's preview (the settings card's Show): an on-demand window on the Overlay layer."
    },
    {
      "namespace": "greeter",
      "order": -10,
      "layer": "overlay",
      "noAnim": true,
      "why": "The login screen, in the greeter's own shell: on the Overlay layer, over everything. No layer service runs there."
    },
    {
      "namespace": "wallpaper",
      "order": 0,
      "layer": "background",
      "noAnim": true,
      "why": "The wallpaper: on the Background layer, under every window."
    },
    {
      "namespace": "edge-trigger",
      "order": -12,
      "layer": "top",
      "overFullscreen": "never",
      "noAnim": true,
      "why": "An edge's hover strip: a pixel window on Top that opens a popout, mapped while its host wants it (inert without input). Last on Top: over the bars, border and docks it opens from. Never shown over a fullscreen window: hidden while one is up on its screen."
    }
  ]
  // The bars' namespaces (without "axiom-")
  readonly property var barLayers: root.layers.filter(l => l.bar).map(l => l.namespace)

  // --- What blurs behind axiom (the compositor's, by namespace; the daemon's
  // layer rules and sway's layer effects) ---

  // Layers blurred whole, their transparent pixels left out: the blur
  // window (drawing the chrome's fills: the chrome doesn't blur itself)
  // and the big surfaces that blur themselves
  readonly property var blurSurfaces: ["blur-backing", "dock-preview", "powermenu", "workspaces", "monitor-prompt"]
  // Surfaces that blur themselves (as blurSurfaces) but not while
  // Overlay.reduceFullscreen reduces them over a fullscreen window: their
  // rule follows BlurManager.reduced
  readonly property var blurReduced: ["overlay"]
  // Backdrops (and the shared prompt and screen-share picker, whose
  // windows hold their own dim),
  // only when asked: the whole screen, at every alpha
  readonly property var blurBackdrops: ["backdrop", "polkit", "screenshare"]
  // The chrome's own windows, for their popups alone (tooltips, the dock's
  // menu): the chrome doesn't blur itself, its popups do
  readonly property var blurChrome: root.barLayers.concat(["popout", "edge-popout", "edge-menu", "menu", "dock"])

  // A namespace's order (with or without its "axiom-" prefix); 0 for one
  // not listed or without an order
  function orderOf(namespace) {
    return root._rowOf(namespace)?.order ?? 0;
  }

  // Whether the namespace's row is an instant action surface (`modal`)
  function isModal(namespace) {
    return root._rowOf(namespace)?.modal === true;
  }

  function _rowOf(namespace) {
    const name = String(namespace).replace(/^axiom-/, "");
    return root.layers.find(l => l.namespace === name);
  }

  // Rule: a window that is never over a fullscreen window: the layer service
  // hides it while one is up on its screen
  function hiddenUnderFullscreen(row, state) {
    return row.overFullscreen === "never" && state.fullscreen;
  }

  // Rule: with no `overFullscreen`, or no fullscreen window on its screen,
  // a window stays on its row's layer
  function staysOnRowLayer(row, state) {
    return row.overFullscreen === undefined || !state.fullscreen;
  }

  // Rule: over a fullscreen window, a window of `always` or `whileShown`
  // rises to Overlay where a move keeps its place (Hyprland with its rules,
  // niri)
  function risesWhereMovesKeepPlace(row, state) {
    return (row.overFullscreen === "always" || row.overFullscreen === "whileShown") && state.fullscreen && state.movesKeepPlace;
  }

  // Rule: where a move lands on top, a `whileShown` window rises while it is
  // wanted
  function risesWhileShown(row, state) {
    return row.overFullscreen === "whileShown" && state.fullscreen && !state.movesKeepPlace && state.wanted;
  }

  // Rule: where a move lands on top, a `whileShown` window not wanted comes
  // down at once (the Top layer is under the fullscreen window, so what it
  // lands over maps again unseen)
  function downWhileNotShown(row, state) {
    return row.overFullscreen === "whileShown" && state.fullscreen && !state.movesKeepPlace && !state.wanted;
  }

  // Rule: where a move lands on top, an `always` window never moves (its
  // surfaces over a fullscreen window fill themselves)
  function staysWhereMovesDont(row, state) {
    return row.overFullscreen === "always" && state.fullscreen && !state.movesKeepPlace;
  }

  // Rule: where a move lands on top, a window that would move onto the modal
  // rows' layer keeps its layer (`underModal`) while a modal shows on its
  // screen; a move down never waits
  function movesWaitForModal(answer, state) {
    return !state.movesKeepPlace && Boolean(state.underModal) && answer !== state.underModal && answer === "overlay";
  }

  /**
   * The layer a window is on now, as a name. `state`: { fullscreen (a
   * fullscreen window is on its screen), wanted (its owner wants it shown),
   * movesKeepPlace (a window moved to another layer keeps its place in the
   * order), underModal (its layer while a modal shows on its screen, else
   * "") }. The table, by row `overFullscreen` (none or `any`): `never`,
   * fullscreen: "" (hiddenUnderFullscreen, not shown now); no
   * fullscreen window: the row's layer (staysOnRowLayer); `always` or
   * `whileShown`, fullscreen, movesKeepPlace: overlay
   * (risesWhereMovesKeepPlace); `whileShown`, fullscreen, wanted: overlay
   * (risesWhileShown); `whileShown`, fullscreen, not wanted: the row's layer
   * (downWhileNotShown); `always`, fullscreen: the row's layer
   * (staysWhereMovesDont). Then movesWaitForModal over the answer. An
   * unlisted namespace is on top.
   */
  function layerOf(namespace, state) {
    const row = root._rowOf(namespace);
    if (!row)
      return "top";
    const answer = root._tableLayer(row, state);
    return root.movesWaitForModal(answer, state) ? state.underModal : answer;
  }

  // The table's answer, before movesWaitForModal
  function _tableLayer(row, state) {
    if (root.hiddenUnderFullscreen(row, state))
      return "";
    if (root.staysOnRowLayer(row, state))
      return row.layer;
    if (root.risesWhereMovesKeepPlace(row, state))
      return "overlay";
    if (root.risesWhileShown(row, state))
      return "overlay";
    if (root.downWhileNotShown(row, state))
      return row.layer;
    return root.staysWhereMovesDont(row, state) ? row.layer : "top";
  }
}
