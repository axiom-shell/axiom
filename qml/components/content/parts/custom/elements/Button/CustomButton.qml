pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.reusable
import qs.components.methods
import qs.components.content.parts.custom

// A custom widget's Button element: an icon and label (each from its
// option unless bound, else the action's name) that run its click action
// (`value` is the {value}; off while the sample, a hold or a failing script
// turns it off, or its `enabled` slot is false); with no action it does
// nothing. A `color` makes it a filled Surface in that colour; `disabled: hide`
// hides it while the script or its `enabled` binding has it off (not for a
// hold or a failure). A failed run flashes it and its tooltip says why. With
// `confirm` the first press turns its label into "Confirm?" (red) for 3
// seconds and the second runs it.
CustomElementBase {
  id: root

  // The first press of a `confirm` button was made, until it runs or 3 s pass
  property bool asking: false
  readonly property string label: root.asking ? I18n.tr("Confirm?") : root.bind.label ? root.text("label") : root.options.label || (root.actionFor("click")?.name ?? "")
  readonly property string icon: root.bind.icon ? root.text("icon") : root.options.icon
  // Its `enabled` binding has it off
  readonly property bool slotOff: !!root.bind.enabled && !CustomWidgetData.truthy(root.value("enabled"))
  // The script or the binding has it off
  readonly property bool off: (root.actionFor("click") !== null && !CustomWidgetData.actionEnabled(root.fields?.actions, root.actionFor("click"))) || root.slotOff
  readonly property bool pressable: root.canRun("click") && !root.slotOff
  // Its click action's last run, when it failed
  readonly property var failedRun: root.failed("click")
  readonly property bool coloured: root.options.color !== ""
  readonly property color fill: root.asking ? Style.error : Style.resolve(root.options.color)
  // Held for a moment after a failed run: a blink (a fixed time)
  property bool flashing: false

  visible: !(root.options.disabled === "hide" && root.off)

  function press() {
    if (root.options.confirm && !root.asking) {
      root.asking = true;
      askTimer.restart();
      return;
    }
    root.asking = false;
    askTimer.stop();
    root.runTrigger("click", root.text("value"));
  }

  onFailedRunChanged: {
    if (root.failedRun) {
      root.flashing = true;
      flashTimer.restart();
    }
  }
  // A fixed time: how long the question is open
  Timer {
    id: askTimer
    interval: 3000
    onTriggered: root.asking = false
  }
  Timer {
    id: flashTimer
    interval: 1200
    onTriggered: root.flashing = false
  }

  Loader {
    anchors.fill: parent
    sourceComponent: root.coloured ? filled : plain
  }

  Component {
    id: plain
    StyledTextButton {
      kind: root.asking ? "danger" : "tonal"
      enabled: root.pressable
      iconText: root.icon
      text: root.label
      onClicked: root.press()
    }
  }

  // A colour from the definition: its fill, and the ink that reads on it
  Component {
    id: filled
    Surface {
      id: button
      outlined: false
      color: root.fill
      opacity: root.pressable ? 1 : Style.opacityDisabled

      StateLayer {
        hovered: area.containsMouse && root.pressable
        pressed: area.pressed && root.pressable
        onAccent: true
        radius: button.radius
      }

      RowLayout {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, button.width)
        spacing: Widget.spacing / 2

        StyledIcon {
          visible: root.icon !== ""
          text: root.icon
          textColor: root.inkOn(root.fill)
          textSize: Style.typeLabel
        }
        StyledLabel {
          visible: text !== ""
          text: root.label
          role: "label"
          textColor: root.inkOn(root.fill)
          textSize: Style.typeLabel
          overflow: "line"
          Layout.fillWidth: true
        }
      }

      MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.pressable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.press()
      }
    }
  }

  // A failed run: the box blinks red and says why on hover
  Rectangle {
    anchors.fill: parent
    radius: Style.radius
    color: root.flashing ? Style.errorWash : "transparent"

    ColorGlide on color {
      duration: Appearance.animSlow
      enabled: Appearance.animations
    }
  }

  HoverHandler {
    id: hover
  }
  LazyLoader {
    active: hover.hovered && root.failedRun !== null
    StyledToolTip {
      target: root
      text: root.failedRun?.message ?? ""
    }
  }
}
