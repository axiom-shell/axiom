pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// A TimeRing over (or beside, `horizontal`) three round buttons: a main one
// filled in the ring's colour between two tonal ones, the running view of
// the one-off timer and caffeine (CountdownTimer) and the stopwatch
// (Stopwatch). With `fill` (an overlay card) the ring and buttons grow to
// the room it's given; either way they're centred in it. With `steps`, the
// wheel over the ring and + / - step the time (`stepped(±1)`); with
// `choices`, a right click or long press on the right button swaps the
// buttons for them (`chosen(value)`). Clicked, it takes the keyboard:
// Space is the main button, `leftKey` / `rightKey` the others.
Item {
  id: root

  // The ring
  property real progress: 0
  property string text: ""
  property string label: ""
  property bool running: false
  property bool urgent: false
  property color color: Theme.accent
  // How often progress moves (ms), the ring sweeping between
  property int tick: 1000

  // The buttons: Material Symbols, tooltips
  property string leftIcon: "stop"
  property string leftTip: ""
  property bool leftEnabled: true
  property string mainIcon: "play_arrow"
  property string mainTip: ""
  property string rightIcon: ""
  property string rightTip: ""
  property bool rightEnabled: true
  property int leftKey: Qt.Key_R
  property int rightKey: 0

  // The wheel and + / - step the time
  property bool steps: false
  // [{ label, value }] offered by a right click on the right button
  property var choices: []

  // Fills the room it's given (an overlay card): the ring grows to it
  property bool fill: false
  // The ring beside the buttons rather than over them
  property bool horizontal: root.fill && root.width > root.height * 1.6
  property real dialSize: root.fill ? root._fitDial : Appearance.fontSize * 9

  signal leftClicked
  signal mainClicked
  signal rightClicked
  signal stepped(int direction)
  signal chosen(var value)

  // Showing the choices instead of the buttons
  property bool choosing: false

  // The buttons grow with the ring (a fifth of it), between their popout
  // size and half again
  readonly property real bigButton: Math.round(Math.max(Appearance.fontSize * 2.6, Math.min(Appearance.fontSize * 3.9, root.dialSize * 0.2)))
  readonly property real smallButton: Math.round(root.bigButton * 0.85)
  // The ring that fits beside or over buttons `big` across
  function _dialFor(big) {
    const controlsWidth = big * 2.7 + Widget.spacing * 2;
    return Math.max(Appearance.fontSize * 4, Math.min(Appearance.fontSize * 24, root.horizontal ? Math.min(root.height, root.width - controlsWidth - Widget.spacing * 2) : Math.min(root.width, root.height - big - Widget.spacing)));
  }
  // Twice: once with the smallest buttons, then with those that ring gets
  readonly property real _fitDial: root._dialFor(Math.max(Appearance.fontSize * 2.6, Math.min(Appearance.fontSize * 3.9, root._dialFor(Appearance.fontSize * 2.6) * 0.2)))

  implicitWidth: grid.implicitWidth
  implicitHeight: grid.implicitHeight
  activeFocusOnTab: true

  onRunningChanged: if (!root.running)
    root.choosing = false

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Space) {
      root.mainClicked();
    } else if (root.leftKey !== 0 && event.key === root.leftKey && root.leftEnabled) {
      root.leftClicked();
    } else if (root.rightKey !== 0 && event.key === root.rightKey && root.rightEnabled) {
      root.rightClicked();
    } else if (root.steps && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) {
      root.stepped(1);
    } else if (root.steps && (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore)) {
      root.stepped(-1);
    } else {
      return;
    }
    event.accepted = true;
  }

  // A click anywhere on it (buttons too) gives it the keyboard
  TapHandler {
    gesturePolicy: TapHandler.DragThreshold
    grabPermissions: PointerHandler.ApprovesTakeOverByAnything
    onTapped: root.forceActiveFocus()
  }

  GridLayout {
    id: grid
    x: Math.round((root.width - width) / 2)
    y: Math.max(0, Math.round((root.height - height) / 2))
    columns: root.horizontal ? 2 : 1
    columnSpacing: Widget.spacing * 2
    rowSpacing: Widget.spacing

    TimeRing {
      id: ring
      size: root.dialSize
      progress: root.progress
      text: root.text
      label: root.label
      running: root.running
      urgent: root.urgent
      color: root.color
      tick: root.tick

      // A notch (120) at a time, so a touchpad's small deltas add up
      property real _wheel: 0
      WheelHandler {
        enabled: root.steps
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
          ring._wheel += event.angleDelta.y;
          while (Math.abs(ring._wheel) >= 120) {
            const direction = ring._wheel > 0 ? 1 : -1;
            ring._wheel -= direction * 120;
            root.stepped(direction);
          }
        }
      }
    }

    // The buttons, or the choices in their place (same height, so nothing
    // moves)
    Item {
      Layout.alignment: Qt.AlignCenter
      implicitWidth: root.choosing ? choiceRow.implicitWidth : buttons.implicitWidth
      implicitHeight: root.bigButton

      RowLayout {
        id: buttons
        anchors.centerIn: parent
        visible: !root.choosing
        spacing: Widget.spacing

        FlatIconButton {
          size: root.smallButton
          iconSize: Math.round(root.smallButton * 0.5)
          iconText: root.leftIcon
          tooltipText: root.leftTip
          enabled: root.leftEnabled
          borderRadius: root.smallButton / 2
          backgroundColor: Theme.backgroundAlt
          onClicked: root.leftClicked()
        }
        FlatIconButton {
          size: root.bigButton
          iconSize: Math.round(root.bigButton * 0.55)
          iconText: root.mainIcon
          tooltipText: root.mainTip
          iconColor: Theme.background
          borderRadius: root.bigButton / 2
          backgroundColor: root.color
          hoverColor: Qt.lighter(root.color, 1.12)
          pressColor: Qt.darker(root.color, 1.12)
          onClicked: root.mainClicked()
        }
        FlatIconButton {
          id: rightButton
          size: root.smallButton
          iconSize: Math.round(root.smallButton * 0.5)
          iconText: root.rightIcon
          tooltipText: root.rightTip
          enabled: root.rightEnabled
          borderRadius: root.smallButton / 2
          backgroundColor: Theme.backgroundAlt
          onClicked: root.rightClicked()
          onPressAndHold: root.choosing = root.choices.length > 0

          TapHandler {
            acceptedButtons: Qt.RightButton
            enabled: root.choices.length > 0
            onTapped: root.choosing = true
          }
        }
      }

      Loader {
        id: choiceRow
        anchors.centerIn: parent
        active: root.choosing
        visible: active
        sourceComponent: RowLayout {
          spacing: Widget.spacing / 2

          FlatIconButton {
            size: root.smallButton
            iconSize: Math.round(root.smallButton * 0.5)
            iconText: "arrow_back"
            tooltipText: I18n.tr("Back")
            borderRadius: root.smallButton / 2
            onClicked: root.choosing = false
          }
          Repeater {
            model: root.choices.length
            StyledTextButton {
              required property int index
              readonly property var choice: root.choices[index] ?? {
                "label": "",
                "value": null
              }
              implicitHeight: root.smallButton
              text: choice.label
              onClicked: {
                root.choosing = false;
                root.chosen(choice.value);
              }
            }
          }
        }
      }
    }
  }
}
