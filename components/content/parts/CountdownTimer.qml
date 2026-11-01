pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.methods
import qs.components.reusable

// A countdown to start and run, for the one-off timer (Stopwatch) and
// caffeine (Caffeine), so both look the same. Idle: a duration to type
// ("10m tea", "at 17:30"), what it reads as at its end, over even rows
// (ChipRows) of the `presets` (StopwatchClock.parse's text) and the
// `recent` ones that aren't presets; set: DialControls with the time left,
// the label or when it ends, and reset, pause or resume and more time (a
// right click offers `moreChoices`; the wheel and + / - step by
// `wheelStep`). With `fill` (an overlay card) it takes the height left and
// sizes the ring to it. The owner keeps the state (StopwatchClock's timer)
// and acts on the signals.
Item {
  id: root

  // StopwatchClock's timer state
  required property var timer
  required property var presets
  // [{ ms, label }], the newest first
  property var recent: []
  // The time left (text, ms), how far it's gone (0–1)
  property string text: ""
  property real remaining: 0
  property real progress: 0
  // The ring's label while it runs; with none, endLabelOf(the end time)
  property string label: ""
  property var endLabelOf: time => I18n.tr("Ends {0}", time)
  // Fills the height it's given (an overlay card): the ring grows to it
  property bool fill: false
  // The muted icon over the idle part, when a filled one has room for it
  property string idleIcon: "timer"
  // The duration field's hint
  property string placeholderText: I18n.tr("10m, 1h30m, at 17:30, 10m tea…")
  // The more-time button's ms and its tooltip, the right click's other
  // amounts, and the wheel's step
  property real moreTime: 60000
  property string moreTimeText: I18n.tr("One more minute")
  property var moreChoices: [5 * 60000, 10 * 60000, 30 * 60000]
  property real wheelStep: 60000
  property string resetText: I18n.tr("Reset")

  readonly property bool idle: StopwatchClock.timerIdle(root.timer)
  // The last minute (or fifth, if shorter)
  readonly property bool urgent: root.timer.running && root.remaining > 0 && root.remaining <= Math.min(60000, root.timer.duration * 0.2)

  // Text StopwatchClock.parse reads as a duration
  signal started(string text)
  // Pause ↔ resume; idle, the last duration again
  signal toggled
  signal reset
  // More time, or less (negative)
  signal extended(real ms)

  // Started from the field: the dial takes the keyboard once it shows
  property bool _focusDial: false

  function _endTime() {
    const end = root.timer.endsAt;
    return end > 0 ? I18n.formatDate(new Date(end), CalendarConfig.timeFormat) : "";
  }

  Layout.fillWidth: true
  Layout.fillHeight: root.fill
  // Filling: whatever is left, never what the ring asks (it's sized from it)
  Layout.preferredHeight: root.fill ? 0 : -1
  implicitWidth: view.implicitWidth
  implicitHeight: view.implicitHeight

  // Centred in the room; the idle part spans the width
  Loader {
    id: view
    // (a filled idle one no wider than a field needs to be)
    width: root.idle ? (root.fill ? Math.min(root.width, Appearance.fontSize * 30) : root.width) : root.width
    height: root.idle ? implicitHeight : root.height
    x: Math.round((root.width - width) / 2)
    y: root.idle ? Math.max(0, Math.round((root.height - height) / 2)) : 0
    sourceComponent: root.idle ? idleView : setView
  }

  Component {
    id: setView

    DialControls {
      id: dial
      fill: root.fill
      progress: root.progress
      text: root.text
      label: !root.timer.running ? I18n.tr("Paused") : root.label !== "" ? root.label : root.endLabelOf(root._endTime())
      running: root.timer.running
      urgent: root.urgent
      leftIcon: "stop"
      leftTip: root.resetText
      mainIcon: root.timer.running ? "pause" : "play_arrow"
      mainTip: root.timer.running ? I18n.tr("Pause") : I18n.tr("Resume")
      rightIcon: "more_time"
      rightTip: root.moreChoices.length > 0 ? I18n.tr("{0} (right-click for more)", root.moreTimeText) : root.moreTimeText
      steps: true
      choices: root.moreChoices.map(ms => ({
            "label": "+" + StopwatchClock.formatShort(ms),
            "value": ms
          }))
      onLeftClicked: root.reset()
      onMainClicked: root.toggled()
      onRightClicked: root.extended(root.moreTime)
      onStepped: direction => root.extended(direction * root.wheelStep)
      onChosen: value => root.extended(value)

      Component.onCompleted: {
        if (root._focusDial)
          dial.forceActiveFocus();
        root._focusDial = false;
      }
    }
  }

  Component {
    id: idleView

    ColumnLayout {
      id: idleColumn

      // The recent timers that aren't presets, newest first, at most 3
      readonly property var presetKeys: root.presets.map(p => {
        const parsed = StopwatchClock.parse(p);
        return parsed.ms + "|" + parsed.label;
      })
      readonly property var recentShown: root.recent.filter(r => !idleColumn.presetKeys.includes(r.ms + "|" + r.label)).slice(0, 3)
      readonly property int chips: root.presets.length + idleColumn.recentShown.length
      // As many to a row as fit, then evened out over the rows (ChipRows)
      readonly property real chipWidth: Appearance.fontSize * 4.5
      readonly property int fit: Math.max(1, Math.floor((root.width + Widget.spacing / 2) / (idleColumn.chipWidth + Widget.spacing / 2)))
      readonly property var rowSizes: ChipRows.split(idleColumn.chips, idleColumn.fit)
      readonly property var rowStarts: ChipRows.starts(idleColumn.rowSizes)
      readonly property real chipHeight: Widget.height - Widget.px(4)
      // What the field reads as: { ms, label }
      property var typed: ({
          "ms": 0,
          "label": ""
        })
      property bool hasText: false
      // Room for the icon: the field and the chips, then the icon's own
      readonly property bool showIcon: root.fill && root.idleIcon !== "" && root.height >= Widget.height + idleColumn.rowSizes.length * (idleColumn.chipHeight + Widget.spacing / 2) + Widget.spacing * 2 + Appearance.fontSize * 4.2

      // The chip at `i`: a preset's text, or a recent { ms, label } as text
      function chipText(i) {
        if (i < root.presets.length)
          return root.presets[i] ?? "";
        const r = idleColumn.recentShown[i - root.presets.length];
        return r ? (StopwatchClock.formatShort(r.ms) + (r.label !== "" ? " " + r.label : "")) : "";
      }

      spacing: Widget.spacing

      StyledIcon {
        visible: idleColumn.showIcon
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: Widget.spacing / 2
        text: root.idleIcon
        textSize: Appearance.fontSize * 3.2
        opacity: 0.4
      }

      StyledTextEntry {
        id: durationField
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.height
        placeholderText: root.placeholderText
        // Typed text stops short of what it reads as
        input.rightPadding: preview.visible ? preview.width + Widget.spacing : 0
        onTextEdited: {
          idleColumn.hasText = durationField.text.trim() !== "";
          idleColumn.typed = StopwatchClock.parse(durationField.text, Date.now());
        }
        onAccepted: {
          if (StopwatchClock.parse(durationField.text, Date.now()).ms <= 0)
            return;
          root._focusDial = true;
          root.started(durationField.text);
          durationField.text = "";
        }

        // What it reads as, or that it doesn't, at the field's end
        StyledText {
          id: preview
          visible: idleColumn.hasText
          anchors.right: parent.right
          anchors.rightMargin: Widget.padding
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, durationField.width * 0.6)
          elide: Text.ElideLeft
          textSize: Appearance.fontSizeBy(-1)
          textColor: idleColumn.typed.ms > 0 ? Theme.foregroundAlt : Theme.error
          text: idleColumn.typed.ms > 0 ? I18n.tr("{0} · ends {1}", StopwatchClock.formatShort(idleColumn.typed.ms), I18n.formatDate(new Date(Date.now() + idleColumn.typed.ms), CalendarConfig.timeFormat)) : I18n.tr("Not a duration")
        }
      }

      // The chips, evenly over the rows, each row filling the width
      ColumnLayout {
        visible: idleColumn.chips > 0
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        Repeater {
          model: idleColumn.rowSizes.length
          RowLayout {
            id: chipRow
            required property int index
            readonly property int first: idleColumn.rowStarts[index] ?? 0
            Layout.fillWidth: true
            spacing: Widget.spacing / 2

            Repeater {
              model: idleColumn.rowSizes[chipRow.index] ?? 0
              StyledTextButton {
                required property int index
                readonly property int chip: chipRow.first + index
                readonly property bool isRecent: chip >= root.presets.length
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.minimumWidth: implicitWidth
                implicitHeight: idleColumn.chipHeight
                iconText: isRecent ? "history" : ""
                text: idleColumn.chipText(chip)
                tooltipText: isRecent ? I18n.tr("Again") : ""
                onClicked: {
                  root._focusDial = true;
                  root.started(idleColumn.chipText(chip));
                }
              }
            }
          }
        }
      }
    }
  }
}
