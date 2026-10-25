pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// How many todos are open (TodoManager). Hovering opens the list, to add
// to and tick off.
BarIconWidget {
  id: root

  hidden: properties.hideWhenEmpty && TodoManager.openCount === 0

  icon: TodoManager.openCount === 0 ? "task_alt" : "checklist"
  text: String(TodoManager.openCount)

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Todo"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && !root.hidden
  }
}
