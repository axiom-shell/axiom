pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config

// Two OptionCards side by side: equal halves, each as tall as the taller
// one, so a short description doesn't leave one card shorter than its
// neighbour
RowLayout {
  id: root

  Layout.fillWidth: true
  spacing: Widget.spacing
  uniformCellSizes: true

  Component.onCompleted: {
    for (const card of root.children)
      card.Layout.fillHeight = true;
  }
}
