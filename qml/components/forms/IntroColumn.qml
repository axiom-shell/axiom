pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// The body of a card's `x-intro` (the status lines and buttons above its
// rows): a column with the one spacing every intro uses, so no two differ.
ColumnLayout {
  spacing: Widget.spacing
}
