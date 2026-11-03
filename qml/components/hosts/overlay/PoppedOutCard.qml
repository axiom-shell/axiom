pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable

// What the overlay shows in place of a page that's in a window of its own
// (PageWindowManager): its icon and name, Bring here (back into the
// overlay) and Go to window. The page itself isn't built here meanwhile.
Item {
  id: root

  required property OverlayGrid grid
  // The page's view type
  required property string type

  implicitWidth: root.grid.unit * 1.3
  implicitHeight: column.implicitHeight + Widget.padding * 8

  ColumnLayout {
    id: column
    anchors.centerIn: parent
    width: parent.width - Widget.padding * 4
    spacing: Widget.spacing

    StyledIcon {
      Layout.alignment: Qt.AlignHCenter
      text: OverlayConfig.viewIcon(root.type)
      textSize: Appearance.fontSize * 3
      textColor: Theme.accent
    }

    StyledText {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: I18n.tr("{0} is open in a window", OverlayConfig.viewLabel({
        "type": root.type
      }, 0))
      font.weight: Font.DemiBold
    }

    StyledText {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: I18n.tr("Edits made there show here too.")
      textColor: Theme.foregroundAlt
    }

    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: Widget.spacing
      spacing: Widget.spacing

      StyledTextButton {
        implicitHeight: Widget.height
        iconText: "pip_exit"
        text: I18n.tr("Bring here")
        onClicked: PageWindowManager.popIn(root.type, false)
      }

      StyledTextButton {
        implicitHeight: Widget.height
        iconText: "jump_to_element"
        text: I18n.tr("Go to window")
        onClicked: {
          ShellManager.closeOverlay();
          PageWindowManager.focus(root.type);
        }
      }
    }
  }
}
