pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// Text in the shell's font: a `role` (size, weight, default tone and
// overflow, from Style) and a `tone`; its colour is the ink of the nearest
// enclosing Surface, else the global role. Optionally turned for a vertical
// bar. docs/dev/core/style.md.
Text {
  id: root

  // -- Public API --
  property bool isVertical: false
  // micro | caption | body | label | title | headline | display
  property string role: "body"
  // "" = the role's: text | muted | faint | accent | onAccent | success |
  // warning | error | info
  property string tone: ""
  // "" = the role's: "line" (one line, elided), "wrap" (wraps, breaks a
  // long token), "none" (neither)
  property string overflow: ""
  // 0 = no cap; with "wrap" the last line elides
  property int maxLines: 0

  // -- Configurable Appearance --
  // Set only for a state or data (a bar's palette, a fitted size): the role
  // and tone are the default
  property color textColor: Style.toneOn(root._inkHost ? root._inkHost.inkScope : null, root.tone || root._role.tone)
  property string textFamily: Appearance.fontFamily
  property int textSize: root._role.size

  // -- Implementation --
  readonly property StyleTextRole _role: Style.textRole(root.role)
  // Bindings, not handlers: they re-run when an ancestor is reparented, so
  // the first colour already is the ink (no Behavior animates in). Both walks
  // stop at the nearest Surface or relay (a publisher of inkHostAbove and
  // drawnZoom)
  readonly property var _inkHost: InkHost.find(root.parent)
  readonly property real _drawnZoom: TextRender.zoomAt(root.parent)

  color: textColor
  rotation: isVertical ? -90 : 0
  font.family: textFamily
  font.pixelSize: textSize
  font.weight: root._role.weight
  // The role's overflow, unless set (written out in both: a binding of its own costs every text)
  elide: (root.overflow || root._role.overflow) === "line" || ((root.overflow || root._role.overflow) === "wrap" && root.maxLines > 0) ? Text.ElideRight : Text.ElideNone
  maximumLineCount: root.maxLines > 0 ? root.maxLines : 2147483647
  wrapMode: (root.overflow || root._role.overflow) === "wrap" && !(root.elide !== Text.ElideNone && root.maxLines === 0) ? Text.Wrap : Text.NoWrap
  // Native at rest, distance field under a declared zoom (a binding, so it
  // follows a reparent; set here rather than left to the pragma)
  renderType: TextRender.typeFor(root._drawnZoom, false, 0)
}
