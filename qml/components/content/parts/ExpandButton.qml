pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// A strip's button growing its detail (`type`, by default the module's own
// full form) over the grid (Card/Panel.expand); hidden where nothing can
// show it
FlatIconButton {
  id: root

  // The module (a Card or Panel) it belongs to
  required property var module
  property string type: ""
  property var properties: ({})

  visible: root.type !== "" && root.module.canExpand(root.type)
  iconText: "open_in_full"
  tooltipText: I18n.tr("More")
  onClicked: root.module.expand(root.type, root.properties, root.module)
}
