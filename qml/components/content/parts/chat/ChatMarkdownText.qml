pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// Selectable chat text: Markdown prose (Chat.renderMarkdown), or plain text
// for what the user typed. Links open in the browser.
TextEdit {
  id: root

  property bool markdown: ChatConfig.renderMarkdown
  property color textColor: Theme.foreground

  readOnly: true
  selectByMouse: true
  persistentSelection: false
  wrapMode: TextEdit.Wrap
  textFormat: root.markdown ? TextEdit.MarkdownText : TextEdit.PlainText
  color: root.textColor
  selectionColor: Theme.accent
  selectedTextColor: Theme.background
  font.family: Appearance.fontFamily
  font.pixelSize: Appearance.fontSize

  onLinkActivated: link => Qt.openUrlExternally(link)

  HoverHandler {
    cursorShape: root.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
  }
}
