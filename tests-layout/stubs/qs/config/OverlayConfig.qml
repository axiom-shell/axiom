pragma Singleton
import QtQuick

// Stand-in for qs.config OverlayConfig in the layout harness: the card padding.
QtObject {
  function cardPad(compact, bare) {
    return bare ? 0 : compact ? Widget.cardPadding * 0.75 : Widget.cardPadding * 1.5;
  }
}
