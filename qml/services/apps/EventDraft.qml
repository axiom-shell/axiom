pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// One event being edited: open(draft) loads a CalendarEvents draft
// (newDraft or draftOf) into the fields, save() and remove() go through
// CalendarManager, and `finished` fires once it's done or cancelled. A
// recurring event asks whether a change is for this one or all of them
// (`asking`). Not a singleton: each EventEditor holds its own, except the
// Calendar page's, which is CalendarManager.page.draft so it survives the
// page moving between the overlay and its window.
QtObject {
  id: root

  // An event is open in the editor
  property bool active: false
  // The draft as opened; the fields below are its edits
  property var draft: null
  property string calendar: ""
  property string title: ""
  property string location: ""
  property string description: ""
  property bool allDay: false
  property real start: 0
  property real end: 0
  property string repeat: "none"
  property int reminder: -1

  readonly property bool isNew: !root.draft?.href
  readonly property bool readOnly: !root.isNew && !(CalendarManager.calendar(root.draft?.originalCalendar ?? "")?.writable ?? false)
  property bool busy: false
  property string error: ""
  // "save" | "delete" while asking which of a recurring event's,
  // "confirm" while confirming a single event's delete
  property string asking: ""

  signal finished

  function open(draft) {
    root.draft = draft;
    root.calendar = draft.calendar;
    root.title = draft.title;
    root.location = draft.location;
    root.description = draft.description;
    root.allDay = draft.allDay;
    root.start = draft.start;
    root.end = draft.end;
    root.repeat = draft.repeat;
    root.reminder = draft.reminder;
    root.error = "";
    root.asking = "";
    root.busy = false;
    root.active = true;
  }

  function close() {
    root.active = false;
    root.asking = "";
    root.finished();
  }

  // A new start, the end moving with it (keeping the length)
  function setStart(value) {
    root.end = value + (root.end - root.start);
    root.start = value;
  }

  function _collect() {
    return Object.assign({}, root.draft, {
      "calendar": root.calendar,
      "title": root.title,
      "location": root.location,
      "description": root.description,
      "allDay": root.allDay,
      "start": root.start,
      "end": root.end,
      "repeat": root.repeat,
      "reminder": root.reminder
    });
  }

  function _problemText(problem) {
    switch (problem) {
    case "title":
      return I18n.tr("Give it a title.");
    case "calendar":
      return I18n.tr("Pick a calendar.");
    case "end":
      return I18n.tr("It ends before it starts.");
    }
    return "";
  }

  function save() {
    const draft = root._collect();
    const problems = CalendarEvents.problems(draft);
    if (problems.length > 0) {
      root.error = root._problemText(problems[0]);
      return;
    }
    // A change to the repeat or the calendar is the whole series'
    if (draft.recurring && root.asking === "" && draft.repeat === draft.origRepeat && draft.calendar === draft.originalCalendar) {
      root.asking = "save";
      return;
    }
    root.saveAs("series");
  }

  // Saves for `scope`: "series" or "occurrence"
  function saveAs(scope) {
    root.asking = "";
    root.busy = true;
    root.error = "";
    CalendarManager.save(root._collect(), scope, result => root._answered(result));
  }

  // Asks first: which of a recurring event's, or whether a single one
  function remove() {
    root.asking = root.draft.recurring ? "delete" : "confirm";
  }

  // Deletes for `scope`: "series" or "occurrence"
  function removeAs(scope) {
    root.asking = "";
    root.busy = true;
    const event = CalendarManager.events.find(e => e.href === root.draft.href && e.rid === root.draft.rid) ?? root.draft;
    CalendarManager.remove(Object.assign({}, event, {
      "calendar": root.draft.originalCalendar
    }), scope, result => root._answered(result));
  }

  function _answered(result) {
    if (!root)
      return;
    root.busy = false;
    if (result.ok)
      root.close();
    else
      root.error = CalendarManager.errorText(result);
  }
}
