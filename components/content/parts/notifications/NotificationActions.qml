pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.config
import qs.components.reusable

// A notification's action buttons (all but the default one and the inline
// reply's) as pills, scrolling sideways when they don't fit; emits invoked
// after running one. When the app sends action icons each identifier is an
// icon name: the pill shows the icon, its label as a tooltip.
Flickable {
  id: root

  required property var notification

  signal invoked

  readonly property var actions: (notification?.actions ?? []).filter(a => a.identifier !== "default" && a.identifier !== "inline-reply")
  readonly property bool icons: notification?.hasActionIcons ?? false

  Layout.fillWidth: true
  visible: root.actions.length > 0
  implicitHeight: actionRow.implicitHeight
  contentWidth: actionRow.implicitWidth
  interactive: contentWidth > width
  flickableDirection: Flickable.HorizontalFlick
  clip: true

  RowLayout {
    id: actionRow
    spacing: Widget.spacing / 2

    Repeater {
      model: root.actions

      Rectangle {
        id: pill
        required property var modelData

        // The action's icon, when the app sends them and the theme has it
        readonly property string iconSource: root.icons ? Quickshell.iconPath(pill.modelData.identifier, true) : ""
        readonly property bool showIcon: pill.iconSource !== "" && icon.status !== Image.Error

        implicitWidth: (pill.showIcon ? icon.width : label.implicitWidth) + Widget.padding * 2
        implicitHeight: label.implicitHeight + Widget.padding
        radius: height / 2
        color: area.containsMouse ? Theme.accent : Theme.backgroundHighlight
        scale: area.pressed ? 0.95 : 1

        ColorGlide on color {}
        Glide on scale {}

        IconImage {
          id: icon
          anchors.centerIn: parent
          visible: pill.showIcon
          width: label.implicitHeight
          height: width
          source: pill.iconSource
        }

        StyledText {
          id: label
          visible: !pill.showIcon
          anchors.centerIn: parent
          text: pill.modelData.text
          textSize: Appearance.fontSizeBy(-2)
          textColor: area.containsMouse ? Theme.background : Theme.foreground
        }

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            pill.modelData.invoke();
            root.invoked();
          }
        }

        LazyLoader {
          active: pill.showIcon && area.containsMouse
          StyledToolTip {
            target: pill
            text: pill.modelData.text
          }
        }
      }
    }
  }
}
