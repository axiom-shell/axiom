pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// An editable list of schema objects: a header with an add button, a delegate per item, moving and removal
ColumnLayout {
  id: root
  required property string label
  required property var items
  property string description: ""
  property var itemDelegate: null
  // After the label (the settings row's unsaved dot and reset)
  property Component headerExtra: null

  signal itemAdded
  signal itemRemoved(int index)
  signal itemMoved(int fromIndex, int toIndex)

  Layout.fillWidth: true
  spacing: Widget.spacing

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    FieldHeader {
      label: root.label
      title: true
      trailing: root.headerExtra
    }

    StyledIconButton {
      kind: "tonal"
      iconText: "add"
      iconSize: Style.iconMd

      onClicked: {
        root.itemAdded();
      }
    }
  }

  ClampedText {
    text: root.description === "" ? "" : I18n.tr(root.description)
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    // Keyed by count, not by the array: editing an item updates its
    // delegate in place instead of rebuilding every row (which would take
    // focus away from a text field on each keystroke)
    Repeater {
      model: root.items.length

      delegate: Surface {
        id: entry
        tone: "sunken"
        outlined: true
        required property int index
        readonly property var modelData: root.items[index]

        Layout.fillWidth: true
        implicitHeight: itemContent.implicitHeight + (Widget.padding * 2)

        ColumnLayout {
          id: itemContent
          anchors.fill: parent
          anchors.margins: Widget.padding
          spacing: Widget.spacing

          RowLayout {
            Layout.fillWidth: true
            spacing: Widget.spacing

            StyledLabel {
              text: "#" + (entry.index + 1)
              role: "label"
              tone: "accent"
            }

            Item {
              Layout.fillWidth: true
            }

            SquareIconButton {
              visible: entry.index > 0
              size: Widget.iconButton
              kind: "text"
              iconText: "expand_less"
              iconSize: Style.iconSm

              onClicked: {
                root.itemMoved(entry.index, entry.index - 1);
              }
            }

            SquareIconButton {
              visible: entry.index < root.items.length - 1
              size: Widget.iconButton
              kind: "text"
              iconText: "expand_more"
              iconSize: Style.iconSm

              onClicked: {
                root.itemMoved(entry.index, entry.index + 1);
              }
            }

            SquareIconButton {
              size: Widget.iconButton
              kind: "danger"
              iconText: "close"
              iconSize: Style.iconMd

              onClicked: {
                root.itemRemoved(entry.index);
              }
            }
          }

          StyledSeparator {
            Layout.fillWidth: true
            backTone: "sunken"
          }

          Loader {
            Layout.fillWidth: true
            sourceComponent: root.itemDelegate
            onLoaded: {
              item.itemData = Qt.binding(() => entry.modelData);
              item.itemIndex = Qt.binding(() => entry.index);
            }
          }
        }
      }
    }
  }

  Surface {
    visible: root.items.length === 0
    tone: "sunken"
    outlined: true
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height * 3 - Widget.padding

    StyledLabel {
      anchors.centerIn: parent
      text: I18n.tr("No items - click + to add")
      tone: "faint"
    }
  }
}
