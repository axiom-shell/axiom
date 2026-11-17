pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The frame of a text field or a field-like trigger: a sunken, outlined
// Surface whose border follows `active` (accent, the focus width) and
// `invalid` (error, the focus width; wins over active). StyledTextEntry and
// StyledTextArea draw through it; a field-like button (a picker's trigger, a
// key recorder) takes it for the same look. A caller makes it frameless with
// `color: "transparent"; outlined: false`.
Surface {
  id: root

  // Focused / being edited: the accent border
  property bool active: false
  // Its value is refused: the error border
  property bool invalid: false

  tone: "sunken"
  outlined: true
  border.width: root.outlined ? (root.active || root.invalid ? Style.focusWidth : Style.hairline) : 0
  border.color: root.invalid ? Style.error : root.active ? Style.accent : Style.borderStrong

  ColorGlide on border.color {
    duration: Appearance.animNormal
  }
}
