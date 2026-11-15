pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// A choice as a box: an icon, a title with an optional tag ("Recommended"),
// and a description. The selected one is outlined in the accent color;
// an unavailable one is greyed out, saying why.
Surface {
  id: root
  tone: root.selected ? "accentContainer" : "surface"

  property string icon
  property string title
  property string description
  property bool selected: false
  property bool recommended: false
  // The tag beside the title ("" for none)
  property string tag: root.recommended ? I18n.tr("Recommended") : ""
  // StatusChip's tone for the tag
  property string tagTone: "accent"
  // False greys it out and ignores clicks
  property bool available: true
  // Why it isn't available, shown under the description
  property string unavailableReason

  signal clicked

  Layout.fillWidth: true
  implicitHeight: row.implicitHeight + Widget.padding * 2
  // Outlined in both states: subtle, or the accent when selected
  outlined: true
  border.color: root.selected ? Style.accent : Style.borderSubtle

  ColorGlide on color {}

  StateLayer {
    hovered: area.containsMouse && root.available && !root.selected
  }

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.padding

    StyledIcon {
      Layout.alignment: Qt.AlignTop
      opacity: root.available ? 1 : Style.opacityDisabled
      visible: root.icon !== ""
      text: root.icon
      size: "lg"
      tone: root.selected ? "accent" : ""
    }

    ColumnLayout {
      Layout.fillWidth: true
      // At the top when the card is stretched taller than its text
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing / 2

      RowLayout {
        spacing: Widget.spacing

        StyledLabel {
          text: root.title
          role: "label"
          tone: root.available ? "" : "disabled"
        }

        StatusChip {
          visible: root.tag !== ""
          opacity: root.available ? 1 : Style.opacityDisabled
          text: root.tag
          // On the selected card's accent container an accent chip would vanish
          tone: root.selected && root.tagTone === "accent" ? "neutral" : root.tagTone
        }
      }

      StyledText {
        Layout.fillWidth: true
        visible: root.description !== ""
        text: root.description
        role: "caption"
        tone: root.available ? "muted" : "disabled"
      }

      RowLayout {
        Layout.fillWidth: true
        visible: !root.available && root.unavailableReason !== ""
        spacing: Widget.spacing / 2

        StyledIcon {
          Layout.alignment: Qt.AlignTop
          text: "block"
          tone: "warning"
        }

        StyledText {
          Layout.fillWidth: true
          text: root.unavailableReason
          role: "caption"
          tone: "warning"
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
