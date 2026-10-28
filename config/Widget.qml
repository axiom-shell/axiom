pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Interface section (named Widget, as every size outside
// the bars is Widget.<size>): sizing for panels, cards, popouts and
// controls, and the card size every module grid starts from. Bars size
// their own widgets (BarsConfig.enrichBarConfig).
QtObject {
  readonly property var _c: ConfigManager.live.Interface

  // The Interface scale, as a factor: text (Appearance.fontSize) and the
  // sizes below grow with it
  readonly property real scale: _c.scale / 100
  // How big module cards are, in % of two filling the screen's short
  // side (OverlayConfig.cardUnitOn)
  readonly property int cardSize: _c.cardSize
  // "compact" | "normal" | "roomy"
  readonly property string density: _c.density

  // Each density's sizes (px, at 100 % scale): control height, padding,
  // spacing, card padding, square icon button, small height, small padding
  readonly property var _densities: ({
      "compact": {
        "height": 26,
        "padding": 7,
        "spacing": 3,
        "card": 9,
        "iconButton": 24,
        "smallHeight": 18,
        "smallPadding": 5
      },
      "normal": {
        "height": 30,
        "padding": 10,
        "spacing": 4,
        "card": 12,
        "iconButton": 28,
        "smallHeight": 20,
        "smallPadding": 6
      },
      "roomy": {
        "height": 36,
        "padding": 14,
        "spacing": 6,
        "card": 16,
        "iconButton": 32,
        "smallHeight": 24,
        "smallPadding": 9
      }
    })
  readonly property var _density: _densities[density]

  // Height of buttons, fields and other controls
  readonly property int height: Math.round(_density.height * scale)
  // Inner padding of panels, cards and controls
  readonly property int padding: Math.round(_density.padding * scale)
  // Gap between items inside panels, cards and controls
  readonly property int spacing: Math.round(_density.spacing * scale)
  // A module card's padding (OverlayConfig.cardPad)
  readonly property int cardPadding: Math.round(_density.card * scale)
  // Side of a square icon button (FlatIconButton)
  readonly property int iconButton: Math.round(_density.iconButton * scale)
  // Height of chips, pills and small buttons (keybind chips, a
  // notification's actions)
  readonly property int smallHeight: Math.round(_density.smallHeight * scale)
  // Inner margins of rows, fields and dropdowns
  readonly property int smallPadding: Math.round(_density.smallPadding * scale)

  // A size that isn't a control's, padding or gap (a panel's width, an
  // avatar, a dot) at the Interface scale. Bars never use it: they size
  // their own widgets
  function px(n: real): int {
    return Math.round(n * scale);
  }
  // Corners of what sits inside something (cards, controls, rows, bar
  // widgets); outer edges use Appearance.borderRadius
  // (null: the main radius, Appearance's: x-inherit)
  readonly property int radius: _c.radius !== null ? _c.radius : Appearance.borderRadius
}
