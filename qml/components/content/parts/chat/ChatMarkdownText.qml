pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// Selectable chat text: Markdown prose (Chat.renderMarkdown), or plain text
// for what the user typed. Links open in the browser.
TextEdit {
  id: root
  renderType: TextRender.typeFor(TextRender.zoomAt(parent), false, 0)

  property bool markdown: ChatConfig.renderMarkdown
  property color textColor: Style.text

  readOnly: true
  selectByMouse: true
  persistentSelection: false
  wrapMode: TextEdit.Wrap
  textFormat: root.markdown ? TextEdit.MarkdownText : TextEdit.PlainText
  color: root.textColor
  selectionColor: Style.accent
  selectedTextColor: Style.onAccent
  font.family: Appearance.fontFamily
  font.pixelSize: Style.typeBody

  onLinkActivated: link => Qt.openUrlExternally(link)

  HoverHandler {
    cursorShape: root.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
  }
}
