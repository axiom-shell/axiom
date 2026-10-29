pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Emoji to copy (EmojiManager, as the launcher's ";" does): a search field,
// Unicode's groups as tabs and a grid, most used first until you search or
// pick a group. Click one to copy it; the line under the grid names the one
// under the pointer. A short card is a row of the most used.
// properties: { showGroups }
Panel {
  id: root

  readonly property string query: field.text.trim()
  // A group's name, "" for most used then everything
  property string group: ""
  // Rebuilt on what's typed or picked, never on use, so the grid holds
  // still while you copy
  property var results: []
  // emoji.json is missing or empty (read in refresh(): entries() loads
  // it, which a binding mustn't do)
  property bool noList: false
  property var hoveredEntry: null
  // The last one copied, for a moment, as feedback
  property string copied: ""

  readonly property real cell: Appearance.fontSize * 2.4
  // One row: the most used, as many as fit
  readonly property bool strip: root.embedded && root.innerHeight < Appearance.fontSize * 7
  readonly property bool showSearch: !root.strip
  readonly property bool showGroups: (root.properties.showGroups ?? true) && !root.strip && (!root.embedded || (root.innerHeight >= Appearance.fontSize * 11 && root.innerWidth >= root.groupIcons.length * 26 + 30))
  readonly property bool showFooter: !root.strip && (!root.embedded || root.innerHeight >= Appearance.fontSize * 12)
  readonly property var recent: EmojiManager.recent(Math.max(1, Math.floor(root.innerWidth / root.cell)))

  // Unicode's group names (emoji.json) and their tab icons.
  // I18n.tr("Smileys & Emotion") I18n.tr("People & Body") I18n.tr("Animals & Nature")
  // I18n.tr("Food & Drink") I18n.tr("Travel & Places") I18n.tr("Activities")
  // I18n.tr("Objects") I18n.tr("Symbols") I18n.tr("Flags")
  readonly property var groupIcons: [
    {
      "group": "",
      "icon": "history"
    },
    {
      "group": "Smileys & Emotion",
      "icon": "mood"
    },
    {
      "group": "People & Body",
      "icon": "emoji_people"
    },
    {
      "group": "Animals & Nature",
      "icon": "pets"
    },
    {
      "group": "Food & Drink",
      "icon": "restaurant"
    },
    {
      "group": "Travel & Places",
      "icon": "flight"
    },
    {
      "group": "Activities",
      "icon": "sports_soccer"
    },
    {
      "group": "Objects",
      "icon": "lightbulb"
    },
    {
      "group": "Symbols",
      "icon": "emoji_symbols"
    },
    {
      "group": "Flags",
      "icon": "flag"
    }
  ]

  implicitWidth: Widget.px(380)
  fullMinWidth: Appearance.fontSize * 10
  fullMinHeight: Appearance.fontSize * 3.5
  wantsKeyboardFocus: true
  spacing: Widget.spacing

  function refresh() {
    root.noList = EmojiManager.entries().length === 0;
    root.results = EmojiManager.search(root.query, Infinity, root.query === "" ? root.group : "");
    grid.positionViewAtBeginning();
  }

  function copy(emoji) {
    EmojiManager.copy(emoji);
    root.copied = emoji;
    copiedReset.restart();
  }

  // The name with a capital, as the launcher shows it
  function nameOf(entry) {
    return entry ? entry.n.charAt(0).toUpperCase() + entry.n.slice(1) : "";
  }

  onQueryChanged: refresh()
  onGroupChanged: refresh()
  Component.onCompleted: refresh()

  Timer {
    id: copiedReset
    interval: 1500
    onTriggered: root.copied = ""
  }

  compactContent: CompactFigure {
    icon: root.recent.length > 0 ? "" : "add_reaction"
    value: root.recent[0] ?? ""
    label: I18n.tr("Emoji")
  }

  // One emoji in the grid or the strip
  component EmojiCell: Rectangle {
    id: cellItem
    required property string emoji
    property var entry: null

    implicitWidth: root.cell
    implicitHeight: root.cell
    radius: Widget.radius
    color: root.copied === cellItem.emoji ? Qt.alpha(Theme.accent, 0.3) : cellHover.hovered ? Theme.backgroundHighlight : "transparent"
    scale: cellTap.pressed ? 0.9 : 1

    ColorGlide on color {}
    Glide on scale {}

    Text {
      anchors.centerIn: parent
      text: cellItem.emoji
      font.pixelSize: root.cell * 0.6
      color: Theme.foreground
    }

    HoverHandler {
      id: cellHover
      cursorShape: Qt.PointingHandCursor
      onHoveredChanged: {
        if (hovered)
          root.hoveredEntry = cellItem.entry;
        else if (root.hoveredEntry === cellItem.entry)
          root.hoveredEntry = null;
      }
    }
    TapHandler {
      id: cellTap
      onTapped: root.copy(cellItem.emoji)
    }
  }

  StyledTextEntry {
    id: field
    visible: root.showSearch
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height
    placeholderText: I18n.tr("Search emoji")
    input.wrapMode: Text.NoWrap
    onAccepted: {
      if (root.results.length > 0)
        root.copy(root.results[0].e);
    }
    Keys.onEscapePressed: event => {
      if (field.text === "") {
        event.accepted = false;
        return;
      }
      field.text = "";
    }
  }

  // The groups; searching looks through all of them
  RowLayout {
    visible: root.showGroups
    Layout.fillWidth: true
    spacing: 0
    opacity: root.query === "" ? 1 : 0.4

    Glide on opacity {}

    Repeater {
      model: root.groupIcons.length

      FlatIconButton {
        id: tab
        required property int index
        readonly property var info: root.groupIcons[index]
        readonly property bool active: root.group === tab.info.group
        Layout.fillWidth: true
        Layout.preferredWidth: -1
        size: Widget.iconButton
        iconText: tab.info.icon
        iconColor: tab.active ? Theme.accent : Theme.foregroundAlt
        backgroundColor: tab.active ? Qt.alpha(Theme.accent, 0.15) : "transparent"
        tooltipText: tab.info.group === "" ? I18n.tr("Most used") : I18n.tr(tab.info.group)
        onClicked: {
          field.text = "";
          root.group = tab.info.group;
        }
      }
    }
  }

  // Everything that matches, a cell's width apart and centred
  GridView {
    id: grid
    visible: !root.strip
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? -1 : Appearance.fontSize * 16
    readonly property int columns: Math.max(1, Math.floor(width / root.cell))
    cellWidth: width / grid.columns
    cellHeight: root.cell
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.results.length

    delegate: Item {
      id: slot
      required property int index
      width: grid.cellWidth
      height: grid.cellHeight

      EmojiCell {
        anchors.centerIn: parent
        emoji: root.results[slot.index]?.e ?? ""
        entry: root.results[slot.index] ?? null
      }
    }

    EmptyState {
      visible: root.results.length === 0
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: parent.height
      icon: "search_off"
      text: root.noList ? I18n.tr("No emoji list: run scripts/generate_emoji.py") : I18n.tr("No matches")
    }
  }

  // The one under the pointer, or what a click does
  StyledText {
    visible: root.showFooter
    Layout.fillWidth: true
    text: root.copied !== "" ? I18n.tr("Copied {0}", root.copied) : root.hoveredEntry ? root.nameOf(root.hoveredEntry) : I18n.tr("Click to copy")
    textSize: Appearance.fontSizeBy(-2)
    textColor: root.copied !== "" ? Theme.accent : Theme.foregroundAlt
    elide: Text.ElideRight
  }

  // A short card: the most used in a row
  RowLayout {
    visible: root.strip
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 0

    Repeater {
      model: root.strip ? root.recent.length : 0

      EmojiCell {
        required property int index
        Layout.alignment: Qt.AlignVCenter
        emoji: root.recent[index] ?? ""
      }
    }

    StyledText {
      wrapMode: Text.WordWrap
      visible: root.recent.length === 0
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      text: I18n.tr("Emoji you copy show up here")
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
    }

    Item {
      Layout.fillWidth: true
    }
  }
}
