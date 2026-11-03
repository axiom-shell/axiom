pragma ComponentBehavior: Bound
import QtQuick

// Builds `sourceComponent` anew whenever `key` changes, and nothing while
// it's empty. For forms whose rows commit when their value changes: one
// reused for another selection would write the old values onto it.
Item {
  id: root

  property string key
  property Component sourceComponent

  Repeater {
    model: root.key === "" ? [] : [root.key]
    delegate: root.sourceComponent
  }
}
