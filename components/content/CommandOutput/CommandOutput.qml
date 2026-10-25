pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Any shell command's output, run every `interval` seconds while shown
// (CommandManager: one run for every card and bar button asking for the
// same command), so a script can be a module with no QML. Output that's
// one short line shows as a big figure, a sentence or two larger and
// centred, and longer output as text, as many lines as fit. A `clickCommand` runs on a click on the card (then the
// command again). Compact, the first line; short, it on one row.
// properties: { title, icon, command, interval, monospace, clickCommand }
Card {
  id: root

  readonly property string command: (root.properties.command ?? "").trim()
  readonly property string clickCommand: (root.properties.clickCommand ?? "").trim()
  readonly property string title: root.properties.title ?? ""
  readonly property string icon: root.properties.icon || "terminal"
  readonly property string output: root.command !== "" ? (CommandManager.outputs[root.command] ?? "") : ""
  readonly property bool waiting: root.command !== "" && CommandManager.outputs[root.command] === undefined
  readonly property string firstLine: root.output.split("\n")[0] ?? ""
  // One short line reads as a figure (a count, a temperature, a status)
  readonly property bool figure: root.output !== "" && !root.output.includes("\n") && root.output.length <= 14
  // A line or three of words: larger, centred
  readonly property bool statement: !root.figure && root.output !== "" && root.output.length <= 80 && root.output.split("\n").length <= 3
  readonly property string textFamily: root.properties.monospace ? "monospace" : Appearance.fontFamily

  // One row: the icon, the title and the first line
  readonly property bool strip: root.innerHeight < Appearance.fontSize * 4.5
  readonly property bool showHeader: !root.strip && (root.title !== "" || root.innerHeight >= Appearance.fontSize * 8)

  fullMinWidth: Appearance.fontSize * 8
  fullMinHeight: Appearance.fontSize * 2.2

  function register() {
    CommandManager.acquire(root, {
      "command": root.command,
      "interval": Math.max(1000, root.properties.interval)
    });
  }
  onPropertiesChanged: register()
  Component.onCompleted: register()
  Component.onDestruction: CommandManager.release(root)

  function clicked() {
    if (root.clickCommand === "")
      return;
    CommandManager.runDetached(root.clickCommand);
    refreshLater.restart();
  }

  // Once the click's command has had a moment to change things
  Timer {
    id: refreshLater
    interval: 500
    onTriggered: CommandManager.refresh(root.command)
  }

  compactContent: Item {
    CompactFigure {
      anchors.fill: parent
      icon: root.icon
      value: root.figure ? root.output : ""
      label: root.figure ? root.title : (root.firstLine || root.title || I18n.tr("No output"))
    }
    TapHandler {
      enabled: root.clickCommand !== ""
      onTapped: root.clicked()
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.clickCommand !== ""
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  EmptyState {
    visible: root.command === "" && !root.strip
    anchors.centerIn: parent
    maxWidth: root.innerWidth
    availableHeight: root.innerHeight
    icon: "terminal"
    text: I18n.tr("Set a command in this module's settings")
  }

  // A short card: everything on one row
  RowLayout {
    visible: root.strip
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    StyledIcon {
      text: root.icon
      textColor: Theme.accent
      textSize: Appearance.fontSizeBy(2)
    }
    StyledText {
      visible: root.title !== ""
      text: root.title
      font.bold: true
      textColor: Theme.foregroundAlt
    }
    StyledText {
      Layout.fillWidth: true
      text: root.command === "" ? I18n.tr("No command set") : root.waiting ? "…" : root.firstLine
      textFamily: root.textFamily
      horizontalAlignment: root.title !== "" ? Text.AlignRight : Text.AlignLeft
      font.bold: root.figure
      elide: Text.ElideRight
    }
  }

  ColumnLayout {
    visible: !root.strip && root.command !== ""
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    ModuleHeader {
      visible: root.showHeader
      icon: root.icon
      title: root.title || root.command
      FlatIconButton {
        size: Widget.iconButton
        iconText: "refresh"
        tooltipText: I18n.tr("Run it again")
        onClicked: CommandManager.refresh(root.command)
      }
    }

    // A figure, centred in the room
    Item {
      visible: root.figure || root.waiting
      Layout.fillWidth: true
      Layout.fillHeight: true

      StyledText {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width)
        text: root.waiting ? "…" : root.output
        textFamily: root.textFamily
        textSize: Math.max(Appearance.fontSize, Math.min(Appearance.fontSize * 3, parent.height * 0.5, parent.width / Math.max(4, root.output.length) * 1.6))
        font.bold: true
        elide: Text.ElideRight
      }
    }

    // Text: as many lines as fit
    StyledText {
      id: body
      visible: !root.figure && !root.waiting
      Layout.fillWidth: true
      Layout.fillHeight: true
      text: root.output === "" ? I18n.tr("No output") : root.output
      textFamily: root.textFamily
      textSize: root.statement ? Math.max(Appearance.fontSize, Math.min(Appearance.fontSize * 1.5, body.height / 5)) : Appearance.fontSizeBy(-1)
      textColor: root.output === "" ? Theme.foregroundAlt : Theme.foreground
      wrapMode: root.properties.monospace && !root.statement ? Text.NoWrap : Text.Wrap
      elide: Text.ElideRight
      maximumLineCount: Math.max(1, Math.floor(body.height / Math.max(1, metrics.height)))
      horizontalAlignment: root.statement || root.output === "" ? Text.AlignHCenter : Text.AlignLeft
      verticalAlignment: root.statement || root.output === "" ? Text.AlignVCenter : Text.AlignTop
      clip: true

      FontMetrics {
        id: metrics
        font: body.font
      }
    }
  }
}
