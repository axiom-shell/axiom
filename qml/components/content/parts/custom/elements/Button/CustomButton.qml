pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components.reusable
import qs.components.methods
import qs.services.apps
import qs.components.content.parts.custom

// A custom widget's Button element: an icon and label (each from its
// option unless bound, else its action's name) that run its named action
// (`value` is the {value}; off while the sample, a hold or a failing script
// turns it off, or its `enabled` slot is false), else its click command
// ({value} is the label); without either, the widget's own click action.
// A `color` makes it a filled Surface in that colour; `disabled: hide`
// hides it while the script or its `enabled` binding has it off (not for a
// hold or a failure). A failed run flashes it and its tooltip says why.
CustomElementBase {
  id: root

  readonly property string label: root.bind.label ? root.text("label") : root.options.label || CustomWidgetsManager.actionLabel(root.actionId) // lock-inert: a name, nothing runs
  readonly property string icon: root.bind.icon ? root.text("icon") : root.options.icon
  // The script or the binding has it off
  readonly property bool off: (root.actionId !== "" && !CustomWidgetData.actionEnabled(root.fields?.actions, root.actionId)) || (!!root.bind.enabled && !CustomWidgetData.truthy(root.value("enabled")))
  readonly property bool pressable: root.canRun && !(!!root.bind.enabled && !CustomWidgetData.truthy(root.value("enabled")))
  readonly property bool coloured: root.options.color !== ""
  readonly property color fill: Style.resolve(root.options.color)
  // Held for a moment after a failed run: a blink (a fixed time)
  property bool flashing: false

  visible: !(root.options.disabled === "hide" && root.off)

  function press() {
    if (root.actionId !== "")
      root.run("click", root.text("value"));
    else if (root.actions.click !== "")
      root.act("click", root.label);
    else
      CustomWidgetsManager.act(root.widgetId, "click"); // lock-inert: the button is disabled without actionsEnabled
  }

  onFailedChanged: {
    if (root.failed) {
      root.flashing = true;
      flashTimer.restart();
    }
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
    active: hover.hovered && root.failed !== null
    StyledToolTip {
      target: root
      text: root.failed?.message ?? ""
    }
  }
}
