pragma ComponentBehavior: Bound
import QtQuick

// What the layouts editor edits (OverlayManager.editTarget), as its canvas
// and inspector show it: PageTarget, MenuTarget, LockscreenTarget, GreeterTarget. See
// GridCanvas for what each field draws.
QtObject {
  // The grid being edited
  property var editor: null
  // Its modules, or null when there's nothing to edit (a tool page)
  property var modules: null
  property string icon: "dashboard"
  property string title: ""
  property string emptyText: ""
  // Drawn around the grid: an edge, a screen box in units and its size in
  // px, a band along the edge, other menus
  property string edge: ""
  property var screenBox: null
  property var screenSize: null
  property real reservedDepth: 0
  property string reservedLabel: ""
  property var ghosts: []
  // How it fits, under the canvas title
  property string fitText: ""
  property bool fitWarning: false
  // Where to change what the fit line says, beside it (an `x-link`: {
  // setting } or { page }), or null
  property var fitLink: null
  // Arrows under the canvas title moving it along its edge (an edge
  // menu's): what they say ("" for no arrows), whether they run up and
  // down, which way they can go, and what they and recentring do
  property string nudgeText: ""
  property bool nudgeVertical: false
  property bool canNudgeBack: false
  property bool canNudgeForward: false
  property bool canCentre: false
  property var nudge: step => {}
  property var centre: () => {}
  // The px its lattice is moved along the edge, how far it can be either
  // way, and setting it
  property int gridOffset: 0
  property int gridOffsetLimit: 0
  property var setGridOffset: px => {}
  // The cells of a menu's lattice along its edge ({ from, to } in units
  // from the grid's origin; null for none): the canvas tints the rest
  property var latticeSpan: null
  // Whether modules can be added (else `notEditableHint` in the inspector)
  property bool editable: false
  property string notEditableHint: ""
}
