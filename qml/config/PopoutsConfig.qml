pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// Reader for the Popouts section: behaviour shared by bar popouts and
// screen-edge popouts. (Named PopoutsConfig because `Popouts` is the bar
// popout wrapper type.)
QtObject {
  readonly property var _c: ConfigManager.live.Popouts

  readonly property int openDelay: _c.timing.openDelay
  readonly property int dismissDelay: _c.timing.closeDelay
  // Space between a popout's box (inside its stroke) and its content
  readonly property int padding: Widget.px(_c.padding)

  // How a bar popout lays out and draws on `screen` at its Size (`sizing`:
  // its widget's `popout.sizing`, or null for none), as a menu's layoutOf does
  // (arguments in OverlayConfig.layoutFor's order):
  //   zoom  what its content is drawn at (its Content size, less what it
  //         takes to fit)
  //   unit  the card size its content lays out at, for content laid out in
  //         cards (CustomWidget): the drawn card over the zoom before the
  //         fit, so neither it nor the content's size depends on the fit
  //   fit   the factor, at most 1, both are shrunk by so the content, at
  //         `content` ({ width, height }: the most its layout size will be)
  //         drawn at its zoom, fits `room` ({ width, height }: the screen's
  //         px for it, which must not depend on the popout's own box)
  function layoutFor(screen, content, room, sizing) {
    const card = screen ? OverlayConfig.cardUnitOn(screen.width, screen.height) : GridPlacement.cardUnit;
    return Sizing.popoutLayout(sizing, card, content, room);
  }
}
