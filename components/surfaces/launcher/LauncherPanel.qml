pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.components.reusable
import qs.config
import qs.services.ui

// The launcher's contents: the search field, the results and the controls
// hint, without a box of its own: its host's surface is the box (a
// FloatingPopout, or on a screen edge an EdgePopout). Reversed, the
// search field is at the bottom and the best match sits just above it.
FocusScope {
  id: root

  property bool reversed: LauncherConfig.reverse
  // Blinks the cursor only while shown
  property bool shown: true
  // The row kept selected when the rows are rebuilt for the same text
  property int selected: 0
  // Whether the pointer picks rows. Typing and keys turn it off, and only a
  // real move turns it back on: rows rebuilt under a still pointer get a
  // synthetic hover, which would otherwise select and highlight them
  property bool pointerActive: false
  property point _pointer: Qt.point(-1, -1)

  // Esc, or a row that closes the launcher
  signal closeRequested

  // Above and below the list, while it has rows
  readonly property int listMargin: Widget.smallPadding
  readonly property int rowHeight: Math.max(LauncherConfig.iconSize + Widget.padding + Widget.spacing, LauncherConfig.showDescriptions ? Appearance.fontSize * 2 + Widget.padding * 2 + Widget.spacing : Appearance.fontSize + Widget.padding * 2 + Widget.spacing / 2)
  // The tallest it gets, so a host can keep it from moving as rows come and
  // go: every block at its largest (a full list under the Frequent header).
  // Exact, not estimated: content taller than this resizes the host, which
  // on the bottom edge moves it a frame late
  readonly property int maxHeight: searchRow.height + searchLine.height + frequentLabel.implicitHeight + frequentLabel.Layout.topMargin + rowHeight * LauncherConfig.maxResults + listMargin * 2 + (LauncherConfig.showHint ? hintLine.height + hint.height : 0)

  // Holds its tallest (maxHeight), the blocks against the field's end: for
  // a host that lays its height along a screen edge (the left or right
  // one), where a box resized around its centre would move the field
  property bool holdHeight: false

  implicitWidth: LauncherConfig.width
  implicitHeight: holdHeight ? maxHeight : _blocksHeight()

  // Starts over with `text` searched (the search itself is skipped when the
  // launcher already ran it on opening)
  function reset(text) {
    input.text = text ?? "";
    input.cursorPosition = input.text.length;
    if (LauncherManager.text !== input.text)
      LauncherManager.query(input.text);
    root.selected = 0;
    list.currentIndex = 0;
    root.pointerActive = false;
    root._pointer = Qt.point(-1, -1);
    input.forceActiveFocus();
  }

  // The search is shared: a launcher open on another monitor (see
  // SurfaceGroup) shows what's typed in this one
  Connections {
    target: LauncherManager
    function onTextChanged() {
      if (input.text === LauncherManager.text)
        return;
      input.text = LauncherManager.text;
      input.cursorPosition = input.text.length;
    }
  }

  // A row reports the pointer's scene position; it only selects once the
  // pointer has moved since the last report
  function pointerAt(index, pos) {
    const moved = root._pointer.x >= 0 && (pos.x !== root._pointer.x || pos.y !== root._pointer.y);
    root._pointer = pos;
    if (!moved)
      return;
    root.pointerActive = true;
    root.selected = index;
    list.currentIndex = index;
  }

  function _syncRows() {
    const count = LauncherManager.results.length;
    if (rowModel.count > count)
      rowModel.remove(count, rowModel.count - count);
    while (rowModel.count < count)
      rowModel.append({
        row: 0
      });
    // A rebuild for the same text (a command that keeps the launcher open)
    // keeps the selection
    list.currentIndex = Math.max(0, Math.min(root.selected, count - 1));
  }

  Connections {
    target: LauncherManager
    function onResultsChanged() {
      root._syncRows();
    }
  }

  // Off until the first rows are in, so it opens at their height rather
  // than growing to it
  property bool _settled: false
  Component.onCompleted: {
    _syncRows();
    Qt.callLater(() => root._settled = true);
  }

  function select(index) {
    root.pointerActive = false;
    if (list.count === 0)
      return;
    root.selected = (index + list.count) % list.count;
    list.currentIndex = root.selected;
  }

  function activate(shift) {
    const result = LauncherManager.activate(list.currentIndex, shift);
    if (typeof result === "string") {
      input.text = result;
      input.cursorPosition = result.length;
    } else if (result === true) {
      root.closeRequested();
    }
  }

  function complete() {
    const text = LauncherManager.completion(list.currentIndex);
    if (text !== "") {
      input.text = text;
      input.cursorPosition = text.length;
    }
  }

  // The blocks top to bottom; each sits under the visible ones before it
  // (holding its height reversed, all of them down against the field)
  readonly property var _order: reversed ? [hint, hintLine, body, searchLine, searchRow] : [searchRow, searchLine, body, hintLine, hint]
  function _offset(index) {
    let y = root.holdHeight && root.reversed ? Math.max(0, root.height - root._blocksHeight()) : 0;
    for (let i = 0; i < index; i++)
      y += root._order[i].visible ? root._order[i].height : 0;
    return y;
  }
  function _blocksHeight() {
    return root._order.reduce((sum, block) => sum + (block.visible ? block.height : 0), 0);
  }

  // --- Search field ---
  RowLayout {
    id: searchRow
    y: root._offset(root._order.indexOf(searchRow))
    x: Widget.padding * 2
    width: root.width - Widget.padding * 4
    height: Appearance.fontSizeLarge + Widget.px(36)
    spacing: Widget.padding

    StyledIcon {
      readonly property var glyphs: ({
          apps: "search",
          commands: "settings",
          calc: "calculate",
          run: "terminal",
          web: "web",
          chat: "forum",
          clipboard: "content_paste",
          emoji: "mood"
        })
      text: glyphs[LauncherManager.mode] ?? glyphs.apps
      textColor: Theme.accent
      textSize: Appearance.fontSizeBy(6)
    }

    TextField {
      id: input
      Layout.fillWidth: true
      focus: true
      color: Theme.foreground
      font.family: Appearance.fontFamily
      font.pixelSize: Appearance.fontSizeLarge
      selectByMouse: true
      selectedTextColor: Theme.background
      selectionColor: Theme.accent
      placeholderText: LauncherConfig.commands ? I18n.tr("Search apps, or type / for commands") : I18n.tr("Search apps")
      placeholderTextColor: Theme.foregroundInactive
      background: null
      padding: 0

      onTextChanged: {
        root.selected = 0;
        root.pointerActive = false;
        if (text !== LauncherManager.text)
          LauncherManager.query(text);
      }

      Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        // Up moves away from the search field, whichever end it's at
        const step = root.reversed ? -1 : 1;
        if (event.key === Qt.Key_Escape) {
          root.closeRequested();
        } else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N))) {
          root.select(list.currentIndex + step);
        } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P))) {
          root.select(list.currentIndex - step);
        } else if (event.key === Qt.Key_PageDown) {
          root.select(Math.max(0, Math.min(list.count - 1, list.currentIndex + step * LauncherConfig.maxResults)));
        } else if (event.key === Qt.Key_PageUp) {
          root.select(Math.max(0, Math.min(list.count - 1, list.currentIndex - step * LauncherConfig.maxResults)));
        } else if (event.key === Qt.Key_Tab) {
          root.complete();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activate(event.modifiers & Qt.ShiftModifier);
        } else {
          return;
        }
        event.accepted = true;
      }

      cursorDelegate: Rectangle {
        width: 2
        color: Theme.accent
        visible: input.activeFocus
        SequentialAnimation on opacity {
          loops: Animation.Infinite
          running: input.activeFocus && root.shown
          PropertyAnimation {
            to: 1
            duration: 500 // behaviour timing: the cursor blink
          }
          PropertyAnimation {
            to: 0
            duration: 500 // behaviour timing: the cursor blink
          }
        }
      }
    }

    // The mode, when it isn't a plain search
    Rectangle {
      readonly property var labels: ({
          commands: I18n.tr("Commands"),
          calc: I18n.tr("Calculator"),
          run: I18n.tr("Run"),
          web: I18n.tr("Web"),
          chat: I18n.tr("Chat"),
          clipboard: I18n.tr("Clipboard"),
          emoji: I18n.tr("Emoji")
        })
      visible: modeLabel.text !== ""
      implicitWidth: modeLabel.implicitWidth + Widget.spacing * 4
      implicitHeight: modeLabel.implicitHeight + Widget.spacing * 2
      radius: Widget.radius
      color: Qt.alpha(Theme.accent, 0.16)

      StyledText {
        id: modeLabel
        anchors.centerIn: parent
        text: parent.labels[LauncherManager.mode] ?? ""
        textColor: Theme.accent
        textSize: Appearance.fontSizeBy(-2)
      }
    }

    // Clears the search, keeping the focus in it
    FlatIconButton {
      visible: input.text !== ""
      focusPolicy: Qt.NoFocus
      iconText: "close"
      iconSize: Appearance.fontSizeBy(2)
      tooltipText: I18n.tr("Clear")
      onClicked: {
        input.clear();
        input.forceActiveFocus();
      }
    }
  }

  Rectangle {
    id: searchLine
    y: root._offset(root._order.indexOf(searchLine))
    width: root.width
    height: Appearance.borderWidth
    visible: list.count > 0 || empty.visible
    color: Theme.border
  }

  // --- Results ---
  ColumnLayout {
    id: body
    y: root._offset(root._order.indexOf(body))
    width: root.width
    height: implicitHeight
    visible: list.count > 0 || empty.visible
    spacing: 0

    StyledText {
      id: frequentLabel
      Layout.leftMargin: Widget.padding * 2
      Layout.topMargin: Widget.padding
      visible: LauncherManager.frequent && list.count > 0
      text: I18n.tr("Frequent")
      textColor: Theme.foregroundInactive
      textSize: Appearance.fontSizeBy(-3)
      font.weight: Font.DemiBold
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 1
    }

    StyledText {
      id: empty
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.margins: Widget.padding * 2
      visible: list.count === 0 && input.text.trim() !== ""
      horizontalAlignment: Text.AlignHCenter
      text: I18n.tr("No results")
      textColor: Theme.foregroundInactive
    }

    // The list at its rows' height (and a margin each side), in a frame
    // whose height glides to it as matches come and go, the blocks after
    // it and the box with it: the list itself is never resized
    // mid-animation, only clipped while the frame catches up
    Item {
      id: listFrame
      readonly property real targetHeight: list.count > 0 ? list.height + root.listMargin * 2 : 0
      Layout.fillWidth: true
      Layout.preferredHeight: drawnHeight
      clip: drawnHeight !== targetHeight
      property real drawnHeight: targetHeight
      Glide on drawnHeight {
        enabled: root._settled
      }

      ListView {
        id: list
        // Reversed, the best match stays against the field
        y: root.reversed ? listFrame.height - root.listMargin - height : root.listMargin
        width: listFrame.width
        height: Math.min(count, LauncherConfig.maxResults) * root.rowHeight
        clip: true
        interactive: count > LauncherConfig.maxResults
        boundsBehavior: Flickable.StopAtBounds
        // The best match next to the search field
        verticalLayoutDirection: root.reversed ? ListView.BottomToTop : ListView.TopToBottom
        highlightMoveDuration: Appearance.animFast
        highlightFollowsCurrentItem: true
        currentIndex: 0
        // One entry per row, grown and shrunk at the end, so the rows survive
        // each keystroke and only their contents change (a new model would
        // rebuild every row and fade the selection back in)
        model: ListModel {
          id: rowModel
        }

        // Rows added at the end (more matches) fade in. Displaced rows are
        // brought back to full opacity: an add interrupted by the next
        // keystroke would otherwise leave its row half faded.
        add: Transition {
          NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: Appearance.animNormal
            easing.type: Appearance.easing
          }
        }
        displaced: Transition {
          NumberAnimation {
            property: "opacity"
            to: 1
            duration: Appearance.animFast
            easing.type: Appearance.easing
          }
        }

        delegate: LauncherRow {
          modelData: LauncherManager.results[index] ?? ({})
          width: ListView.view.width
          height: root.rowHeight
          current: ListView.isCurrentItem
          pointerActive: root.pointerActive
          onHovered: pos => root.pointerAt(index, pos)
          onClicked: {
            list.currentIndex = index;
            root.activate(false);
          }
        }
      }
    }
  }

  // --- Controls hint ---
  Rectangle {
    id: hintLine
    y: root._offset(root._order.indexOf(hintLine))
    width: root.width
    height: Appearance.borderWidth
    visible: LauncherConfig.showHint
    color: Theme.border
  }

  Item {
    id: hint
    y: root._offset(root._order.indexOf(hint))
    width: root.width
    height: hintFlow.implicitHeight + Widget.padding * 2
    visible: LauncherConfig.showHint

    Flow {
      id: hintFlow
      x: Widget.padding * 2
      y: Widget.padding
      width: parent.width - Widget.padding * 4
      spacing: Widget.padding

      Repeater {
        // I18n.tr("commands") I18n.tr("calculate") I18n.tr("run") I18n.tr("web")
        // I18n.tr("complete") I18n.tr("open") I18n.tr("ask") I18n.tr("clipboard")
        // I18n.tr("emoji")
        model: [[LauncherConfig.commands, "/", "commands"], [LauncherConfig.calculator, "=", "calculate"], [LauncherConfig.runCommands, ">", "run"], [LauncherConfig.webSearch, "?", "web"], [LauncherConfig.chat, "@", "ask"], [LauncherConfig.clipboard, ":", "clipboard"], [LauncherConfig.emoji, ";", "emoji"], [true, "Tab", "complete"], [true, "↵", "open"]].filter(hint => hint[0])

        KeyHint {
          required property var modelData
          key: modelData[1]
          label: I18n.tr(modelData[2])
        }
      }
    }
  }
}
