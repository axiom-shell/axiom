pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.content.parts.notes
import qs.components.content.parts
import qs.components.content.base

// Markdown notes from the notes folder (NotesManager), with checklists,
// rendered but for the paragraph being edited. The header's note name opens
// a list of the folder's notes and folders, with a search over them all;
// Ctrl+F (or the toolbar) finds in the note.
// with `lockNote` the module only ever shows its `note`, and the header and
// toolbar can go, for a bare scratchpad (e.g. in an edge menu).
// properties: { note, lockNote, showHeader, showToolbar, showCompleted }
Card {
  id: root

  readonly property string configuredNote: NotesManager.clean(root.properties.note)
  readonly property bool locked: root.properties.lockNote && root.configuredNote !== ""
  // The last note is remembered per place the module is shown
  readonly property string placeKey: root.host.kind === "edgeMenu" ? "edgeMenu:" + root.host.id : root.host.kind === "desktop" ? "desktop:" + root.host.screen : "overlay"

  // The note shown, and its NotesManager document
  property string path: ""
  property var note: null
  property bool browserOpen: false
  property bool findOpen: false
  property bool showCompleted: root.properties.showCompleted

  // Compact, a headerless scratchpad; too small for a few lines, the
  // note's name and checklist progress
  readonly property bool tiny: root.innerHeight < Appearance.fontSize * 4 || root.innerWidth < Appearance.fontSize * 6
  readonly property bool showHeader: root.properties.showHeader && !root.compact
  // The toolbar's buttons only where they leave the name some room
  readonly property bool showToolbar: root.properties.showToolbar && !root.compact && root.innerWidth >= Appearance.fontSize * 16

  function show(path) {
    const rel = NotesManager.clean(path);
    if (rel === "" || (rel === root.path && root.note))
      return;
    if (root.note)
      NotesManager.release(root.path);
    root.path = rel;
    root.note = NotesManager.acquire(rel);
    if (!root.locked)
      NotesManager.setLastOpened(root.placeKey, rel);
  }

  // A search result: the note, at a line (0-based, or -1)
  function reveal(path, line) {
    root.show(path);
    if (line >= 0)
      editor.revealLine(line);
  }

  function openFind(text) {
    if (text !== "")
      findField.text = text;
    root.findOpen = true;
    findField.input.forceActiveFocus();
    findField.input.selectAll();
    editor.find(findField.text, 0);
  }

  function closeFind(select) {
    root.findOpen = false;
    editor.endFind(select);
  }

  function _initial() {
    return root.configuredNote || NotesManager.lastOpened(root.placeKey) || NotesManager.defaultNote;
  }

  // A different configured note (or lock) takes effect at once
  onConfiguredNoteChanged: {
    if (root._ready && root.configuredNote !== "")
      root.show(root.configuredNote);
  }

  property bool _ready: false
  Component.onCompleted: {
    root._ready = true;
    // Opened for a note from the launcher
    const pending = root.locked ? null : NotesManager.takeReveal(root.placeKey);
    if (pending)
      root.reveal(pending.path, pending.line);
    else
      root.show(root._initial());
  }
  Component.onDestruction: {
    if (root.note)
      NotesManager.release(root.path);
  }

  Connections {
    target: NotesManager
    // Renamed: the document already moved, so only the path follows
    function onMoved(from, to) {
      if (!NotesManager.within(root.path, from))
        return;
      root.path = to + root.path.slice(from.length);
      if (!root.locked)
        NotesManager.setLastOpened(root.placeKey, root.path);
    }
    function onOpenRequested(path, line, place) {
      if (place !== root.placeKey || root.locked)
        return;
      NotesManager.takeReveal(place);
      root.reveal(path, line);
    }
    function onRemoved(path) {
      if (NotesManager.within(root.path, path) && !root.locked) {
        NotesManager.release(root.path);
        root.note = null;
        root.path = "";
        root.show(NotesManager.allNotes.find(note => !NotesManager.within(note, path)) ?? NotesManager.defaultNote);
      }
    }
  }

  CompactFigure {
    visible: root.tiny
    anchors.fill: parent
    anchors.margins: root.pad
    icon: "sticky_note_2"
    value: editor.progress.total > 0 ? `${editor.progress.done}/${editor.progress.total}` : ""
    label: NotesManager.titleOf(root.path)
  }

  ColumnLayout {
    visible: !root.tiny
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    RowLayout {
      id: header
      visible: root.showHeader || root.showToolbar
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      // The note's name: opens the note list, or just a title when locked
      Rectangle {
        visible: root.showHeader
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.iconButton
        radius: Widget.radius / 2
        color: !root.locked && (root.browserOpen || chipHover.hovered) ? Theme.backgroundHighlight : Qt.alpha(Theme.backgroundHighlight, 0)

        ColorGlide on color {}

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: root.locked ? 0 : Widget.spacing / 2
          anchors.rightMargin: Widget.spacing / 2
          spacing: Widget.spacing

          StyledIcon {
            text: "sticky_note_2"
            textColor: Theme.accent
            textSize: Appearance.fontSizeBy(2)
          }
          StyledText {
            Layout.fillWidth: true
            text: NotesManager.titleOf(root.path)
            font.bold: true
            elide: Text.ElideMiddle
          }
          StyledText {
            visible: editor.progress.total > 0
            text: editor.progress.done + "/" + editor.progress.total
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-2)
          }
          StyledIcon {
            visible: !root.locked
            text: root.browserOpen ? "expand_less" : "expand_more"
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSize
          }
        }

        HoverHandler {
          id: chipHover
          enabled: !root.locked
          cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
          enabled: !root.locked
          onTapped: root.browserOpen = !root.browserOpen
        }
      }

      Item {
        visible: !root.showHeader
        Layout.fillWidth: true
      }

      FlatIconButton {
        visible: root.showToolbar
        iconText: "checklist"
        iconColor: Theme.foreground
        tooltipText: I18n.tr("Checklist")
        focusPolicy: Qt.NoFocus
        onClicked: editor.toggleTask()
      }
      FlatIconButton {
        visible: root.showToolbar
        iconText: "format_list_bulleted"
        iconColor: Theme.foreground
        tooltipText: I18n.tr("Bulleted list")
        focusPolicy: Qt.NoFocus
        onClicked: editor.toggleBullet()
      }
      FlatIconButton {
        visible: root.showToolbar
        iconText: "search"
        iconColor: root.findOpen ? Theme.accent : Theme.foreground
        tooltipText: I18n.tr("Find in note")
        focusPolicy: Qt.NoFocus
        onClicked: root.findOpen ? root.closeFind(false) : root.openFind("")
      }
      FlatIconButton {
        visible: root.showToolbar && editor.progress.done > 0
        iconText: root.showCompleted ? "visibility" : "visibility_off"
        iconColor: root.showCompleted ? Theme.foreground : Theme.accent
        tooltipText: root.showCompleted ? I18n.tr("Hide completed items") : I18n.tr("Show completed items")
        focusPolicy: Qt.NoFocus
        onClicked: root.showCompleted = !root.showCompleted
      }
      FlatIconButton {
        visible: root.showHeader && !root.locked
        iconText: "note_add"
        iconColor: Theme.foreground
        tooltipText: I18n.tr("New note")
        onClicked: NotesManager.createNote(NotesManager.parentOf(root.path), "", path => root.show(path))
      }
    }

    StyledSeparator {
      visible: header.visible
      Layout.fillWidth: true
      separatorHeight: 1
      opacity: 0.6
    }

    // Find in note: Enter / Shift+Enter step through the matches, Escape
    // closes, leaving the match selected
    RowLayout {
      visible: root.findOpen
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      StyledTextEntry {
        id: findField
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.height
        placeholderText: I18n.tr("Find in note")
        onTextChanged: {
          if (root.findOpen)
            editor.find(text, 0);
        }
        input.Keys.onPressed: event => {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            editor.find(findField.text, event.modifiers & Qt.ShiftModifier ? -1 : 1);
            event.accepted = true;
          } else if (event.key === Qt.Key_Escape) {
            root.closeFind(true);
            event.accepted = true;
          }
        }
      }
      StyledText {
        visible: findField.text !== ""
        text: editor.findCount === 0 ? I18n.tr("No matches") : I18n.tr("{0}/{1}", editor.findIndex + 1, editor.findCount)
        textColor: editor.findCount === 0 ? Theme.error : Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
      }
      FlatIconButton {
        iconText: "keyboard_arrow_up"
        iconColor: Theme.foreground
        tooltipText: I18n.tr("Previous match")
        focusPolicy: Qt.NoFocus
        onClicked: editor.find(findField.text, -1)
      }
      FlatIconButton {
        iconText: "keyboard_arrow_down"
        iconColor: Theme.foreground
        tooltipText: I18n.tr("Next match")
        focusPolicy: Qt.NoFocus
        onClicked: editor.find(findField.text, 1)
      }
      FlatIconButton {
        iconText: "close"
        iconColor: Theme.foreground
        tooltipText: I18n.tr("Close")
        focusPolicy: Qt.NoFocus
        onClicked: root.closeFind(false)
      }
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      NoteEditor {
        id: editor
        anchors.fill: parent
        note: root.note
        showCompleted: root.showCompleted
        onFindRequested: text => root.openFind(text)
      }

      // The note list closes on a click beside it
      MouseArea {
        anchors.fill: parent
        visible: root.browserOpen
        onClicked: root.browserOpen = false
      }

      Loader {
        active: root.browserOpen
        anchors.top: parent.top
        anchors.left: parent.left
        width: Math.min(parent.width, Widget.px(320))
        sourceComponent: NoteBrowser {
          current: root.path
          maxHeight: editor.height
          onPicked: (path, line) => {
            root.reveal(path, line);
            root.browserOpen = false;
          }
        }
      }
    }

    StyledText {
      visible: NotesManager.error !== ""
      Layout.fillWidth: true
      text: NotesManager.error
      textColor: Theme.error
      textSize: Appearance.fontSizeBy(-2)
      elide: Text.ElideRight
    }
  }
}
