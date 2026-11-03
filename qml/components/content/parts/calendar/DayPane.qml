pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.apps
import qs.components.methods

// A day's events (DayAgenda) that turn into the EventEditor for the one
// clicked, or a new one: what the Calendar popout and module, the Clock &
// calendar module and the Calendar page show beside their month.
// `editing` is true while the editor is up (a popout then takes the
// keyboard). `readOnly` (the lock screen) never opens the editor. The
// event being edited is `session`'s: its own, or one a page keeps past
// it (CalendarManager.page.draft).
Item {
  id: root

  property string dayKey: CalendarEvents.dayKey(new Date())
  property bool closable: false
  property real maxListHeight: Number.POSITIVE_INFINITY
  property bool readOnly: false
  property EventDraft session: EventDraft {}
  readonly property bool editing: root.session.active

  signal closed

  implicitWidth: Math.max(agenda.implicitWidth, Appearance.fontSize * 16)
  implicitHeight: root.editing ? editor.implicitHeight : agenda.implicitHeight
  // How much taller than its laid-out height the editor or agenda can
  // make it, so a popout can make room before the editor opens
  // (Panel.maxImplicitHeight)
  readonly property real growth: root.visible ? Math.max(0, editor.implicitHeight - root.height, agenda.implicitHeight - root.height) : 0
  // How wide the editor's buttons need it (EventEditor.actionsWidth)
  readonly property real actionsWidth: root.editing ? editor.actionsWidth : 0

  function newEvent() {
    if (root.readOnly || !CalendarManager.newEventCalendar)
      return;
    editor.open(CalendarEvents.newDraft(root.dayKey, Date.now(), CalendarManager.newEventCalendar, CalendarConfig.defaultDuration, CalendarConfig.defaultReminder));
  }

  function edit(event) {
    if (root.readOnly)
      return;
    editor.open(CalendarEvents.draftOf(event));
  }

  // Back to the day (a new day shown drops an edit)
  function stopEditing() {
    if (root.editing)
      root.session.close();
  }
  onDayKeyChanged: {
    if (!root.session.busy)
      root.stopEditing();
  }

  DayAgenda {
    id: agenda
    anchors.fill: parent
    visible: !root.editing
    dayKey: root.dayKey
    closable: root.closable
    maxListHeight: root.maxListHeight
    readOnly: root.readOnly
    onEventClicked: event => root.edit(event)
    onAddClicked: root.newEvent()
    onClosed: root.closed()
  }

  EventEditor {
    id: editor
    anchors.fill: parent
    visible: root.editing
    session: root.session
  }
}
