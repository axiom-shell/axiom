pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// A choice as a box: an icon, a title with an optional tag ("Recommended"),
// and a description. The selected one is outlined in the accent color;
// an unavailable one is greyed out, saying why.
Rectangle {
  id: root

  property string icon
  property string title
  property string description
  property bool selected: false
  property bool recommended: false
  // The tag beside the title ("" for none)
  property string tag: root.recommended ? I18n.tr("Recommended") : ""
  property color tagColor: Theme.accent
  // False greys it out and ignores clicks
  property bool available: true
  // Why it isn't available, shown under the description
  property string unavailableReason

  signal clicked

  Layout.fillWidth: true
  implicitHeight: row.implicitHeight + Widget.padding * 2
  radius: Widget.radius
  color: root.selected ? Qt.alpha(Theme.accent, 0.12) : area.containsMouse && root.available ? Theme.backgroundHighlight : Theme.backgroundAlt
  border.color: root.selected ? Theme.accent : Theme.border
  border.width: Appearance.borderWidth

  ColorGlide on color {}

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.padding

    StyledIcon {
      Layout.alignment: Qt.AlignTop
      opacity: root.available ? 1 : 0.5
      visible: root.icon !== ""
      text: root.icon
      textSize: Appearance.fontSize * 1.6
      textColor: root.selected ? Theme.accent : Theme.foreground
    }

    ColumnLayout {
      Layout.fillWidth: true
      // At the top when the card is stretched taller than its text
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing / 2

      RowLayout {
        opacity: root.available ? 1 : 0.5
        spacing: Widget.spacing

        StyledText {
          text: root.title
          font.bold: true
        }

        Rectangle {
          visible: root.tag !== ""
          implicitWidth: tag.implicitWidth + Widget.spacing * 2
          implicitHeight: tag.implicitHeight + Widget.px(4)
          radius: height / 2
          color: root.tagColor

          StyledText {
            id: tag
            anchors.centerIn: parent
            text: root.tag
            textSize: Appearance.fontSize * 0.8
            textColor: Theme.background
          }
        }
      }

      StyledText {
        Layout.fillWidth: true
        visible: root.description !== ""
        opacity: root.available ? 1 : 0.5
        text: root.description
        wrapMode: Text.WordWrap
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSize * 0.9
      }

      RowLayout {
        Layout.fillWidth: true
        visible: !root.available && root.unavailableReason !== ""
        spacing: Widget.spacing / 2

        StyledIcon {
          Layout.alignment: Qt.AlignTop
          text: "block"
          textColor: Theme.warning
          textSize: Appearance.fontSize
        }

        StyledText {
          Layout.fillWidth: true
          text: root.unavailableReason
          wrapMode: Text.WordWrap
          textColor: Theme.warning
          textSize: Appearance.fontSize * 0.9
        }
      }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.available
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
