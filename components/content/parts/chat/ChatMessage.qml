pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// One message: the user's in an accent-tinted bubble on the right, a reply
// as full-width text (thinking, Markdown prose and code blocks). Actions
// show on hover.
Item {
  id: root

  required property var message
  required property int index
  property bool isLast: false

  readonly property bool isUser: message?.role === "user"
  readonly property bool streaming: message?.state === "streaming"
  readonly property string text: streaming ? ChatManager.streamingText : (message?.text ?? "")
  readonly property string thinking: streaming ? ChatManager.streamingThinking : (message?.thinking ?? "")
  // Modelled by count (see AGENTS.md): streaming text edits the last
  // segment in place instead of rebuilding every block on each flush
  readonly property var segments: ChatConfig.renderMarkdown ? ChatMarkdown.segments(root.text) : [
    {
      "kind": "md",
      "text": root.text,
      "lang": "",
      "open": false
    }
  ]
  readonly property bool hovered: hover.hovered

  implicitHeight: column.implicitHeight

  HoverHandler {
    id: hover
  }

  ColumnLayout {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Widget.spacing / 2

    // --- The user's message ---

    Rectangle {
      id: bubble
      visible: root.isUser
      Layout.alignment: Qt.AlignRight
      Layout.maximumWidth: root.width * 0.85
      implicitWidth: Math.min(root.width * 0.85, userColumn.implicitWidth + Widget.padding * 2)
      implicitHeight: userColumn.implicitHeight + Widget.padding * 1.5
      radius: Widget.radius + 2
      color: Qt.alpha(Theme.accent, 0.16)
      border.color: Qt.alpha(Theme.accent, 0.35)
      border.width: 1

      ColumnLayout {
        id: userColumn
        anchors.fill: parent
        anchors.margins: Widget.padding
        anchors.topMargin: Widget.padding * 0.75
        anchors.bottomMargin: Widget.padding * 0.75
        spacing: Widget.spacing

        Flow {
          visible: (root.message?.attachments ?? []).length > 0
          Layout.fillWidth: true
          spacing: Widget.spacing / 2

          Repeater {
            model: root.isUser ? (root.message?.attachments ?? []).length : 0
            delegate: AttachmentChip {
              required property int index
              attachment: root.message.attachments[index]
              size: Widget.px(96)
            }
          }
        }

        ChatMarkdownText {
          visible: text !== ""
          Layout.fillWidth: true
          Layout.maximumWidth: root.width * 0.85 - Widget.padding * 2
          markdown: false
          text: root.isUser ? root.text : ""
        }
      }
    }

    // Unanswered (the reply was cut off by a reload, or deleted)
    StyledTextButton {
      visible: root.isUser && root.isLast && !ChatManager.busy
      Layout.alignment: Qt.AlignRight
      text: I18n.tr("Get a reply")
      iconText: "refresh"
      onClicked: ChatManager.regenerate()
    }

    // --- A reply ---

    ColumnLayout {
      visible: !root.isUser
      Layout.fillWidth: true
      spacing: Widget.spacing

      ChatThinking {
        visible: root.thinking !== ""
        Layout.fillWidth: true
        text: root.thinking
        live: root.streaming && root.text === ""
        durationMs: root.streaming ? 0 : (root.message?.thinkingMs ?? 0)
      }

      Repeater {
        model: root.isUser ? 0 : root.segments.length
        delegate: Loader {
          id: segment
          required property int index
          readonly property var segmentData: root.segments[index] ?? ({})
          Layout.fillWidth: true
          sourceComponent: segmentData.kind === "code" ? codeBlock : prose

          Component {
            id: prose
            ChatMarkdownText {
              width: segment.width
              text: segment.segmentData.text ?? ""
            }
          }

          Component {
            id: codeBlock
            ChatCodeBlock {
              width: segment.width
              code: segment.segmentData.text ?? ""
              lang: segment.segmentData.lang ?? ""
              open: segment.segmentData.open ?? false
            }
          }
        }
      }

      // Waiting for the first token
      Row {
        visible: root.streaming && root.text === "" && root.thinking === ""
        spacing: Widget.spacing
        Layout.topMargin: Widget.spacing
        Layout.bottomMargin: Widget.spacing

        Repeater {
          model: 3
          delegate: Rectangle {
            id: dot
            required property int index
            width: Widget.px(7)
            height: Widget.px(7)
            radius: width / 2
            color: Theme.accent
            opacity: 0.35

            SequentialAnimation on opacity {
              running: root.streaming && Appearance.animations
              loops: Animation.Infinite
              PauseAnimation {
                duration: dot.index * Appearance.animFast
              }
              NumberAnimation {
                to: 1
                duration: Appearance.animNormal
              }
              NumberAnimation {
                to: 0.35
                duration: Appearance.animNormal
              }
              PauseAnimation {
                duration: (2 - dot.index) * Appearance.animFast
              }
            }
          }
        }
      }

      // Why it ended early
      RowLayout {
        visible: !root.streaming && (root.message?.notice ?? "") !== "" || root.message?.state === "stopped"
        spacing: Widget.spacing / 2

        StyledIcon {
          text: root.message?.state === "stopped" ? "stop_circle" : root.message?.notice === "refusal" ? "block" : "content_cut"
          textColor: Theme.warning
          textSize: Appearance.fontSizeBy(-1)
        }
        StyledText {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          textColor: Theme.warning
          textSize: Appearance.fontSizeBy(-2)
          text: {
            if (root.message?.state === "stopped")
              return I18n.tr("Stopped");
            if (root.message?.notice === "refusal")
              return I18n.tr("The model declined to answer this.");
            return I18n.tr("Cut off at the reply length limit (Settings → Chat).");
          }
        }
      }

      // A failed reply
      StyledContainer {
        visible: root.message?.state === "error"
        Layout.fillWidth: true
        implicitHeight: errorColumn.implicitHeight + Widget.padding * 1.5
        backgroundColor: Qt.alpha(Theme.error, 0.12)
        borderColor: Qt.alpha(Theme.error, 0.5)
        borderWidth: 1

        ColumnLayout {
          id: errorColumn
          anchors.fill: parent
          anchors.margins: Widget.padding * 0.75
          spacing: Widget.spacing / 2

          RowLayout {
            spacing: Widget.spacing / 2
            StyledIcon {
              text: "error"
              textColor: Theme.error
            }
            StyledText {
              Layout.fillWidth: true
              text: {
                switch (root.message?.errorKind) {
                case "auth":
                  return I18n.tr("The API key was rejected");
                case "nokey":
                  return I18n.tr("No API key");
                case "network":
                  return I18n.tr("Couldn't reach the provider");
                }
                return I18n.tr("The request failed");
              }
              textColor: Theme.error
              font.bold: true
            }
          }

          StyledText {
            Layout.fillWidth: true
            text: root.message?.error ?? ""
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
            textSize: Appearance.fontSizeBy(-2)
            opacity: 0.8
          }

          RowLayout {
            spacing: Widget.spacing / 2
            StyledTextButton {
              visible: root.isLast
              text: I18n.tr("Retry")
              iconText: "refresh"
              onClicked: ChatManager.regenerate()
            }
            StyledTextButton {
              visible: root.message?.errorKind === "auth" || root.message?.errorKind === "nokey" || root.message?.errorKind === "config"
              text: root.message?.errorKind === "config" ? I18n.tr("Open settings") : I18n.tr("Set API key")
              iconText: root.message?.errorKind === "config" ? "settings" : "key"
              onClicked: ChatManager.openSettings()
            }
          }
        }
      }
    }

    // --- Actions ---

    RowLayout {
      Layout.alignment: root.isUser ? Qt.AlignRight : Qt.AlignLeft
      Layout.preferredHeight: Widget.iconButton
      spacing: 2
      opacity: root.hovered && !root.streaming ? 1 : 0
      enabled: opacity > 0

      Glide on opacity {}

      StyledText {
        visible: !root.isUser && (root.message?.model ?? "") !== ""
        Layout.alignment: Qt.AlignVCenter
        Layout.rightMargin: Widget.spacing
        text: root.message?.model ?? ""
        textColor: Theme.foregroundInactive
        textSize: Appearance.fontSizeBy(-3)
      }

      FlatIconButton {
        visible: root.text !== ""
        size: Widget.iconButton
        iconText: "content_copy"
        iconSize: Appearance.fontSizeBy(-2)
        tooltipText: I18n.tr("Copy")
        onClicked: ChatManager.copy(root.text)
      }

      FlatIconButton {
        visible: !root.isUser && root.isLast && root.message?.state !== "error"
        size: Widget.iconButton
        iconText: "refresh"
        iconSize: Appearance.fontSizeBy(-2)
        tooltipText: I18n.tr("Regenerate")
        onClicked: ChatManager.regenerate()
      }

      FlatIconButton {
        size: Widget.iconButton
        iconText: "delete"
        iconSize: Appearance.fontSizeBy(-2)
        tooltipText: I18n.tr("Delete")
        onClicked: ChatManager.removeMessage(root.index)
      }
    }
  }
}
