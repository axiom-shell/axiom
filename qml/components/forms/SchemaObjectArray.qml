pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// i18n: keys from callers and the schema (titles, descriptions, type labels)
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

    StyledRectButton {
      iconText: "add"
      iconSize: Appearance.fontSizeBy(4)
      hoverColor: Theme.accent

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

      delegate: StyledContainer {
        id: entry
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

            StyledText {
              text: "#" + (entry.index + 1)
              textColor: Theme.accent
              textSize: Appearance.fontSizeBy(-1)
              font.bold: true
            }

            Item {
              Layout.fillWidth: true
            }

            SquareIconButton {
              visible: entry.index > 0
              size: Widget.iconButton
              iconText: "expand_less"
              iconSize: Appearance.fontSizeBy(2)

              onClicked: {
                root.itemMoved(entry.index, entry.index - 1);
              }
            }

            SquareIconButton {
              visible: entry.index < root.items.length - 1
              size: Widget.iconButton
              iconText: "expand_more"
              iconSize: Appearance.fontSizeBy(2)

              onClicked: {
                root.itemMoved(entry.index, entry.index + 1);
              }
            }

            SquareIconButton {
              size: Widget.iconButton
              iconText: "close"
              iconSize: Appearance.fontSizeBy(4)
              hoverColor: Theme.error

              onClicked: {
                root.itemRemoved(entry.index);
              }
            }
          }

          StyledSeparator {
            Layout.fillWidth: true
            separatorHeight: 1
            opacity: 0.3
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

  StyledContainer {
    visible: root.items.length === 0
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height * 3 - Widget.padding
    backgroundColor: Theme.background

    StyledText {
      anchors.centerIn: parent
      text: I18n.tr("No items - click + to add")
      opacity: 0.5
    }
  }
}
