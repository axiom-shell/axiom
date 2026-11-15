pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.components.reusable
import qs.config
import qs.services.compositor
import qs.services.ui

// One screen's prompt: its name while MonitorManager identifies, and
// Keep / Revert with the countdown while an applied layout waits
PanelWindow {
  id: root

  readonly property bool asking: MonitorManager.pending
  readonly property bool shown: asking || MonitorManager.identifying
  readonly property int pad: Widget.px(18)

  visible: shown || card.opacity > 0
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  implicitWidth: card.width
  implicitHeight: card.height

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "axiom-monitor-prompt"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // Every focus grab lets input through to it while it shows, so Keep /
  // Revert work over the overlay the Monitors page applied from
  Component.onDestruction: SurfaceManager.unregisterModal(root)

  Component.onCompleted: {
    SurfaceManager.registerModal(root);
    // Where the compositor blurs only what a window asks: the card
    // (attached only there: attached at all, it claims the window's blur,
    // and Hyprland's layer rules no longer blur it)
    if (CompositorManager.supports.blurRegion === true)
      BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.regionsOn(root.screen) ? cardBlur : null);
  }
  BoxBlurRegion {
    id: cardBlur
    target: card
    opacity: card.opacity
  }

  Surface {
    id: card
    tone: "page"

    width: content.implicitWidth + root.pad * 2
    height: content.implicitHeight + root.pad * 2
    border.color: root.asking ? Style.accent : Style.borderSubtle
    opacity: root.shown ? 1 : 0

    Glide on opacity {}

    ColumnLayout {
      id: content
      anchors.centerIn: parent
      spacing: Widget.spacing * 2

      StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: root.screen?.name ?? ""
        textSize: root.asking ? Style.typeBody : Style.typeBody * 3 // fitted: the monitor's number, read from across the room
        font.weight: Style.weightStrong
        tone: root.asking ? "muted" : ""
        overflow: "none"
      }

      StyledText {
        visible: !root.asking
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: Widget.textPx(420)
        text: String(root.screen?.model ?? "").trim()
        tone: "muted"
      }

      StyledText {
        visible: root.asking
        Layout.alignment: Qt.AlignHCenter
        text: I18n.tr("Keep this display layout?")
        Layout.maximumWidth: Widget.textPx(420)
        role: "headline"
      }

      StyledText {
        visible: root.asking
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: Widget.textPx(420)
        text: I18n.tr("Going back in {0} s", MonitorManager.secondsLeft)
        tone: "muted"
      }

      RowLayout {
        visible: root.asking
        Layout.alignment: Qt.AlignHCenter
        spacing: Widget.spacing * 2

        StyledTextButton {
          text: I18n.tr("Revert")
          iconText: "undo"
          implicitHeight: Widget.height
          onClicked: MonitorManager.revert()
        }

        StyledTextButton {
          text: I18n.tr("Keep")
          iconText: "check"
          implicitHeight: Widget.height
          kind: "primary"
          onClicked: MonitorManager.keep()
        }
      }
    }
  }
}
