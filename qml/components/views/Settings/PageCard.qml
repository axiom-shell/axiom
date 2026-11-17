pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// The settings page's hand-built card (an `x-card`'s QML): a FieldGroup that
// stays open, its body spaced `Style.space2` for what isn't a FormRow
FieldGroup {
  bodySpacing: Style.space2
  foldable: false
}
