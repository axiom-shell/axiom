pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable
import qs.services.apps
import qs.components.content.base
import qs.components.content.parts
import qs.components.content.parts.chat

// The AI chat (ChatManager): an overlay module, and ready to be a bar
// popout (it's a Panel). In a wide slot the conversation list is docked on
// the left; otherwise it slides over the chat. Images can be dropped on it.
Panel {
  id: root

  // A wide card docks the conversation list beside the chat
  readonly property bool listDocked: root.embedded && root.shape === "horizontal" && root.innerWidth >= Appearance.fontSize * 40
  property bool listOpen: false
  property bool pickerOpen: false
  // The dropdowns open just under the header
  readonly property real popupTop: header.height + Widget.spacing

  implicitWidth: Widget.px(440) + root.margins * 2
  // The header, a message or two and the composer, else the figure
  fullMinWidth: Appearance.fontSize * 18
  fullMinHeight: Appearance.fontSize * 16
  wantsKeyboardFocus: true
  spacing: 0

  // Ready to type as soon as it's shown (its page becomes current, its
  // menu or popout opens)
  onVisibleChanged: {
    if (root.visible)
      Qt.callLater(composer.focusInput);
  }
  Component.onCompleted: {
    if (root.visible)
      Qt.callLater(composer.focusInput);
  }

  compactContent: Component {
    CompactFigure {
      icon: "smart_toy"
      label: ChatManager.conversation.title || I18n.tr("Chat")
    }
  }

  Item {
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredHeight: root.embedded ? -1 : Widget.px(560)

    RowLayout {
      anchors.fill: parent
      spacing: Widget.padding

      ConversationList {
        visible: root.listDocked
        Layout.fillHeight: true
        Layout.preferredWidth: Math.max(Widget.px(180), parent.width * 0.32)
        color: Theme.backgroundAlt
        border.width: 0
        floating: false
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Widget.spacing

        ChatHeader {
          id: header
          Layout.fillWidth: true
          listDocked: root.listDocked
          listOpen: root.listOpen
          pickerOpen: root.pickerOpen
          onToggleList: {
            root.pickerOpen = false;
            root.listOpen = !root.listOpen;
          }
          onTogglePicker: {
            root.listOpen = false;
            root.pickerOpen = !root.pickerOpen;
          }
        }

        StyledSeparator {
          Layout.fillWidth: true
          separatorHeight: 1
          opacity: 0.6
        }

        ChatMessageList {
          Layout.fillWidth: true
          Layout.fillHeight: true
        }

        ChatComposer {
          id: composer
          Layout.fillWidth: true
        }
      }
    }

    // Anything open over the chat closes on a click beside it
    MouseArea {
      anchors.fill: parent
      visible: root.listOpen || root.pickerOpen
      onClicked: {
        root.listOpen = false;
        root.pickerOpen = false;
      }
    }

    ConversationList {
      visible: !root.listDocked && root.listOpen
      anchors.top: parent.top
      anchors.topMargin: root.popupTop
      anchors.left: parent.left
      width: Math.min(parent.width - Widget.padding * 2, Widget.px(300))
      maxHeight: parent.height - root.popupTop - Widget.spacing
      onPicked: root.listOpen = false
    }

    ModelPicker {
      visible: root.pickerOpen
      anchors.top: parent.top
      anchors.topMargin: root.popupTop
      anchors.right: parent.right
      width: Math.min(parent.width - Widget.padding * 2, Widget.px(280))
      maxHeight: Math.min(Widget.px(420), parent.height - root.popupTop - Widget.spacing)
      onPicked: root.pickerOpen = false
    }

    DropArea {
      id: drop
      anchors.fill: parent
      keys: ["text/uri-list"]
      onDropped: event => {
        for (const url of event.urls)
          ChatManager.attachFile(url);
      }

      Rectangle {
        visible: drop.containsDrag
        anchors.fill: parent
        radius: Widget.radius
        color: Qt.alpha(Theme.accent, 0.12)
        border.color: Theme.accent
        border.width: 2
      }
    }
  }
}
