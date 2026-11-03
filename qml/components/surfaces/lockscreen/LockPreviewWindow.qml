pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland

import qs.config
import qs.services.session
import qs.components.reusable

// The layouts editor's "Show on screen": the lock screen draft
// (LockManager.editor.localLayout) on the target screen, in a plain Overlay-layer
// window. Nothing is locked and its password field is inert. Escape or a
// click on the background closes it, back to the editor.
PanelWindow {
  id: root

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "axiom-lock-preview"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore
  color: "black"
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  FocusScope {
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: LockManager.editor.stopPreview()

    // Under the surface, so modules keep their own clicks
    MouseArea {
      anchors.fill: parent
      onClicked: LockManager.editor.stopPreview()
    }

    LockSurface {
      screen: root.screen
      layout: LockManager.editor.localLayout
      preview: true
    }

    StatusChip {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: OverlayConfig.cardSpacing
      color: Theme.accent
      text: I18n.tr("Preview: Esc or click to close")
    }
  }
}
