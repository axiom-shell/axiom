pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// The colours an ActionTile or ActionPill takes from its tone: the fill while
// active, the container its well takes while hot, and the ink on the well and
// the text beside it. The host sets `activeTone`, `active` and `hot`.
QtObject {
  // accent | error
  property string activeTone: "accent"
  property bool active: false
  property bool hot: false

  readonly property string _containerTone: activeTone + "Container"
  // The fill while active, and the hover / selected outline
  readonly property color activeColor: activeTone === "error" ? Style.error : Style.accent
  readonly property color containerFill: activeTone === "error" ? Style.errorContainer : Style.accentContainer
  // Glyph on the well: highest at rest, the container's ink hot, the fill's ink while active
  readonly property color contentColor: active ? Style.inkOf(activeTone).icon : hot ? Style.inkOf(_containerTone).icon : Style.inkHighest.icon
  readonly property color labelColor: active ? Style.inkOf(activeTone).text : hot ? Style.inkOf(_containerTone).text : Style.inkSurface.text
  readonly property color mutedColor: active ? Style.inkOf(activeTone).muted : hot ? Style.inkOf(_containerTone).muted : Style.inkSurface.muted

  function wellRadius(width: real): real {
    return Math.min(Style.radius * 1.5, width / 2);
  }
}
