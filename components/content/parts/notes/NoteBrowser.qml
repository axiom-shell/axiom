pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import qs.config
import qs.services.apps
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

  FolderListModel {
    id: folderModel
    folder: "file://" + NotesManager.absolute(root.folder === "" ? "" : root.folder + "/")
    nameFilters: NotesConfig.extensions.map(ext => "*." + ext)
    caseSensitive: false
    showDirsFirst: true
    showDotAndDotDot: false
    showHidden: NotesConfig.showHidden
    sortField: FolderListModel.Name
  }

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
                textColor: Theme.foregroundAlt
                textSize: Appearance.fontSizeBy(-2)
              }
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: (crumb.index === 0 ? crumbLabel.implicitWidth : crumbName.implicitWidth) + Widget.spacing * 1.5
                implicitHeight: Widget.smallHeight
                radius: Widget.radius / 2
                color: crumbHover.hovered && !crumb.last ? Theme.backgroundHighlight : "transparent"

                // The top is an icon; a folder's name is text (a name like
                // "work" would draw as that icon)
                StyledIcon {
                  id: crumbLabel
                  visible: crumb.index === 0
                  anchors.centerIn: parent
                  text: "home"
                  textColor: crumb.last ? Theme.foreground : Theme.foregroundAlt
                  textSize: Appearance.fontSizeBy(1)
                }
                StyledText {
                  id: crumbName
                  visible: crumb.index > 0
                  anchors.centerIn: parent
                  text: root.crumbs[crumb.index - 1] ?? ""
                  textColor: crumb.last ? Theme.foreground : Theme.foregroundAlt
                  textSize: Appearance.fontSizeBy(-1)
                  font.bold: crumb.last
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
        iconColor: root.creating === "note" ? Theme.accent : Theme.foreground
        tooltipText: I18n.tr("New note")
        onClicked: root.creating = root.creating === "note" ? "" : "note"
      }
      FlatIconButton {
        size: Widget.iconButton
        iconText: "create_new_folder"
        iconColor: root.creating === "folder" ? Theme.accent : Theme.foreground
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
      Layout.fillWidth: true
      separatorHeight: 1
      opacity: 0.6
    }

    ListView {
      id: resultList
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
        radius: Widget.radius / 2
        color: hitHover.hovered ? Theme.backgroundHighlight : "transparent"

        HoverHandler {
          id: hitHover
          cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
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
            textColor: hit.result.path === root.current ? Theme.accent : Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(1)
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
              Layout.fillWidth: true
              text: root.highlighted(hit.result.title)
              textFormat: Text.StyledText
              textColor: hit.result.path === root.current ? Theme.accent : Theme.foreground
              textSize: Appearance.fontSizeBy(-1)
              elide: Text.ElideRight
            }
            StyledText {
              visible: text !== ""
              Layout.fillWidth: true
              text: hit.byName ? hit.result.snippet : root.highlighted(hit.result.snippet)
              textFormat: hit.byName ? Text.PlainText : Text.StyledText
              textColor: Theme.foregroundAlt
              textSize: Appearance.fontSizeBy(-2)
              elide: Text.ElideRight
            }
          }
          StyledText {
            visible: !hit.byName
            Layout.alignment: Qt.AlignTop
            text: I18n.tr("line {0}", hit.result.line + 1)
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-3)
          }
        }
      }
    }

    ListView {
      id: list
      visible: root.query === ""
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: contentHeight
      Layout.minimumHeight: Math.min(contentHeight, Widget.height)
      clip: true
      spacing: 2
      boundsBehavior: Flickable.StopAtBounds
      model: folderModel

      delegate: Rectangle {
        id: row

        required property string fileName
        required property bool fileIsDir
        readonly property string path: root.childPath(fileName)
        readonly property bool isCurrent: !fileIsDir && path === root.current
        readonly property bool editing: root.renaming === path
        readonly property bool confirming: root.confirming === path

        width: list.width
        implicitHeight: Math.max(Widget.height - Widget.px(4), rowLayout.implicitHeight + Widget.spacing / 2)
        radius: Widget.radius / 2
        color: row.confirming ? Qt.alpha(Theme.error, 0.14) : row.isCurrent ? Qt.alpha(Theme.accent, 0.16) : rowHover.hovered ? Theme.backgroundHighlight : "transparent"

        HoverHandler {
          id: rowHover
          cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
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
            textColor: row.fileIsDir ? Theme.accent : row.isCurrent ? Theme.accent : Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(1)
          }

          StyledText {
            visible: !row.editing
            Layout.fillWidth: true
            text: row.confirming ? (NotesManager.canTrash ? I18n.tr("Move {0} to the trash?", row.fileName) : I18n.tr("Delete {0} for good?", row.fileName)) : row.fileIsDir ? row.fileName : NotesManager.titleOf(row.fileName)
            textColor: row.isCurrent ? Theme.accent : Theme.foreground
            textSize: Appearance.fontSizeBy(-1)
            elide: Text.ElideRight
          }

          StyledTextEntry {
            visible: row.editing
            Layout.fillWidth: true
            Layout.preferredHeight: Widget.height - Widget.px(8)
            text: row.fileIsDir ? row.fileName : NotesManager.titleOf(row.fileName)
            onVisibleChanged: {
              if (visible) {
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
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSize
          }

          // Delete: confirm or cancel
          FlatIconButton {
            visible: row.confirming
            size: Widget.iconButton
            iconText: "check"
            iconColor: Theme.error
            iconSize: Appearance.fontSizeBy(-1)
            tooltipText: I18n.tr("Delete")
            onClicked: root.remove(row.path)
          }
          FlatIconButton {
            visible: row.confirming
            size: Widget.iconButton
            iconText: "close"
            iconSize: Appearance.fontSizeBy(-1)
            tooltipText: I18n.tr("Cancel")
            onClicked: root.confirming = ""
          }

          FlatIconButton {
            visible: rowHover.hovered && !row.editing && !row.confirming
            size: Widget.iconButton
            iconText: "edit"
            iconSize: Appearance.fontSizeBy(-2)
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
            iconSize: Appearance.fontSizeBy(-2)
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
      wrapMode: Text.WordWrap
      visible: root.query !== "" && !root.searching && root.results.length === 0
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing
      Layout.bottomMargin: Widget.spacing
      horizontalAlignment: Text.AlignHCenter
      text: I18n.tr("No notes match")
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
    }

    StyledText {
      visible: root.query === "" && list.count === 0
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing
      Layout.bottomMargin: Widget.spacing
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: NotesManager.directoryMissing ? I18n.tr("The notes folder doesn't exist: {0}", NotesManager.directory) : root.folder === "" ? I18n.tr("No notes yet") : I18n.tr("This folder is empty")
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
    }
  }
}
