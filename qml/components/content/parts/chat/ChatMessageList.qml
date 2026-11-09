pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.apps
import qs.components.reusable
import qs.components.content.parts

// The conversation, scrolled to the bottom while it streams, unless the
// user scrolled up (then a "Jump to latest" pill brings it back). A
// ListView, so only the messages in view are built (and a screen's worth
// either side, so scrolling back a little doesn't lay their Markdown out
// again): a long conversation would otherwise build every message at once.
Item {
  id: root

  // Stick to the bottom as the content grows
  property bool _follow: true
  property bool _autoScrolling: false
  // A lane on the right for the scroll bar, only while there's anything to scroll
  readonly property int _lane: flick.contentHeight > flick.height ? 10 : 0
  // The furthest it scrolls (a ListView's content starts at originY, which
  // moves as rows above are built)
  readonly property real _end: flick.originY + Math.max(0, flick.contentHeight - flick.height)

  function scrollToEnd() {
    root._follow = true;
    root._autoScrolling = true;
    flick.contentY = root._end;
    root._autoScrolling = false;
  }

  Connections {
    target: ChatManager
    function onConversationChanged() {
      if (ChatManager.messages.length === 0 || ChatManager.messages[ChatManager.messages.length - 1].role === "user")
        root._follow = true;
    }
  }

  ListView {
    id: flick
    anchors.fill: parent
    clip: true
    spacing: Widget.spacing * 2
    cacheBuffer: Math.max(0, flick.height)
    // Mouse drags select text instead of flicking; the wheel scrolls
    interactive: false
    boundsBehavior: Flickable.StopAtBounds

    onContentHeightChanged: {
      if (root._follow)
        Qt.callLater(root.scrollToEnd);
    }
    onHeightChanged: {
      if (root._follow)
        Qt.callLater(root.scrollToEnd);
    }
    onContentYChanged: {
      if (!root._autoScrolling)
        root._follow = contentY >= root._end - 8;
    }

    ScrollBar.vertical: ScrollBar {
      policy: root._lane > 0 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
      rightPadding: Widget.px(3)
      leftPadding: Widget.px(3)
      contentItem: Rectangle {
        implicitWidth: Widget.px(4)
        radius: 2
        color: Theme.accent
        opacity: parent.pressed ? 0.8 : 0.4
      }
    }

    model: CountModel {
      count: ChatManager.messages.length
    }
    delegate: ChatMessage {
      width: flick.width - root._lane
      message: ChatManager.messages[index]
      isLast: index === ChatManager.messages.length - 1
    }
  }

  WheelHandler {
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
      const step = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * Appearance.fontSize * 4;
      flick.contentY = Math.max(flick.originY, Math.min(root._end, flick.contentY - step));
    }
  }

  // Nothing said yet
  ColumnLayout {
    visible: ChatManager.messages.length === 0
    anchors.centerIn: parent
    width: Math.min(parent.width - Widget.padding * 2, Widget.px(280))
    spacing: Widget.spacing

    EmptyState {
      Layout.alignment: Qt.AlignHCenter
      icon: ChatManager.preset.icon || "chat"
      text: I18n.tr("{0} on {1}", ChatManager.preset.name, ChatManager.model || "—")
      maxWidth: parent.width
    }

    StyledTextButton {
      visible: {
        const status = SecretsManager.status(ChatManager.provider);
        return status === "none";
      }
      Layout.alignment: Qt.AlignHCenter
      text: I18n.tr("Add a key for {0}", ChatManager.provider?.name ?? "")
      iconText: "key"
      onClicked: ChatManager.openSettings()
    }
  }

  // Scrolled up while there's more below
  Rectangle {
    visible: !root._follow && flick.contentHeight > flick.height
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: Widget.spacing
    implicitWidth: jumpRow.implicitWidth + Widget.padding * 2
    implicitHeight: jumpRow.implicitHeight + Widget.spacing
    radius: height / 2
    color: Theme.backgroundHighlight
    border.color: Theme.border
    border.width: 1

    RowLayout {
      id: jumpRow
      anchors.centerIn: parent
      spacing: Widget.spacing / 2
      StyledIcon {
        text: "arrow_downward"
        textSize: Appearance.fontSizeBy(-1)
      }
      StyledLabel {
        text: I18n.tr("Jump to latest")
        textSize: Appearance.fontSizeBy(-2)
      }
    }

    TapHandler {
      onTapped: root.scrollToEnd()
    }
    HoverHandler {
      cursorShape: Qt.PointingHandCursor
    }
  }
}
