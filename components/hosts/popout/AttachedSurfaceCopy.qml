pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods

// A copy of an AttachedSurface's shape, its geometry bound live to the
// source's (sliding with it: its own slide runs with the source's
// `active`): its fill alone, or with `mirrorStroke`. The blur window draws
// one per surface (shell/BlurBacking); a bar's pills cast their shadow
// from black ones (BarContainer).
AttachedSurface {
  id: root

  // (null for a moment while its owner is torn down, as on a reload: it
  // draws nothing then)
  required property AttachedSurface source

  mirror: true
  visible: root.source !== null
  width: root.source?.width ?? 0
  height: root.source?.height ?? 0
  edge: root.source?.edge ?? ScreenEdge.Top
  active: root.source?.active ?? false
  animationDuration: root.source?.animationDuration ?? Appearance.animNormal
  boxWidth: root.source?.boxWidth ?? 0
  boxHeight: root.source?.boxHeight ?? 0
  boxStart: root.source?.boxStart ?? 0
  connectorGap: root.source?.connectorGap ?? 0
  joinStart: root.source?.joinStart ?? false
  joinEnd: root.source?.joinEnd ?? false
  flushStart: root.source?.flushStart ?? false
  flushEnd: root.source?.flushEnd ?? false
  flushStartThrough: root.source?.flushStartThrough ?? true
  flushEndThrough: root.source?.flushEndThrough ?? true
  detached: root.source?.detached ?? false
  detachedOffset: root.source?.detachedOffset ?? 0
  backfill: root.source?.backfill ?? 0
  joinBackfill: root.source?.joinBackfill ?? 0
  straight: root.source?.straight ?? false
  straightJoins: root.source?.straightJoins ?? false
  straightJoinStart: root.source?.straightJoinStart ?? straightJoins
  straightJoinEnd: root.source?.straightJoinEnd ?? straightJoins
  startCornerRadius: root.source?.startCornerRadius ?? 0
  endCornerRadius: root.source?.endCornerRadius ?? 0
  startNearRadius: root.source?.startNearRadius ?? 0
  endNearRadius: root.source?.endNearRadius ?? 0
  fillColor: root.source?.fillColor ?? "transparent"
}
