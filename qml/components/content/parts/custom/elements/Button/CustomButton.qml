pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.config
import qs.components.reusable
import qs.components.methods
import qs.components.content.parts.custom

// A custom widget's Button element: an icon and label (each its text field,
// the label, else the action's name unless it has an icon: an icon alone) that run its click action
// (`value` is the {value}; off while the sample, a hold or a failing script
// turns it off, or its Enabled condition fails); with no action it does
// nothing. A `background` fills it in that colour (and `textColor` its text; each can
// change by a rule); `disabled: hide`
// hides it while the script or its Enabled condition has it off (not for a
// hold or a failure). A failed run flashes it and its tooltip says why. With
// `confirm` the first press turns its label into "Confirm?" (red) for 3
// seconds and the second runs it.
CustomElementBase {
  id: root

  // The first press of a `confirm` button was made, until it runs or 3 s pass
  property bool asking: false
  readonly property string label: root.asking ? I18n.tr("Confirm?") : root.bind.label ? root.text("label") : root.bind.icon ? "" : (root.actionFor("click")?.name ?? "")
  readonly property string icon: root.text("icon")
  // Its Enabled condition has it off
  readonly property bool slotOff: !root.allowed
  // The script or the binding has it off
  readonly property bool off: (root.actionFor("click") !== null && !CustomWidgetData.actionEnabled(root.fields?.actions, root.actionFor("click"))) || root.slotOff
  readonly property bool pressable: root.canRun("click") && !root.slotOff
  // Its click action's last run, when it failed
  readonly property var failedRun: root.failed("click")
  // Its background, else null (Auto: the tonal button); the question's red wins
  readonly property var background: root.colorFor("background", null)
  readonly property bool coloured: root.background !== null && !root.asking
  readonly property color fill: root.background ?? Style.fillHighest
  // The text colour (picked or by a rule), else the ink that reads on the
  // background, else null: the button's own
  readonly property var ink: root.colorFor("textColor", root.coloured ? root.inkOn(root.fill) : null)
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

  // One button for every look: Auto is the tonal one; a background (picked
  // or by a rule) fills it, its ink reading on it unless Text color is set
  StyledTextButton {
    id: button
    anchors.fill: parent
    kind: root.asking ? "danger" : "tonal"
    enabled: root.pressable
    ownFill: root.coloured
    inkColor: root.ink
    iconText: root.icon
    text: root.label
    // Fit: two fifths of the box, never below a label; else the shell's text size
    textSize: root.fixedTextSize || Math.max(Style.typeLabel, root.textSizeFor(root.height / 2))
    onClicked: root.press()

    Binding {
      target: button
      property: "color"
      value: root.fill
      when: root.coloured
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
