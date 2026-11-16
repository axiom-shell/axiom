pragma Singleton
import QtQuick

// Where a schema field's control goes: on its label's line, or under it.
// One rule for every form field (FieldLine reads it), decided from constant
// widths only (the field's width, the label's one-line width, the control's
// implicit or least width), never from laid-out ones, so it can't loop. The
// tokens `t` come from Widget.fieldTokens: gap, labelLeast, controlLeast,
// controlMax, controlShare, inlineFrom. No file access, processes or
// services.
//
// Kinds: "switch" (always beside), "fixed" (a toggle, a stepper: beside when
// its implicit width and the label's least column fit), "flex" (a dropdown,
// a colour: beside at `controlShare` of the width, at least controlLeast),
// "slider" (beside from inlineFrom), "fill" (beside, filling the rest),
// "block" (never beside).
QtObject {
  id: root

  // What a field of `kind` does in `width`, given the label's one-line
  // width (0: no label) and the control's implicit width (fixed kinds):
  //   inline       the control is on the label's line
  //   controlWidth the control's width when inline (-1: implicit or fill)
  //   fill         the control takes the whole width (stacked) or the rest
  //   align        "end" or "start" for a control narrower than its cell
  function place(kind, width, labelLine, control, t) {
    const out = {
      "inline": false,
      "controlWidth": -1,
      "fill": true,
      "align": kind === "fixed" ? "end" : "start"
    };
    if (!(width > 0) || !(labelLine > 0))
      return out;
    const need = Math.min(labelLine, t.labelLeast);
    let inline = false;
    let controlWidth = -1;
    switch (kind) {
    case "switch":
    case "fill":
      inline = true;
      break;
    case "fixed":
      inline = control + t.gap + need <= width;
      break;
    case "flex":
      controlWidth = root._flexWidth(width, t);
      inline = controlWidth + t.gap + need <= width;
      break;
    case "slider":
      controlWidth = root._flexWidth(width, t);
      inline = width >= t.inlineFrom;
      break;
    }
    if (!inline)
      return {
        "inline": false,
        "controlWidth": -1,
        "fill": true,
        "align": "start"
      };
    return {
      "inline": true,
      "controlWidth": controlWidth,
      "fill": kind === "fill",
      "align": "end"
    };
  }

  // A flexible control's width on the label's line: its share of the field,
  // within [controlLeast, controlMax]
  function _flexWidth(width, t) {
    return Math.max(t.controlLeast, Math.min(t.controlMax, Math.round(width * t.controlShare)));
  }

  // The narrowest a field of `kind` stays usable in (a pair's half)
  function least(kind, labelLine, control, t) {
    if (kind === "fixed")
      return control;
    if (kind === "switch")
      return Math.min(labelLine, t.labelLeast) + t.gap + control;
    return t.controlLeast;
  }

  // Whether two fields side by side, each half `(width - gap) / 2`, both
  // keep their least width
  function pairFits(width, gap, leastA, leastB) {
    return (width - gap) / 2 >= Math.max(leastA, leastB);
  }
}
