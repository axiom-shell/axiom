pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

/**
 * Settings page: the sunken box that holds the settings of the one selected
 * item of an editor (OSDSystemsEditor, OSDBarsEditor): its icon and name, a
 * separator, any child items, then a form built anew for each `formKey` from
 * `sourceComponent` (a form whose rows commit on change must not be reused
 * for another selection). The form sets its width from `formWidth`.
 */
Surface {
  id: root
  tone: "sunken"

  property string icon: ""
  property string title: ""
  // A smaller label after the title; hidden while empty
  property string caption: ""
  property string formKey: ""
  property Component sourceComponent
  // Items shown between the separator and the form
  default property alias extras: extraSlot.data
  readonly property real formWidth: formSlot.width

  implicitHeight: column.implicitHeight + Widget.padding * 2

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: Widget.padding
    spacing: Widget.spacing

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledIcon {
        text: root.icon
        tone: "accent"
      }

      StyledLabel {
        Layout.fillWidth: true
        text: root.title
        role: "label"
        overflow: "line"
      }

      StyledLabel {
        visible: root.caption !== ""
        text: root.caption
        role: "caption"
      }
    }

    StyledSeparator {
      Layout.fillWidth: true
    }

    ColumnLayout {
      id: extraSlot
      visible: visibleChildren.length > 0
      Layout.fillWidth: true
      spacing: Widget.spacing
    }

    KeyedLoader {
      id: formSlot
      Layout.fillWidth: true
      Layout.preferredHeight: formSlot.childrenRect.height
      key: root.formKey
      sourceComponent: root.sourceComponent
    }
  }
}
