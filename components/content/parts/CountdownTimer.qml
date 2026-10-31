pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.methods
import qs.components.reusable

// A countdown to start and run, for the one-off timer (Stopwatch) and
// caffeine (Caffeine), so both look the same. Idle: a duration to type
// ("10m tea") over an even grid of the `presets` (StopwatchClock.parse's
// text), plus the last duration again; set: a TimeRing with the time left,
// and reset, pause or resume and more time, centred in the room it has.
// With `fill` (an overlay card) it takes the height left and sizes the ring
// to it, the ring beside the controls when that room is wide and short
// (`horizontal`). The owner keeps the state (StopwatchClock's timer) and
// acts on the signals.
Item {
  id: root

  // StopwatchClock's timer state
  required property var timer
  required property var presets
  // The time left, how far it's gone (0–1)
  property string text: ""
  property real progress: 0
  // The ring's label while it runs
  property string label: ""
  // Fills the height it's given (an overlay card): the ring grows to it
  property bool fill: false
  // The ring beside the controls rather than over them
  property bool horizontal: root.fill && root.width > root.height * 1.6
  property real dialSize: root.fill ? root._fitDial : Appearance.fontSize * 9
  // The muted icon over the idle part, when a filled one has room for it
  property string idleIcon: "timer"
  // The duration field's hint
  property string placeholderText: I18n.tr("10m, 1h30m, 90s, 10m tea…")
  // The more-time button's ms, and its tooltip
  property real moreTime: 60000
  property string moreTimeText: I18n.tr("One more minute")
  property string resetText: I18n.tr("Reset")

  readonly property bool idle: StopwatchClock.timerIdle(root.timer)

  // Text StopwatchClock.parse reads as a duration
  signal started(string text)
  // Pause ↔ resume; idle, the last duration again
  signal toggled
  signal reset
  signal extended(real ms)

  // The controls grow with the ring (a fifth of it), between their popout
  // size and half again
  readonly property real _bigButton: Math.round(Math.max(Appearance.fontSize * 2.6, Math.min(Appearance.fontSize * 3.9, root.dialSize * 0.2)))
  readonly property real _smallButton: Math.round(root._bigButton * 0.77)
  // The ring that fits beside or over controls `big` across
  function _dialFor(big) {
    const controlsWidth = big * 2.54 + Widget.spacing * 2;
    return Math.max(Appearance.fontSize * 4, Math.min(Appearance.fontSize * 24, root.horizontal ? Math.min(root.height, root.width - controlsWidth - Widget.spacing * 2) : Math.min(root.width, root.height - big - Widget.spacing)));
  }
  // Twice: once with the smallest controls, then with those that ring gets
  readonly property real _fitDial: root._dialFor(Math.max(Appearance.fontSize * 2.6, Math.min(Appearance.fontSize * 3.9, root._dialFor(Appearance.fontSize * 2.6) * 0.2)))

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
    width: root.idle ? (root.fill ? Math.min(root.width, Appearance.fontSize * 30) : root.width) : implicitWidth
    x: Math.round((root.width - width) / 2)
    y: Math.max(0, Math.round((root.height - height) / 2))
    sourceComponent: root.idle ? idleView : setView
  }

  Component {
    id: setView

    GridLayout {
      columns: root.horizontal ? 2 : 1
      columnSpacing: Widget.spacing * 2
      rowSpacing: Widget.spacing

      TimeRing {
        size: root.dialSize
        progress: root.progress
        text: root.text
        label: root.timer.running ? root.label : I18n.tr("Paused")
        running: root.timer.running
      }

      RowLayout {
        Layout.alignment: Qt.AlignCenter
        spacing: Widget.spacing

        FlatIconButton {
          size: root._smallButton
          iconSize: Math.round(root._smallButton * 0.55)
          iconText: "stop"
          tooltipText: root.resetText
          onClicked: root.reset()
        }
        FlatIconButton {
          size: root._bigButton
          iconSize: Math.round(root._bigButton * 0.6)
          iconText: root.timer.running ? "pause" : "play_arrow"
          iconColor: Theme.accent
          tooltipText: root.timer.running ? I18n.tr("Pause") : I18n.tr("Resume")
          onClicked: root.toggled()
        }
        FlatIconButton {
          size: root._smallButton
          iconSize: Math.round(root._smallButton * 0.55)
          iconText: "more_time"
          tooltipText: root.moreTimeText
          onClicked: root.extended(root.moreTime)
        }
      }
    }
  }

  Component {
    id: idleView

    ColumnLayout {
      id: idleColumn

      // The presets, then the last duration again
      readonly property bool hasReplay: root.timer.duration > 0
      readonly property int chips: root.presets.length + (idleColumn.hasReplay ? 1 : 0)
      // As many to a row as fit, then evened out over the rows needed;
      // the same width each, but never under its text
      readonly property int fitColumns: Math.max(1, Math.floor((root.width + Widget.spacing / 2) / (idleColumn.chipWidth + Widget.spacing / 2)))
      readonly property int rows: Math.max(1, Math.ceil(idleColumn.chips / idleColumn.fitColumns))
      readonly property int columns: Math.max(1, Math.ceil(idleColumn.chips / idleColumn.rows))
      // The narrowest a chip may be: room for the last duration's text
      readonly property real chipWidth: Math.max(Appearance.fontSize * 4.5, idleColumn.hasReplay ? replayChip.implicitWidth : 0)
      readonly property real chipHeight: Widget.height - Widget.px(4)
      // Room for the icon: the field and the chips, then the icon's own
      readonly property bool showIcon: root.fill && root.idleIcon !== "" && root.height >= Widget.height + idleColumn.rows * (idleColumn.chipHeight + Widget.spacing / 2) + Widget.spacing * 2 + Appearance.fontSize * 4.2

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
        onAccepted: {
          if (StopwatchClock.parse(durationField.text).ms <= 0)
            return;
          root.started(durationField.text);
          durationField.text = "";
        }
      }

      GridLayout {
        visible: idleColumn.chips > 0
        Layout.fillWidth: true
        columns: idleColumn.columns
        columnSpacing: Widget.spacing / 2
        rowSpacing: Widget.spacing / 2

        Repeater {
          model: root.presets.length
          StyledTextButton {
            required property int index
            readonly property string preset: root.presets[index] ?? ""
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: Math.max(implicitWidth, idleColumn.chipWidth)
            implicitHeight: idleColumn.chipHeight
            text: preset
            onClicked: root.started(preset)
          }
        }
        StyledTextButton {
          id: replayChip
          visible: idleColumn.hasReplay
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          Layout.minimumWidth: Math.max(implicitWidth, idleColumn.chipWidth)
          implicitHeight: idleColumn.chipHeight
          iconText: "replay"
          text: StopwatchClock.format(root.timer.duration, false, true)
          tooltipText: I18n.tr("Again")
          onClicked: root.toggled()
        }
      }
    }
  }
}
