pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

import qs.config

// The shell's shadow (the BarStyle section's, as the bars and the border
// cast it), as a layer effect for a surface with an exposed border:
// popouts, edge popouts (OSDs, edge menus, the launcher), docks, floating
// popouts. It spreads evenly, so it never slides onto a stroke the surface
// joins. Windows keep AttachedSurface.shadowReach of room past the
// surface for it.
// `cut` keeps only the shadow outside the source's shape, dropping the
// source too: for a translucent surface, whose own shadow would otherwise
// show through it. Its source then is a copy of the shape (a layer of its
// own, as FloatingPopout's copy, or a capture of it: OutsideShadow). Only
// what the shape covers fully is cut: under its anti-aliased edge the
// shadow stays, as the stroke drawn over it hides it there, or a pixel's
// gap shows between the surface and its shadow.
MultiEffect {
  property bool cut: false
  // What it's cut by: the source, or a copy of it with more cut out
  // (OutsideShadow's holes)
  property var cutSource: source

  // BarStyle's, or a bar's own (Bar.barConfig: shadow, shadowColor, shadowSize)
  property var look: BarStyle.look

  shadowEnabled: look.shadow
  shadowColor: BarsConfig.shadowColor(look)
  shadowBlur: 1
  blurMax: look.shadowSize
  maskEnabled: cut
  maskSource: cut ? cutSource : null
  maskInverted: true
  maskThresholdMin: 0.99
  maskSpreadAtMin: 0
}
