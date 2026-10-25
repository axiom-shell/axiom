pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.core
import qs.components.methods

// A stretch of a stroke a surface covers, left open there, whatever draws
// that stroke: every host publishes its openings through this, so one
// joined the same way opens the same way. `span` is in screen px along its
// `edge` ({ screen, edge, start, end, startFillet?, endFillet? }: what
// EdgeAttach.joinOpening gives, or a stretch along the surface's own
// edge), `sink` who draws it (SurfaceContext.end's `sink`, or for the
// surface's own edge "border"/"solidBar"):
// - "border": the border's strip (ShellManager.borderOpenings), open under
//   a translucent fill only, as an opaque one hides it anyway
// - "solidBar": with the border off, a solid bar's own inner stroke, open
//   opaque or not (the bar and the surface are separate windows, whose
//   stacking isn't the bar's), on whole pixels (SurfaceContext.opening)
// Anything else ("pillBar": PillBarJoin, null) publishes nothing.
QtObject {
  id: root

  required property ShellScreen screen
  // Unique per opening, for the solid bar's owner-keyed openings
  required property string owner
  property var span: null
  property var sink: null

  readonly property var _border: BorderOpening {
    opening: root.sink === "border" && Appearance.translucent && root.span ? root.span : null
  }
  readonly property var _solid: PillStretch {
    readonly property var panel: root.sink === "solidBar" && root.span ? ShellManager.barOn(root.screen?.name ?? "", Bar.locationOf(root.span.edge)) : null
    owner: root.owner
    container: panel?.visible && (panel.barConfig?.innerStroke ?? false) ? panel.container : null
    opening: {
      const origin = container?.blurOrigin ?? null;
      if (!origin)
        return null;
      const along = root.span.edge === "left" || root.span.edge === "right" ? origin.y : origin.x;
      const o = SurfaceContext.opening(root.span.start - along, root.span.end - along, root.span.startFillet ?? 0, root.span.endFillet ?? 0);
      return o.end > o.start ? o : null;
    }
  }
}
