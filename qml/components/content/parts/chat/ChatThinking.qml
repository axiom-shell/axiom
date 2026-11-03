pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A reply's thinking, folded under a "Thought for 12s" row. Open while the
// model is still thinking; after that it stays how the user left it.
ColumnLayout {
  id: root

  property string text: ""
  // Still thinking (the reply's text hasn't started)
  property bool live: false
  property real durationMs: 0

  property var _userExpanded: null
  readonly property bool expanded: root._userExpanded ?? root.live

  spacing: Widget.spacing / 2

  RowLayout {
    spacing: Widget.spacing / 2

    StyledIcon {
      id: thinkIcon
      text: "psychology"
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSize

      SequentialAnimation on opacity {
        running: root.live && Appearance.animations
        loops: Animation.Infinite
        onRunningChanged: {
          if (!running)
            thinkIcon.opacity = 1;
        }
        NumberAnimation {
          to: 0.35
          duration: Appearance.animSlow * 2
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          to: 1
          duration: Appearance.animSlow * 2
          easing.type: Easing.InOutSine
        }
      }
    }

    StyledText {
      text: {
        if (root.live)
          return I18n.tr("Thinking…");
        const seconds = Math.round(root.durationMs / 1000);
        return seconds > 0 ? I18n.tr("Thought for {0}s", seconds) : I18n.tr("Thought");
      }
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-1)
    }

    StyledIcon {
      visible: root.text !== ""
      text: root.expanded ? "expand_less" : "expand_more"
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSize
    }

    TapHandler {
      enabled: root.text !== ""
      onTapped: root._userExpanded = !root.expanded
    }

    HoverHandler {
      enabled: root.text !== ""
      cursorShape: Qt.PointingHandCursor
    }
  }

  RowLayout {
    visible: root.expanded && root.text !== ""
    Layout.fillWidth: true
    spacing: Widget.padding

    Rectangle {
      Layout.fillHeight: true
      implicitWidth: 2
      radius: 1
      color: Theme.border
    }

    ChatMarkdownText {
      Layout.fillWidth: true
      text: root.text
      textColor: Theme.foregroundAlt
      font.pixelSize: Appearance.fontSizeBy(-1)
    }
  }
}
