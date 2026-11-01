pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.ui
import qs.components.methods

// One OSD's items, by shape (OSDItems), showing whichever changed last:
// its levels laid out by its settings (vertical bars side by side,
// horizontal bars as rows, or along its edge one line parallel to it, end
// to end when the bars run along it too), a status as one line, or the
// now playing card. Every part is built while the OSD is closed, as its
// items report their own changes.
Item {
  id: root

  // The OSD's entry (OSDConfig.osds)
  required property var osd
  required property string screenName
  // The edge it slides out of runs vertically
  property bool edgeVertical: false

  // An item changed; `force` when its showOsd says to open
  signal poked(bool force)

  readonly property var levelItems: OSDItems.ofShape(osd.items, "level")
  readonly property var statusItems: OSDItems.ofShape(osd.items, "status")
  readonly property bool hasMedia: OSDItems.ofShape(osd.items, "media").length > 0

  // "level" | "status" | "media": the part shown, the last to change (the
  // levels, else the first part it has, until one does)
  readonly property string shown: root._shown !== "" ? root._shown : root.levelItems.length > 0 ? "level" : root.statusItems.length > 0 ? "status" : "media"
  property string _shown: ""
  // When the status line last changed (Date.now()), for OSDItems.replaces
  property real _lineAt: 0

  // The OSD's largest size across its edge, whichever part shows, so its
  // window keeps room for every part (EdgePopout.maxContentDepth)
  readonly property real maxDepth: {
    const parts = [root.levelItems.length > 0 ? grid : null, root.statusItems.length > 0 || root._shown === "status" ? line : null, root.hasMedia ? card : null].filter(part => part !== null);
    return Math.max(0, ...parts.map(part => root.edgeVertical ? part.implicitWidth : part.implicitHeight));
  }

  // Length of each bar along its axis; the OSD grows with the bar count in
  // the other direction
  readonly property int barLength: Widget.px(190)
  readonly property int barSpacing: Widget.padding * 2
  readonly property bool vertical: osd.orientation === "vertical"
  // What a delegate past the end reads when the bar count drops (a restored
  // or applied config), until the Repeater removes it: no bar, rather than
  // undefined for every binding in OSDBar to guard against
  readonly property var noBar: ({
      "type": "",
      "apps": [],
      "icon": "",
      "showOsd": false
    })

  readonly property Item _current: root.shown === "status" ? line : root.shown === "media" ? card : grid
  implicitWidth: root._current.implicitWidth
  implicitHeight: root._current.implicitHeight

  // Shows a status line, unless it would cut in on the one showing
  // (OSDItems.replaces); `force` opens the OSD
  function showLine(next, force) {
    const showing = root.shown === "status" ? line.line.type : "";
    if (!OSDItems.replaces(showing, next.type, Date.now() - root._lineAt))
      return;
    line.line = next;
    root._lineAt = Date.now();
    root._shown = "status";
    root.poked(force);
  }

  // The settings page's Show: the levels, else what its first status or
  // the card shows now
  function preview() {
    if (root.levelItems.length > 0)
      root._shown = "level";
    else if (sources.count > 0)
      (sources.itemAt(0) as OSDStatusSource).preview();
  }

  GridLayout {
    id: grid
    visible: root.shown === "level"
    readonly property bool rowFlow: root.osd.alongEdge ? !root.edgeVertical : root.vertical
    flow: rowFlow ? GridLayout.LeftToRight : GridLayout.TopToBottom
    columnSpacing: root.barSpacing
    rowSpacing: root.barSpacing

    Repeater {
      // By count, so edits to a bar update it in place
      model: root.levelItems.length

      delegate: OSDBar {
        required property int index

        entry: root.levelItems[index]?.item ?? root.noBar
        screenName: root.screenName
        vertical: root.vertical
        showPercent: root.osd.showPercent
        Layout.preferredWidth: root.vertical ? implicitWidth : root.barLength
        Layout.preferredHeight: root.vertical ? root.barLength : implicitHeight
        onPoked: {
          root._shown = "level";
          root.poked(entry.showOsd);
        }
      }
    }
  }

  OSDStatusLine {
    id: line
    visible: root.shown === "status"
  }

  OSDMediaCard {
    id: card
    visible: root.shown === "media"
  }

  // The status and media items' watchers (they draw nothing)
  Repeater {
    id: sources
    // By count, as the bars
    model: root.statusItems.length + (root.hasMedia ? 1 : 0)

    delegate: OSDStatusSource {
      required property int index

      entry: index < root.statusItems.length ? root.statusItems[index].item : (OSDItems.ofShape(root.osd.items, "media")[0]?.item ?? root.noBar)
      onFired: next => {
        if (next.type === "media") {
          root._shown = "media";
          root.poked(entry.showOsd);
        } else {
          root.showLine(next, entry.showOsd);
        }
      }
    }
  }

  Connections {
    target: ShellManager

    function onOsdMessage(id, icon, text) {
      if (id !== root.osd.id)
        return;
      const own = root.osd.items.find(item => item.type === "message");
      root.showLine({
        "type": "message",
        "icon": icon || (own?.icon ?? ""),
        "text": text
      }, true);
    }

    function onShowOsd(id) {
      if (id === root.osd.id)
        root.preview();
    }
  }
}
