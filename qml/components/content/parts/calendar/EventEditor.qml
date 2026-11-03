pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// Editing an event: open(draft) loads a CalendarEvents draft (newDraft or
// draftOf), Save and Delete go through CalendarManager, and `finished`
// fires once it's done or cancelled. A recurring event asks whether a
// change is for this one or all of them. An event in a calendar axiom
// can't change (a subscription, a read-only share) shows read-only.
ColumnLayout {
  id: root

  // The draft as opened; the fields below are its edits
  property var draft: null
  property string calendar: ""
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
  // How wide the buttons along the bottom need it (the fields and texts
  // take any width), so a popout can widen for a long translation
  readonly property real actionsWidth: root.asking !== "" ? askRow.implicitWidth - askText.implicitWidth + Appearance.fontSize * 6 : actionRow.implicitWidth

  signal finished

  spacing: Widget.spacing

  function open(draft) {
    root.draft = draft;
    root.calendar = draft.calendar;
    root.allDay = draft.allDay;
    root.start = draft.start;
    root.end = draft.end;
    root.repeat = draft.repeat;
    root.reminder = draft.reminder;
    titleEntry.text = draft.title;
    locationEntry.text = draft.location;
    notesArea.text = draft.description;
    root.error = "";
    root.asking = "";
    root.busy = false;
    fields.contentY = 0;
    if (root.isNew)
      Qt.callLater(() => titleEntry.input.forceActiveFocus());
  }

  function _collect() {
    return Object.assign({}, root.draft, {
      "calendar": root.calendar,
      "title": titleEntry.text,
      "location": locationEntry.text,
      "description": notesArea.text,
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
    root._save("series");
  }

  function _save(scope) {
    root.asking = "";
    root.busy = true;
    root.error = "";
    CalendarManager.save(root._collect(), scope, result => {
      if (!root)
        return;
      root.busy = false;
      if (result.ok)
        root.finished();
      else
        root.error = CalendarManager.errorText(result);
    });
  }

  function remove() {
    root.asking = root.draft.recurring ? "delete" : "confirm";
  }

  function _remove(scope) {
    root.asking = "";
    root.busy = true;
    const event = CalendarManager.events.find(e => e.href === root.draft.href && e.rid === root.draft.rid) ?? root.draft;
    CalendarManager.remove(Object.assign({}, event, {
      "calendar": root.draft.originalCalendar
    }), scope, result => {
      if (!root)
        return;
      root.busy = false;
      if (result.ok)
        root.finished();
      else
        root.error = CalendarManager.errorText(result);
    });
  }

  // The fields scroll when the editor is short
  Flickable {
    id: fields
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredHeight: form.implicitHeight
    contentHeight: form.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ColumnLayout {
      id: form
      width: parent.width
      spacing: Widget.spacing

      StyledTextEntry {
        id: titleEntry
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.height
        placeholderText: I18n.tr("Title")
        readOnly: root.readOnly
        onAccepted: root.save()
      }

      // A rule written elsewhere (Custom) can't be carried to another
      // calendar: a move re-creates the event, with a simple rule
      StyledComboEntry {
        Layout.fillWidth: true
        icon: "event"
        readOnly: root.readOnly || root.draft?.origRepeat === "custom"
        options: (root.readOnly ? CalendarManager.calendars : CalendarManager.writableCalendars).map(calendar => ({
              "value": calendar.id,
              "label": CalendarConfig.accounts.length > 1 ? I18n.tr("{0} · {1}", calendar.name, calendar.accountName) : calendar.name
            }))
        value: root.calendar
        onPicked: value => root.calendar = value
      }

      RowLayout {
        Layout.fillWidth: true
        StyledText {
          Layout.fillWidth: true
          text: I18n.tr("All day")
        }
        StyledSwitch {
          checked: root.allDay
          enabled: !root.readOnly
          onToggled: root.allDay = checked
        }
      }

      DateTimeField {
        Layout.fillWidth: true
        label: I18n.tr("Start")
        value: root.start
        allDay: root.allDay
        readOnly: root.readOnly
        // The end moves with the start, keeping the length
        onEdited: value => {
          root.end = value + (root.end - root.start);
          root.start = value;
        }
      }

      DateTimeField {
        Layout.fillWidth: true
        label: I18n.tr("End")
        value: root.end
        allDay: root.allDay
        readOnly: root.readOnly
        onEdited: value => root.end = value
      }

      RowLayout {
        Layout.fillWidth: true
        StyledText {
          Layout.preferredWidth: Appearance.fontSize * 4.5
          text: I18n.tr("Reminder")
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-1)
        }
        StyledComboEntry {
          Layout.fillWidth: true
          icon: "notifications"
          readOnly: root.readOnly
          options: {
            const minutes = [-1, 0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080];
            if (!minutes.includes(root.reminder))
              minutes.push(root.reminder);
            return minutes.sort((a, b) => a - b).map(m => ({
                  "value": String(m),
                  "label": m < 0 ? I18n.tr("None") : m === 0 ? I18n.tr("At the start") : m % 1440 === 0 ? I18n.tr("{0} d before", m / 1440) : m % 60 === 0 ? I18n.tr("{0} h before", m / 60) : I18n.tr("{0} min before", m)
                }));
          }
          value: String(root.reminder)
          onPicked: value => root.reminder = Number(value)
        }
      }

      // Repeat: the simple rules; one written elsewhere shows as Custom
      // and is kept unless another is picked
      Flow {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        Repeater {
          model: ["none", "daily", "weekly", "monthly", "yearly"].concat(root.draft?.origRepeat === "custom" ? ["custom"] : [])
          SegmentButton {
            required property string modelData
            // I18n.tr("Never") I18n.tr("Every day") I18n.tr("Every week") I18n.tr("Every month") I18n.tr("Every year") I18n.tr("Custom")
            text: I18n.tr({
              "none": "Never",
              "daily": "Every day",
              "weekly": "Every week",
              "monthly": "Every month",
              "yearly": "Every year",
              "custom": "Custom"
            }[modelData])
            active: root.repeat === modelData
            available: !root.readOnly && (modelData !== "custom" || root.repeat === "custom")
            onClicked: {
              if (available)
                root.repeat = modelData;
            }
          }
        }
      }

      StyledTextEntry {
        id: locationEntry
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.height
        placeholderText: I18n.tr("Location")
        readOnly: root.readOnly
      }

      StyledTextArea {
        id: notesArea
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(implicitHeight, Appearance.fontSize * 5)
        placeholderText: I18n.tr("Notes")
        readOnly: root.readOnly
      }
    }
  }

  StyledText {
    visible: root.error !== "" || root.readOnly
    Layout.fillWidth: true
    text: root.error !== "" ? root.error : I18n.tr("This calendar can't be changed.")
    textColor: root.error !== "" ? Theme.error : Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.Wrap
  }

  // Which of a recurring event's: this one, or all of them; or a single
  // event's delete confirmed
  RowLayout {
    id: askRow
    visible: root.asking !== ""
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      id: askText
      Layout.fillWidth: true
      text: root.asking === "confirm" ? I18n.tr("Delete this event?") : root.asking === "delete" ? I18n.tr("Delete which?") : I18n.tr("Change which?")
      elide: Text.ElideRight
    }
    StyledTextButton {
      visible: root.asking === "confirm"
      text: I18n.tr("Delete")
      iconText: "delete"
      textColor: Theme.error
      onClicked: root._remove("series")
    }
    StyledTextButton {
      visible: root.asking !== "confirm"
      text: I18n.tr("This event")
      onClicked: root.asking === "delete" ? root._remove("occurrence") : root._save("occurrence")
    }
    StyledTextButton {
      visible: root.asking !== "confirm"
      text: I18n.tr("All events")
      onClicked: root.asking === "delete" ? root._remove("series") : root._save("series")
    }
    FlatIconButton {
      iconText: "close"
      onClicked: root.asking = ""
    }
  }

  RowLayout {
    id: actionRow
    visible: root.asking === ""
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledTextButton {
      visible: !root.isNew && !root.readOnly
      text: I18n.tr("Delete")
      iconText: "delete"
      textColor: Theme.error
      enabled: !root.busy
      onClicked: root.remove()
    }
    Item {
      Layout.fillWidth: true
    }
    StyledTextButton {
      text: root.readOnly ? I18n.tr("Close") : I18n.tr("Cancel")
      onClicked: root.finished()
    }
    StyledTextButton {
      visible: !root.readOnly
      text: root.busy ? I18n.tr("Saving…") : I18n.tr("Save")
      iconText: "check"
      backgroundColor: Theme.accent
      textColor: Theme.background
      enabled: !root.busy
      onClicked: root.save()
    }
  }
}
