pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A StyledRectButton that fills with the accent on hover and dims when
// disabled
StyledRectButton {
  opacity: enabled ? 1 : 0.4
  hoverColor: Theme.accent
}
