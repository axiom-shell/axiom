pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// The muted line under a Size row (SchemaPropertiesForm.fieldNote) saying
// what the surface's sizing comes to: `own` (its `sizing`) against the
// Look & Feel Card and Content sizes (the numbers: Sizing.breakdown), and
// what shrinks it (`fit`: { screen, scale, capped, card }, an entry of
// OverlayManager.fitOf or the same for a menu or a screen layout; null for
// none, a popout's is only known per open). Shared by the Layouts editor's
// targets (EditTarget.sizingNote) and the bar editor's widget popouts.
QtObject {
  id: root

  // The surface's `sizing` ({ cardSize, linked, contentSize }, or { contentSize } alone)
  property var own: null
  // What shrinks it, or null
  property var fit: null

  // The Look & Feel sizes in %
  readonly property var _global: ({
      "card": Widget.cardSize,
      "content": Widget.contentSize
    })
  readonly property var _breakdown: Sizing.breakdown(root.own, root._global, root.fit?.scale ?? null, root.fit?.capped ?? false)

  // The line for the Size row `key` (cardSize, or contentSize where it
  // shows), "" for a row that has none. A linked sizing's one line sits
  // under Card size; unlinked, each row says its own
  function lineFor(key) {
    const b = root._breakdown;
    let text = "";
    if (b.kind === "zoom" && key === "contentSize")
      text = I18n.tr("Content at {0}% ({1}% × {2}% here); cards zoom with it", b.content.total, b.content.global, b.content.here);
    else if (b.kind === "linked" && key === "cardSize")
      text = I18n.tr("Cards at {0}% ({1}% × {2}% here), content at {3}% ({4}% × {2}% here)", b.card.total, b.card.global, b.card.here, b.content.total, b.content.global);
    else if (b.kind === "following" && key === "cardSize")
      text = I18n.tr("Cards at {0}% and content at {1}%, as in Look & Feel", b.card.total, b.content.total);
    else if (b.kind === "unlinked" && key === "cardSize")
      text = I18n.tr("Cards at {0}% ({1}% × {2}% here)", b.card.total, b.card.global, b.card.here);
    else if (b.kind === "unlinked" && key === "contentSize")
      text = I18n.tr("Content at {0}% ({1}% × {2}% here)", b.content.total, b.content.global, b.content.here);
    // The cards' px and the fit go with the row that says the cards' size
    // (a zoomed surface's one row, else Card size)
    if (text === "" || (key === "contentSize" && b.kind !== "zoom"))
      return text;
    const parts = [text];
    if (root.fit?.card)
      parts.push(b.capped ? I18n.tr("Capped at two cards high ({0} px)", root.fit.card) : I18n.tr("Cards {0} px", root.fit.card));
    if (b.shrunk)
      parts.push(I18n.tr("Shrunk to {0}% to fit {1}", b.shrunkTo, root.fit.screen));
    return parts.join(" · ");
  }

  // The line for a module's Content size row (`contentSize`: its own, a %
  // or null): the surface's own content factor and the module's, with a
  // shrink clause when the surface is shrunk
  function moduleLine(contentSize) {
    const b = Sizing.moduleBreakdown(root.own, root._global, root.fit?.scale ?? null, contentSize);
    const text = I18n.tr("Content at {0}% ({1}% × {2}% here × {3}% this module)", b.total, b.global, b.here, b.module);
    return b.shrunk ? text + " · " + I18n.tr("Shrunk to {0}% to fit {1}", b.shrunkTo, root.fit.screen) : text;
  }

  // The line for the form row at `path` (SchemaPropertiesForm.fieldNote): a
  // Size row's, else none
  function noteFor(path) {
    return path[path.length - 2] === "sizing" ? root.lineFor(path[path.length - 1]) : "";
  }
}
