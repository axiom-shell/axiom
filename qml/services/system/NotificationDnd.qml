pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.services.compositor
import qs.services.core

// NotificationManager's do not disturb (its `_dndState`): the user's own
// switch (`manual`, saved by the manager as `dnd`), its schedule, and a window
// rule's hold read from WindowRulesManager; `on` is what DndHold decides.
// A switch by hand (setByHand) sets `manual`, and turning it off while a rule
// holds it also overrides the hold until it ends (the daemon keeps that);
// the schedule sets only `manual`. Until the daemon answers there is no
// hold, so it is just the user's.
QtObject {
  id: root

  // The manager's saved state is loaded: the schedule may act
  property bool ready: false
  // The user's own switch: by hand, or its schedule
  property bool manual: false
  // A window rule holds it, and the user turned it off since
  readonly property bool held: (WindowRulesManager.holds?.dnd ?? []).length > 0
  readonly property bool overridden: WindowRulesManager.state?.overrides?.dnd === true
  readonly property bool on: DndHold.on(root.manual, root.held, root.overridden)

  // Switch it by hand
  function setByHand(on: bool): void {
    const change = DndHold.byHand(on, root.held, root.overridden);
    root.manual = change.manual;
    if (change.override)
      WindowRulesManager.override("dnd");
  }

  // NotificationsConfig.dnd's schedule: on and off at its times; a switch
  // by hand lasts until the next of them
  property DailySchedule _schedule: DailySchedule {
    name: "notificationsDnd"
    enabled: NotificationsConfig.dndSchedule
    ready: root.ready
    startAt: NotificationsConfig.dndStartAt
    endAt: NotificationsConfig.dndEndAt
    onDue: on => root.manual = on
  }
}
