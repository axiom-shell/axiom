pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable

// Editing an event, held by an EventDraft (`session`: its own, or one a
// page keeps past it): its open(draft) loads a CalendarEvents draft (newDraft
// or draftOf), Save and Delete go through CalendarManager, and `finished`
// fires once it's done or cancelled. A recurring event asks whether a
// change is for this one or all of them. An event in a calendar axiom
// can't change (a subscription, a read-only share) shows read-only.
ColumnLayout {
  id: root

  property EventDraft session: EventDraft {}
  // How wide the buttons along the bottom need it (the fields and texts
  // take any width), so a popout can widen for a long translation
  readonly property real actionsWidth: root.session.asking !== "" ? askRow.implicitWidth - askText.implicitWidth + Appearance.fontSize * 6 : actionRow.implicitWidth

  signal finished

  spacing: Widget.spacing

  // An event opening (or already open when built, by a Loader) starts at
  // the top, and a new one takes the keyboard
  function _opened() {
    fields.contentY = 0;
    if (root.session.isNew)
      Qt.callLater(() => titleEntry.input.forceActiveFocus());
  }
  Component.onCompleted: {
    if (root.session.active)
      root._opened();
  }

  Connections {
    target: root.session
    function onActiveChanged() {
      if (root.session.active)
        root._opened();
    }
    function onFinished() {
      root.finished();
    }
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
        text: root.session.title
        placeholderText: I18n.tr("Title")
        readOnly: root.session.readOnly
        onTextEdited: root.session.title = text
        onAccepted: root.session.save()
      }

      StyledComboEntry {
        Layout.fillWidth: true
        icon: "event"
        readOnly: root.session.readOnly
        options: (root.session.readOnly ? CalendarManager.calendars : CalendarManager.writableCalendars).map(calendar => ({
              "value": calendar.id,
              "label": CalendarConfig.accounts.length > 1 ? I18n.tr("{0} · {1}", calendar.name, calendar.accountName) : calendar.name
            }))
        value: root.session.calendar
        onPicked: value => root.session.calendar = value
      }

      RowLayout {
        Layout.fillWidth: true
        StyledText {
          Layout.fillWidth: true
          text: I18n.tr("All day")
        }
        StyledSwitch {
          checked: root.session.allDay
          enabled: !root.session.readOnly
          onToggled: root.session.allDay = checked
        }
      }

      DateTimeField {
        Layout.fillWidth: true
        label: I18n.tr("Start")
        value: root.session.start
        allDay: root.session.allDay
        readOnly: root.session.readOnly
        onEdited: value => root.session.setStart(value)
      }

      DateTimeField {
        Layout.fillWidth: true
        label: I18n.tr("End")
        value: root.session.end
        allDay: root.session.allDay
        readOnly: root.session.readOnly
        onEdited: value => root.session.end = value
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
          readOnly: root.session.readOnly
          options: {
            const minutes = [-1, 0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080];
            if (!minutes.includes(root.session.reminder))
              minutes.push(root.session.reminder);
            return minutes.sort((a, b) => a - b).map(m => ({
                  "value": String(m),
                  "label": m < 0 ? I18n.tr("None") : m === 0 ? I18n.tr("At the start") : m % 1440 === 0 ? I18n.tr("{0} d before", m / 1440) : m % 60 === 0 ? I18n.tr("{0} h before", m / 60) : I18n.tr("{0} min before", m)
                }));
          }
          value: String(root.session.reminder)
          onPicked: value => root.session.reminder = Number(value)
        }
      }

      // Repeat: the simple rules; one written elsewhere shows as Custom
      // and is kept unless another is picked
      Flow {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        Repeater {
          model: ["none", "daily", "weekly", "monthly", "yearly"].concat(root.session.draft?.origRepeat === "custom" ? ["custom"] : [])
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
            active: root.session.repeat === modelData
            available: !root.session.readOnly && (modelData !== "custom" || root.session.repeat === "custom")
            onClicked: {
              if (available)
                root.session.repeat = modelData;
            }
          }
        }
      }

      StyledTextEntry {
        id: locationEntry
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.height
        text: root.session.location
        placeholderText: I18n.tr("Location")
        readOnly: root.session.readOnly
        onTextEdited: root.session.location = text
      }

      StyledTextArea {
        id: notesArea
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(implicitHeight, Appearance.fontSize * 5)
        text: root.session.description
        placeholderText: I18n.tr("Notes")
        readOnly: root.session.readOnly
        onTextEdited: root.session.description = text
      }
    }
  }

  StyledText {
    visible: root.session.error !== "" || root.session.readOnly
    Layout.fillWidth: true
    text: root.session.error !== "" ? root.session.error : I18n.tr("This calendar can't be changed.")
    textColor: root.session.error !== "" ? Theme.error : Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-1)
    wrapMode: Text.Wrap
  }

  // Which of a recurring event's: this one, or all of them; or a single
  // event's delete confirmed
  RowLayout {
    id: askRow
    visible: root.session.asking !== ""
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      id: askText
      Layout.fillWidth: true
      text: root.session.asking === "confirm" ? I18n.tr("Delete this event?") : root.session.asking === "delete" ? I18n.tr("Delete which?") : I18n.tr("Change which?")
      elide: Text.ElideRight
    }
    StyledTextButton {
      visible: root.session.asking === "confirm"
      text: I18n.tr("Delete")
      iconText: "delete"
      textColor: Theme.error
      onClicked: root.session.removeAs("series")
    }
    StyledTextButton {
      visible: root.session.asking !== "confirm"
      text: I18n.tr("This event")
      onClicked: root.session.asking === "delete" ? root.session.removeAs("occurrence") : root.session.saveAs("occurrence")
    }
    StyledTextButton {
      visible: root.session.asking !== "confirm"
      text: I18n.tr("All events")
      onClicked: root.session.asking === "delete" ? root.session.removeAs("series") : root.session.saveAs("series")
    }
    FlatIconButton {
      iconText: "close"
      onClicked: root.session.asking = ""
    }
  }

  RowLayout {
    id: actionRow
    visible: root.session.asking === ""
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledTextButton {
      visible: !root.session.isNew && !root.session.readOnly
      text: I18n.tr("Delete")
      iconText: "delete"
      textColor: Theme.error
      enabled: !root.session.busy
      onClicked: root.session.remove()
    }
    Item {
      Layout.fillWidth: true
    }
    StyledTextButton {
      text: root.session.readOnly ? I18n.tr("Close") : I18n.tr("Cancel")
      onClicked: root.session.close()
    }
    StyledTextButton {
      visible: !root.session.readOnly
      text: root.session.busy ? I18n.tr("Saving…") : I18n.tr("Save")
      iconText: "check"
      backgroundColor: Theme.accent
      textColor: Theme.background
      enabled: !root.session.busy
      onClicked: root.session.save()
    }
  }
}
