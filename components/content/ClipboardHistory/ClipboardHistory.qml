pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// The clipboard history (ClipboardManager, as the launcher's ":" lists it):
// pinned clips first, then the newest, with a search field. Click a clip to
// copy it back; on hover, pin it (kept through restarts and Clear) or
// remove it. Images show a thumbnail. A short card is the
// newest clip with a copy button.
// properties: { grow }
Panel {
  id: root

  readonly property string query: field.text.trim().toLowerCase()
  readonly property bool off: !ClipboardManager.enabled
  // The compositor offers no clipboard control
  readonly property bool missing: ClipboardManager.unsupported
  // Pins, then the history without them
  readonly property var allClips: ClipboardManager.pins.concat(ClipboardManager.entries.filter(e => !ClipboardManager.isPinned(e)))
  readonly property var clips: root.query === "" ? root.allClips : root.allClips.filter(e => root.labelOf(e).toLowerCase().includes(root.query) || (e.text ?? "").toLowerCase().includes(root.query))
  readonly property var newest: ClipboardManager.pins.length > 0 || ClipboardManager.entries.length > 0 ? (ClipboardManager.entries[0] ?? ClipboardManager.pins[0]) : null
  // The clip copied last, for a moment, as feedback
  property string copiedId: ""
  // Clear asks twice
  property bool confirmClear: false

  // One row: the newest clip and a copy button
  readonly property bool strip: root.embedded && root.innerHeight < Appearance.fontSize * 7
  readonly property bool showHeader: !root.embedded || root.innerHeight >= Appearance.fontSize * 10
  readonly property bool showSearch: !root.strip && (!root.embedded || root.innerHeight >= Appearance.fontSize * 9)
  // Columns of clips in a wide card
  readonly property int columns: root.embedded ? Math.max(1, Math.floor((root.innerWidth + Widget.spacing) / (Appearance.fontSize * 22))) : 1
  // Two lines of a clip when a column is wide enough for them to read as a
  // preview
  readonly property int titleLines: (root.embedded ? root.innerWidth / root.columns : root.implicitWidth) >= Appearance.fontSize * 18 ? 2 : 1
  // Every row one height, so columns line up: the title's lines and the
  // detail under them
  readonly property real rowHeight: Math.ceil(Appearance.fontSize * (root.titleLines > 1 ? 3.6 : 2.4)) + Widget.spacing * 2

  implicitWidth: Widget.px(400)
  fullMinWidth: Appearance.fontSize * 11
  fullMinHeight: Appearance.fontSize * 3.5
  wantsKeyboardFocus: root.showSearch
  spacing: Widget.spacing
  wantedHeight: root.compact || root.strip ? 0 : root.height > 0 ? root.height + list.contentHeight - list.height : 0

  // The text with its lines run together (a preview), or what an image is
  function previewOf(entry) {
    if (entry.format || entry.html)
      return labelOf(entry);
    return entry.text.trim().slice(0, 400).replace(/\s+/g, " ");
  }

  // The first line, or what an image is
  function labelOf(entry) {
    if (entry.format)
      return I18n.tr("Image {0}", entry.dimensions);
    if (entry.html)
      return entry.image ? I18n.tr("Image from {0}", (entry.image.match(/^\w+:\/\/([^/]+)/) ?? ["", ""])[1]) : I18n.tr("Image");
    return entry.text.trim().split("\n")[0].trim();
  }

  function detailOf(entry) {
    if (entry.format)
      return entry.format.toUpperCase() + " · " + entry.size;
    if (entry.html)
      return I18n.tr("HTML");
    const details = [];
    const lines = entry.text.trim().split("\n").length;
    if (entry.pinned)
      details.push(I18n.tr("Pinned"));
    if (lines > 1)
      details.push(I18n.tr("{0} lines", lines));
    if (entry.time > 0)
      details.push(I18n.formatDate(new Date(entry.time), I18n.dateFormat("time24")));
    return details.join(" · ");
  }

  function copy(entry) {
    ClipboardManager.copy(entry);
    root.copiedId = entry.id;
    copiedReset.restart();
  }

  Timer {
    id: copiedReset
    interval: 1500
    onTriggered: root.copiedId = ""
  }
  Timer {
    running: root.confirmClear
    interval: 3000
    onTriggered: root.confirmClear = false
  }

  compactContent: CompactFigure {
    icon: "content_paste"
    iconColor: root.off ? Theme.foregroundAlt : Theme.accent
    value: root.off ? "" : String(root.allClips.length)
    label: root.off ? I18n.tr("off") : I18n.tr("clips")
  }

  ModuleHeader {
    visible: root.showHeader && !root.strip
    icon: "content_paste"
    title: I18n.tr("Clipboard")
    StyledText {
      visible: root.allClips.length > 0
      text: String(root.allClips.length)
      textSize: Appearance.fontSizeBy(-2)
      textColor: Theme.foregroundAlt
    }
    FlatIconButton {
      visible: ClipboardManager.entries.length > 0
      size: Widget.iconButton
      iconText: "delete_sweep"
      iconColor: root.confirmClear ? Theme.error : Theme.foregroundAlt
      backgroundColor: root.confirmClear ? Qt.alpha(Theme.error, 0.2) : "transparent"
      tooltipText: root.confirmClear ? I18n.tr("Click again to clear (pins stay)") : I18n.tr("Clear the history")
      onClicked: {
        if (root.confirmClear)
          ClipboardManager.clear();
        root.confirmClear = !root.confirmClear;
      }
    }
  }

  StyledTextEntry {
    id: field
    visible: root.showSearch && !root.off && !root.missing
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height
    placeholderText: I18n.tr("Search the clipboard")
    clearable: true
    escapeClears: true
    input.wrapMode: Text.NoWrap
    onAccepted: {
      if (root.clips.length > 0)
        root.copy(root.clips[0]);
    }
  }

  // Off, no clipboard here, or nothing (that matches) yet
  Item {
    visible: !root.strip && (root.off || root.missing || root.clips.length === 0)
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredHeight: root.embedded ? -1 : Appearance.fontSize * 8
    EmptyState {
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: parent.height
      icon: root.off ? "content_paste_off" : root.query !== "" ? "search_off" : "content_paste"
      text: root.off ? I18n.tr("Clipboard history is off (Launcher settings)") : root.missing ? I18n.tr("This compositor offers no clipboard control") : root.query !== "" ? I18n.tr("No matches") : I18n.tr("Copy something and it shows up here")
    }
  }

  GridView {
    id: list
    visible: !root.strip && !root.off && !root.missing && root.clips.length > 0
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? -1 : Math.min(contentHeight, Appearance.fontSize * 22)
    clip: true
    cellWidth: width / root.columns
    cellHeight: root.rowHeight + 2
    boundsBehavior: Flickable.StopAtBounds
    model: root.clips.length

    delegate: ItemRow {
      id: row
      required property int index
      width: GridView.view.cellWidth - (root.columns > 1 ? Widget.spacing / 2 : 0)
      height: root.rowHeight
      readonly property var entry: root.clips[index] ?? ({
          "id": "",
          "text": ""
        })
      readonly property bool pinned: ClipboardManager.isPinned(row.entry)
      icon: root.copiedId === row.entry.id ? "check" : row.entry.pinned ? "keep" : row.entry.format || row.entry.html ? "image" : "content_paste"
      image: row.entry.image ?? ""
      marked: row.entry.pinned === true || root.copiedId === row.entry.id
      title: row.titleLines > 1 ? root.previewOf(row.entry) : root.labelOf(row.entry)
      titleLines: row.entry.format || row.entry.html ? 1 : root.titleLines
      subtitle: root.detailOf(row.entry)
      onActivated: root.copy(row.entry)

      FlatIconButton {
        visible: ClipboardManager.canPin(row.entry)
        size: Widget.iconButton
        iconText: row.pinned ? "keep_off" : "keep"
        iconColor: row.pinned ? Theme.accent : Theme.foregroundAlt
        tooltipText: row.pinned ? I18n.tr("Unpin") : I18n.tr("Pin")
        onClicked: ClipboardManager.togglePin(row.entry)
      }
      FlatIconButton {
        size: Widget.iconButton
        iconText: "delete"
        tooltipText: row.entry.pinned ? I18n.tr("Unpin") : I18n.tr("Remove")
        onClicked: {
          if (row.entry.pinned)
            ClipboardManager.unpin(row.entry);
          else
            ClipboardManager.remove(row.entry);
        }
      }
    }
  }

  // A short card: the newest clip
  RowLayout {
    visible: root.strip
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Widget.spacing

    StyledIcon {
      text: root.copiedId !== "" ? "check" : "content_paste"
      textColor: Theme.accent
      textSize: Appearance.fontSizeBy(2)
    }
    StyledText {
      Layout.fillWidth: true
      text: root.off ? I18n.tr("Clipboard history is off") : root.newest ? root.labelOf(root.newest) : I18n.tr("Nothing copied yet")
      textColor: root.newest && !root.off ? Theme.foreground : Theme.foregroundAlt
      elide: Text.ElideRight
    }
    FlatIconButton {
      visible: root.newest !== null && !root.off
      size: Widget.iconButton
      iconText: "content_copy"
      tooltipText: I18n.tr("Copy")
      onClicked: root.copy(root.newest)
    }
  }
}
