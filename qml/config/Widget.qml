pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

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

  // Height of buttons, fields and other controls: the density's, or what
  // the font's line needs (StyleTokens.controlHeight)
  readonly property int height: StyleTokens.controlHeight(Math.round(_density.height * scale), Appearance.fontSize, px(1))
  // Inner padding of panels, cards and controls
  readonly property int padding: Math.round(_density.padding * scale)
  // Gap between items inside panels, cards and controls
  readonly property int spacing: Math.round(_density.spacing * scale)
  // A module card's padding (OverlayConfig.cardPad)
  readonly property int cardPadding: Math.round(_density.card * scale)
  // Side of a square icon button (StyledIconButton's default size): the
  // density's, or what its icon needs
  readonly property int iconButton: Math.max(Math.round(_density.iconButton * scale), Appearance.fontSize + 2 * px(4))
  // Height of a compact control beside a full one (a list row's action, a
  // lane's tool button, a renaming field): a little under `height`
  readonly property int compactHeight: height - px(6)
  // A switch's or segmented row's track, a chip or button sized to sit in a
  // full-height line
  readonly property int slimHeight: height - px(4)
  // Height of chips, pills and small buttons (keybind chips, a
  // notification's actions): the density's, or what a micro line needs
  readonly property int smallHeight: StyleTokens.controlHeight(Math.round(_density.smallHeight * scale), Appearance.fontSizeBy(-3), 0)
  // Inner margins of rows, fields and dropdowns
  readonly property int smallPadding: Math.round(_density.smallPadding * scale)

  // A size that isn't a control's, padding or gap (a panel's width, an
  // avatar, a dot) at the Interface scale. Bars never use it: they size
  // their own widgets
  function px(n: real): int {
    return Math.round(n * scale);
  }
  // A width that holds text (N characters at the default font): follows the
  // Interface scale and the font size; equal to px(n) at 14 px
  function textPx(n: real): int {
    return StyleTokens.textPx(n, scale, Appearance.baseFontSize);
  }
  // A slider goes beside its label only on a form field at least this wide
  // (FieldFit); narrower it stacks under the label
  readonly property int fieldInlineFrom: textPx(420)
  // The least width of a form field's label column (a longer label wraps)
  readonly property int fieldLabelLeast: textPx(160)
  // The least width of a dropdown or colour box on its label's line
  readonly property int fieldControlLeast: textPx(120)
  // What FieldFit places a field by (FieldLine passes it): gap, labelLeast,
  // controlLeast, controlMax (the widest a box beside its label gets),
  // controlShare (its share of the field), inlineFrom
  readonly property var fieldTokens: ({
      "gap": spacing * 2,
      "labelLeast": fieldLabelLeast,
      "controlLeast": fieldControlLeast,
      "controlMax": textPx(260),
      "controlShare": 0.42,
      "inlineFrom": fieldInlineFrom
    })
  // Corners of what sits inside something (cards, controls, rows, bar
  // widgets); outer edges use Appearance.borderRadius
  // (Appearance.innerRadius)
  readonly property int radius: Appearance.innerRadius
}
