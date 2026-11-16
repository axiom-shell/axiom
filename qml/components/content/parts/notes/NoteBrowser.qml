pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.services.core
import qs.components.reusable

// The notes folder, one level at a time: folders first, then notes. A
// folder opens on click; the path above goes back up. Notes and folders
// can be made, renamed and sent to the trash here. The search field above
// looks through every note's name and text instead (NotesManager.search).
DropdownSurface {
  id: root

  // The open note, highlighted
  property string current: ""
  // The folder shown (relative, "" for the top)
  property string folder: NotesManager.parentOf(root.current)
  property real maxHeight: Widget.px(400)

  // A note, and the line to show (0-based, or -1)
  signal picked(string path, int line)

  // The row being renamed or confirming a delete (its path, "" for none)
  property string renaming: ""
  property string confirming: ""
  // "note" | "folder" while naming a new one, else ""
  property string creating: ""

  readonly property var crumbs: root.folder === "" ? [] : root.folder.split("/")

  // The search field's text, and its results ([] while it's empty)
  readonly property string query: searchField.text.trim()
  property var results: []
  property bool searching: false

  onQueryChanged: {
    root.searching = root.query !== "";
    if (root.query === "") {
      root.results = [];
      NotesManager.search("");
    } else {
      searchDelay.restart();
    }
  }

  Timer {
    id: searchDelay
    interval: 200
    onTriggered: NotesManager.search(root.query, results => {
      root.results = results;
      root.searching = false;
    })
  }

  // The result's text with the query in bold, as rich text
  function highlighted(text) {
    const escape = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const at = text.toLowerCase().indexOf(root.query.toLowerCase());
    if (at < 0 || root.query === "")
      return escape(text);
    const end = at + root.query.length;
    return escape(text.slice(0, at)) + "<b>" + escape(text.slice(at, end)) + "</b>" + escape(text.slice(end));
  }

  function childPath(name) {
    return root.folder === "" ? name : root.folder + "/" + name;
  }

  function open(folder) {
    root.folder = folder;
    root.renaming = "";
    root.confirming = "";
    root.creating = "";
  }

  function remove(path) {
    root.confirming = "";
    NotesManager.trash(path);
  }

  implicitHeight: Math.min(root.maxHeight, content.implicitHeight + Widget.spacing * 2)

  // The folder's entries ([{ name, isDir }], NotesManager.listFolder),
  // listed again when it, the listing's settings or an entry change
  property var entries: []
  property int _listings: 0
  property var _watch: null
  readonly property string _listed: [NotesManager.directory, root.folder, NotesConfig.extensions.join(), NotesConfig.showHidden].join("\n")

  function relist() {
    const listing = ++root._listings;
    NotesManager.listFolder(root.folder, entries => {
      if (listing === root._listings && JSON.stringify(entries) !== JSON.stringify(root.entries))
        root.entries = entries;
    });
  }

  function _rewatch() {
    FileManager.unwatch(root._watch);
    root._watch = NotesManager.watchFolder(root.folder, () => root.relist());
  }

  on_ListedChanged: {
    root._rewatch();
    root.relist();
  }
  Component.onCompleted: {
    root._rewatch();
    root.relist();
  }
  Component.onDestruction: FileManager.unwatch(root._watch)

  ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Widget.spacing
    spacing: Widget.spacing / 2

    // Where we are, and new note / new folder
    RowLayout {
      Layout.fillWidth: true
      spacing: 2

      Flickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Widget.iconButton
        contentWidth: crumbRow.implicitWidth
        contentX: Math.max(0, contentWidth - width)
        clip: true
        interactive: contentWidth > width

        Row {
          id: crumbRow
          height: parent.height
          spacing: 0

          Repeater {
            model: root.crumbs.length + 1
            delegate: Row {
              id: crumb
              required property int index
              readonly property bool last: index === root.crumbs.length
              height: crumbRow.height

              StyledIcon {
                visible: crumb.index > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "chevron_right"
                size: "xs"
                tone: "faint"
              }
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: (crumb.index === 0 ? crumbLabel.implicitWidth : crumbName.implicitWidth) + Widget.spacing * 1.5
                implicitHeight: Math.max(Widget.smallHeight, (crumb.index === 0 ? crumbLabel.implicitHeight : crumbName.implicitHeight) + Widget.spacing)
                radius: Style.radiusInner
                color: "transparent"

                StateLayer {
                  hovered: crumbHover.hovered && !crumb.last
                  radius: parent.radius
                }

                // The top is an icon; a folder's name is text (a name like
                // "work" would draw as that icon)
                StyledIcon {
                  id: crumbLabel
                  visible: crumb.index === 0
                  anchors.centerIn: parent
                  text: "home"
                  size: "sm"
                  tone: crumb.last ? "text" : "muted"
                }
                StyledLabel {
                  id: crumbName
                  visible: crumb.index > 0
                  anchors.centerIn: parent
                  text: root.crumbs[crumb.index - 1] ?? ""
                  role: "caption"
                  tone: crumb.last ? "text" : "muted"
                  font.weight: crumb.last ? Style.weightStrong : Style.roleCaption.weight
                }
                HoverHandler {
                  id: crumbHover
                  cursorShape: crumb.last ? Qt.ArrowCursor : Qt.PointingHandCursor
                }
                TapHandler {
                  enabled: !crumb.last
                  onTapped: root.open(root.crumbs.slice(0, crumb.index).join("/"))
                }
              }
            }
          }
        }
      }

      FlatIconButton {
        size: Widget.iconButton
        iconText: "note_add"
        iconColor: root.creating === "note" ? Style.accent : Style.text
        tooltipText: I18n.tr("New note")
        onClicked: root.creating = root.creating === "note" ? "" : "note"
      }
      FlatIconButton {
        size: Widget.iconButton
        iconText: "create_new_folder"
        iconColor: root.creating === "folder" ? Style.accent : Style.text
        tooltipText: I18n.tr("New folder")
        onClicked: root.creating = root.creating === "folder" ? "" : "folder"
      }
    }

    StyledTextEntry {
      id: nameField
      visible: root.creating !== ""
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      placeholderText: root.creating === "folder" ? I18n.tr("Folder name") : I18n.tr("Note name")
      onVisibleChanged: {
        text = "";
        if (visible)
          input.forceActiveFocus();
      }
      onAccepted: {
        if (root.creating === "folder")
          NotesManager.createFolder(root.folder, text, path => root.open(path));
        else
          NotesManager.createNote(root.folder, text, path => root.picked(path, -1));
        root.creating = "";
      }
      input.Keys.onEscapePressed: root.creating = ""
    }

    // Enter opens the first result, Escape clears the field
    StyledTextEntry {
      id: searchField
      visible: root.creating === ""
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      placeholderText: I18n.tr("Search notes")
      clearable: true
      escapeClears: true
      Component.onCompleted: input.forceActiveFocus()
      onAccepted: {
        const first = root.results[0];
        if (first)
          root.picked(first.path, first.line);
      }
    }

    StyledSeparator {
      backTone: "raised"
      Layout.fillWidth: true
    }

    MotionListView {
      id: resultList
      ScrollIndicator.vertical: StyledScrollIndicator {}

      visible: root.query !== ""
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: contentHeight
      Layout.minimumHeight: Math.min(contentHeight, Widget.height)
      clip: true
      spacing: 2
      boundsBehavior: Flickable.StopAtBounds
      model: root.results.length

      delegate: Rectangle {
        id: hit

        required property int index
        readonly property var result: root.results[index]
        readonly property bool byName: hit.result.line < 0

        width: resultList.width
        implicitHeight: hitLayout.implicitHeight + Widget.spacing
        radius: Style.radiusInner
        color: "transparent"

        StateLayer {
          hovered: hitHover.hovered
          pressed: hitTap.pressed
        }

        HoverHandler {
          id: hitHover
          cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
          id: hitTap
          onTapped: root.picked(hit.result.path, hit.result.line)
        }

        RowLayout {
          id: hitLayout
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Widget.spacing
          anchors.rightMargin: Widget.spacing
          spacing: Widget.spacing

          StyledIcon {
            Layout.alignment: Qt.AlignTop
            text: hit.byName ? "description" : "notes"
            size: "sm"
            tone: hit.result.path === root.current ? "accent" : "muted"
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledLabel {
              Layout.fillWidth: true
              text: root.highlighted(hit.result.title)
              textFormat: Text.StyledText
              role: "caption"
              tone: hit.result.path === root.current ? "accent" : "text"
              overflow: "line"
            }
            StyledLabel {
              visible: text !== ""
              Layout.fillWidth: true
              text: hit.byName ? hit.result.snippet : root.highlighted(hit.result.snippet)
              textFormat: hit.byName ? Text.PlainText : Text.StyledText
              role: "caption"
              overflow: "line"
            }
          }
          StyledLabel {
            visible: !hit.byName
            Layout.alignment: Qt.AlignTop
            text: I18n.tr("line {0}", hit.result.line + 1)
            role: "micro"
          }
        }
      }
    }

    MotionListView {
      id: list
      ScrollIndicator.vertical: StyledScrollIndicator {}

      visible: root.query === ""
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: contentHeight
      Layout.minimumHeight: Math.min(contentHeight, Widget.height)
      clip: true
      spacing: 2
      boundsBehavior: Flickable.StopAtBounds
      model: root.entries.length

      delegate: Rectangle {
        id: row

        required property int index
        readonly property string fileName: root.entries[index]?.name ?? ""
        readonly property bool fileIsDir: root.entries[index]?.isDir ?? false
        readonly property string path: root.childPath(fileName)
        readonly property bool isCurrent: !fileIsDir && path === root.current
        readonly property bool editing: root.renaming === path
        readonly property bool confirming: root.confirming === path

        width: list.width
        implicitHeight: Math.max(Widget.height, rowLayout.implicitHeight + Widget.spacing / 2)
        radius: Style.radiusInner
        color: row.confirming ? Style.errorContainer : row.isCurrent ? Style.accentContainer : "transparent"

        StateLayer {
          hovered: rowHover.hovered
          pressed: rowTap.pressed
        }

        HoverHandler {
          id: rowHover
          cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
          id: rowTap
          enabled: !row.editing && !row.confirming
          onTapped: {
            if (row.fileIsDir)
              root.open(row.path);
            else
              root.picked(row.path, -1);
          }
        }

        RowLayout {
          id: rowLayout
          anchors.fill: parent
          anchors.leftMargin: Widget.spacing
          anchors.rightMargin: Widget.spacing
          spacing: Widget.spacing

          StyledIcon {
            text: row.fileIsDir ? "folder" : "description"
            fill: row.fileIsDir ? 1 : 0
            size: "sm"
            textColor: row.confirming ? Style.inkErrorContainer.text : row.isCurrent ? Style.inkAccentContainer.text : row.fileIsDir ? Style.accent : Style.textMuted
          }

          StyledLabel {
            visible: !row.editing
            Layout.fillWidth: true
            text: row.confirming ? (NotesManager.canTrash ? I18n.tr("Move {0} to the trash?", row.fileName) : I18n.tr("Delete {0} for good?", row.fileName)) : row.fileIsDir ? row.fileName : NotesManager.titleOf(row.fileName)
            role: "caption"
            textColor: row.confirming ? Style.inkErrorContainer.text : row.isCurrent ? Style.inkAccentContainer.text : Style.text
            overflow: "line"
          }

          StyledTextEntry {
            visible: row.editing
            Layout.fillWidth: true
            Layout.preferredHeight: Widget.height - Widget.px(8)
            // Pushed in as it opens: typing drops a binding, and a
            // cancelled rename's text would come back
            onVisibleChanged: {
              if (visible) {
                text = row.fileIsDir ? row.fileName : NotesManager.titleOf(row.fileName);
                input.forceActiveFocus();
                input.selectAll();
              }
            }
            onAccepted: {
              NotesManager.rename(row.path, text, row.fileIsDir);
              root.renaming = "";
            }
            input.Keys.onEscapePressed: root.renaming = ""
          }

          StyledIcon {
            visible: row.fileIsDir && !row.editing && !row.confirming && !rowHover.hovered
            text: "chevron_right"
            tone: "muted"
            size: "sm"
          }

          // Delete: confirm or cancel
          FlatIconButton {
            visible: row.confirming
            size: Widget.iconButton
            iconText: "check"
            iconColor: Style.inkErrorContainer.text
            iconSize: Style.iconSm
            tooltipText: I18n.tr("Delete")
            onClicked: root.remove(row.path)
          }
          FlatIconButton {
            visible: row.confirming
            size: Widget.iconButton
            iconText: "close"
            iconColor: Style.inkErrorContainer.text
            iconSize: Style.iconSm
            tooltipText: I18n.tr("Cancel")
            onClicked: root.confirming = ""
          }

          FlatIconButton {
            visible: rowHover.hovered && !row.editing && !row.confirming
            size: Widget.iconButton
            iconText: "edit"
            iconColor: row.isCurrent ? Style.inkAccentContainer.muted : Style.textMuted
            iconSize: Style.iconXs
            tooltipText: I18n.tr("Rename")
            onClicked: {
              root.confirming = "";
              root.renaming = row.path;
            }
          }
          FlatIconButton {
            visible: rowHover.hovered && !row.editing && !row.confirming
            size: Widget.iconButton
            iconText: "delete"
            iconColor: row.isCurrent ? Style.inkAccentContainer.muted : Style.textMuted
            iconSize: Style.iconXs
            tooltipText: I18n.tr("Delete")
            onClicked: {
              root.renaming = "";
              // Without a trash, deleting is for good: always asked
              if (NotesConfig.confirmDelete || !NotesManager.canTrash)
                root.confirming = row.path;
              else
                root.remove(row.path);
            }
          }
        }
      }
    }

    StyledText {
      visible: root.query !== "" && !root.searching && root.results.length === 0
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing
      Layout.bottomMargin: Widget.spacing
      horizontalAlignment: Text.AlignHCenter
      text: I18n.tr("No notes match")
      role: "caption"
    }

    StyledText {
      visible: root.query === "" && list.count === 0
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing
      Layout.bottomMargin: Widget.spacing
      horizontalAlignment: Text.AlignHCenter
      text: NotesManager.directoryMissing ? I18n.tr("The notes folder doesn't exist: {0}", NotesManager.directory) : root.folder === "" ? I18n.tr("No notes yet") : I18n.tr("This folder is empty")
      role: "caption"
    }
  }
}
