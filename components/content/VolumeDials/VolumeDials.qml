pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.content.base

// Output and microphone volume as two dials: scroll to adjust, click to
// mute. Side by side in wide and square slots, stacked in tall ones, each
// labelled where there's room; compact shows the output only.
Card {
  id: root

  component Dial: Item {
    id: dial
    property real level: 0
    property bool muted: false
    property string icon
    property string label
    signal toggled
    signal stepped(real delta)

    // The label beside the dial in a wide cell, under it otherwise, and
    // only where it has room
    readonly property bool beside: dial.width > dial.height * 1.8
    readonly property bool labelled: !root.compact && (dial.beside ? dial.width - dial.height >= Appearance.fontSize * 5 : dial.width >= Appearance.fontSize * 5 && dial.height >= Appearance.fontSize * 5)
    readonly property real side: Math.max(0, dial.beside ? Math.min(dial.height, dial.width * 0.5) : Math.min(dial.width, dial.height - (dial.labelled ? dialLabel.implicitHeight + dial.gap : 0)))
    readonly property real gap: Widget.spacing * 2

    // The dial and its label, kept together and centred
    GridLayout {
      anchors.centerIn: parent
      columns: dial.beside ? 2 : 1
      columnSpacing: dial.gap
      rowSpacing: dial.gap
      PercentageCircle {
        Layout.alignment: Qt.AlignCenter
        Layout.preferredWidth: dial.side
        Layout.preferredHeight: dial.side
        percentage: dial.muted ? 0 : Math.round(dial.level * 100)
        iconText: dial.icon
        iconColor: dial.muted ? Theme.error : Theme.foreground
        fillColor: Theme.accent
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: dial.toggled()
          onWheel: wheel => dial.stepped(wheel.angleDelta.y > 0 ? 0.05 : -0.05)
        }
      }
      StyledText {
        id: dialLabel
        visible: dial.labelled
        Layout.alignment: Qt.AlignCenter
        Layout.maximumWidth: dial.beside ? dial.width - dial.side - dial.gap : dial.width
        elide: Text.ElideRight
        text: dial.muted ? I18n.tr("{0} · muted", dial.label) : `${dial.label} · ${Math.round(dial.level * 100)}%`
        textSize: Appearance.fontSizeBy(-1)
        opacity: 0.8
      }
    }
  }

  GridLayout {
    anchors.fill: parent
    anchors.margins: root.pad
    columns: root.shape === "vertical" ? 1 : 2
    columnSpacing: root.pad
    rowSpacing: root.pad

    Dial {
      Layout.fillWidth: true
      Layout.fillHeight: true
      level: AudioManager.volume
      muted: AudioManager.muted
      icon: AudioManager.muted ? "volume_off" : "volume_up"
      label: I18n.tr("Output")
      onToggled: AudioManager.toggleMute()
      onStepped: delta => AudioManager.stepNodeVolume(AudioManager.defaultSink, delta)
    }
    Dial {
      visible: !root.compact
      Layout.fillWidth: true
      Layout.fillHeight: true
      level: AudioManager.sourceVolume
      muted: AudioManager.sourceMuted
      icon: AudioManager.sourceMuted ? "mic_off" : "mic"
      label: I18n.tr("Input")
      onToggled: AudioManager.toggleSourceMute()
      onStepped: delta => AudioManager.stepNodeVolume(AudioManager.defaultSource, delta)
    }
  }
}
