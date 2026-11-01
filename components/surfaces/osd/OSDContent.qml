pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.ui
import qs.components.methods

// One OSD's parts, showing whichever changed last: its bars (vertical
// bars side by side, horizontal bars as rows, or along its edge one line
// parallel to it, end to end when the bars run along it too) with its
// status icons beside them, the status icons alone (a status changed, the
// one that did highlighted), an audio device's card (it switched), or the
// now playing card. Every part is built
// while the OSD is closed, as its items report their own changes.
Item {
  id: root

  // The OSD's entry (OSDConfig.osds)
  required property var osd
  required property string screenName
  // The edge it slides out of runs vertically
  property bool edgeVertical: false
  // Its host is showing (open, or still sliding away): a status changing
  // then keeps the part shown (the bars stay, the change highlighted in
  // their row) rather than swapping the OSD's shape under the cursor, and
  // the highlight is released only once it's gone
  property bool hostOpen: false

  // An item changed; `force` when it opens the OSD
  signal poked(bool force)

  readonly property var levelItems: osd.bars.items
  readonly property var statusTypes: osd.statuses.items
  readonly property bool hasMedia: osd.media.enabled

  // "level" | "status" | "device" | "media": the part shown, the last to change (the
  // bars, else the status icons, else the card, until one does)
  readonly property string shown: root._shown !== "" ? root._shown : root.levelItems.length > 0 ? "level" : root.statusTypes.length > 0 ? "status" : "media"
  property string _shown: ""
  // The status that changed last ("" once a bar has), highlighted, and
  // when (Date.now(), for OSDItems.replaces)
  property string changed: ""
  property real _changedAt: 0
  // It was an audio device switching (its card), not its mute
  property bool _changedSwitch: false

  // Every status's tile (OSDItems.tile) by type, as its source reports it;
  // a message's from the last one
  property var tiles: ({})
  // The sources by type, and the types a click on their icon flips
  property var _sources: ({})
  property var toggleable: []
  // The icon last clicked: it stays in the row while the OSD stays open,
  // though it turned back to ordinary
  property string _held: ""
  // The status icons shown with the bars (what's unusual, every one, or
  // none) and alone (the change too)
  readonly property var _types: root.changed === "message" && !root.statusTypes.includes("message") ? root.statusTypes.concat(["message"]) : root.statusTypes
  readonly property var rowTypes: OSDItems.rowTypes(root._types, root.tiles, root.osd.statuses.row, root.changed !== "" ? root.changed : root._held)

  // The OSD shows an audio device's card as it switches
  // Every type the row may show: its statuses, and a message as one comes
  readonly property var _allTypes: root.statusTypes.includes("message") ? root.statusTypes : root.statusTypes.concat(["message"])
  readonly property bool hasDevices: root.statusTypes.includes("audio") || root.statusTypes.includes("microphone")
  // The device card's role line: what the device switched to is now used
  // for (both, a headset taking the output and the input)
  // I18n.tr("Output") I18n.tr("Input") I18n.tr("Output and input")
  readonly property string deviceRole: {
    if (root._cardType === "")
      return "";
    const other = root._cardType === "audio" ? "microphone" : "audio";
    const key = root.tiles[root._cardType]?.device ?? "";
    if (key !== "" && root.statusTypes.includes(other) && root.tiles[other]?.device === key)
      return I18n.tr("Output and input");
    return root._cardType === "audio" ? I18n.tr("Output") : I18n.tr("Input");
  }
  // The device the card shows (its status type): kept past the OSD
  // closing, so the card doesn't empty as it slides away
  property string _cardType: ""

  // The OSD's largest size across its edge, whichever part shows, so its
  // window keeps room for every part (EdgePopout.maxContentDepth). The
  // icons' at their largest (OSDStatusRow.maxDepth), not as they are: they
  // come and go while it's open (a status turning unusual, a message)
  readonly property real maxDepth: {
    const depth = item => root.edgeVertical ? item.implicitWidth : item.implicitHeight;
    const parts = [row.maxDepth];
    if (root.levelItems.length > 0)
      parts.push(depth(grid) + levels.rowSpacing + row.maxDepth);
    if (root.hasMedia)
      parts.push(depth(card));
    if (root.hasDevices)
      parts.push(depth(deviceCard));
    return Math.max(0, ...parts);
  }

  // Length of each bar along its axis; the OSD grows with the bar count in
  // the other direction
  readonly property int barLength: Widget.px(190)
  readonly property int barSpacing: Widget.padding * 2
  readonly property bool vertical: osd.bars.orientation === "vertical"
  // What a delegate past the end reads when the bar count drops (a restored
  // or applied config), until the Repeater removes it: no bar, rather than
  // undefined for every binding in OSDBar to guard against
  readonly property var noBar: ({
      "type": "",
      "apps": [],
      "icon": "",
      "showOsd": false
    })

  readonly property Item _current: root.shown === "media" ? card : root.shown === "device" ? deviceCard : levels
  implicitWidth: root._current.implicitWidth
  implicitHeight: root._current.implicitHeight

  function _setTile(type, tile) {
    const next = Object.assign({}, root.tiles);
    next[type] = tile;
    root.tiles = next;
  }

  function _register(source, add) {
    const sources = Object.assign({}, root._sources);
    if (add)
      sources[source.type] = source;
    else if (sources[source.type] === source)
      delete sources[source.type];
    root._sources = sources;
    root.toggleable = Object.keys(sources).filter(type => sources[type].canToggle);
  }

  // An icon clicked: flips it, held in place
  function toggle(type) {
    const source = root._sources[type];
    if (!source)
      return;
    root._held = type;
    source.toggle();
  }

  // The OSD gone: nothing held
  onHostOpenChanged: {
    if (!root.hostOpen) {
      root._held = "";
      root.changed = "";
    }
  }

  // A status changed: shows the icons with it highlighted (an audio
  // device switching, `switched`: its card), unless it would take the
  // highlight from one it mustn't (OSDItems.replaces); `force` opens the
  // OSD. While it's open on the bars, they stay: the change is
  // highlighted in their row
  function showStatus(type, force, switched) {
    if (root.changed !== "" && !OSDItems.replaces(root.changed, type, Date.now() - root._changedAt, root.tiles, root._changedSwitch, switched === true))
      return;
    root.changed = type;
    root._changedAt = Date.now();
    root._changedSwitch = switched === true;
    if (!(root.hostOpen && root.shown === "level")) {
      if (switched === true)
        root._cardType = type;
      root._shown = switched === true ? "device" : "status";
    }
    root.poked(force);
  }

  // The settings page's Show: the bars, else the status icons as they are
  function preview() {
    root.changed = "";
    root._shown = root.levelItems.length > 0 ? "level" : root.statusTypes.length > 0 ? "status" : "media";
  }

  // The bars with the icons beside them, or the icons alone
  GridLayout {
    id: levels
    visible: root.shown === "level" || root.shown === "status"
    flow: root.edgeVertical ? GridLayout.LeftToRight : GridLayout.TopToBottom
    rows: root.edgeVertical ? 1 : -1
    columns: root.edgeVertical ? -1 : 1
    rowSpacing: Widget.spacing * 2
    columnSpacing: Widget.spacing * 2

    GridLayout {
      id: grid
      visible: root.shown === "level"
      Layout.alignment: Qt.AlignCenter
      readonly property bool rowFlow: root.osd.bars.alongEdge ? !root.edgeVertical : root.vertical
      flow: rowFlow ? GridLayout.LeftToRight : GridLayout.TopToBottom
      columnSpacing: root.barSpacing
      rowSpacing: root.barSpacing

      Repeater {
        // By count, so edits to a bar update it in place
        model: root.levelItems.length

        delegate: OSDBar {
          required property int index

          entry: root.levelItems[index] ?? root.noBar
          screenName: root.screenName
          vertical: root.vertical
          showPercent: root.osd.bars.showPercent
          Layout.preferredWidth: root.vertical ? implicitWidth : root.barLength
          Layout.preferredHeight: root.vertical ? root.barLength : implicitHeight
          onPoked: {
            root._shown = "level";
            root.changed = "";
            root.poked(entry.showOsd);
          }
        }
      }
    }

    OSDStatusRow {
      id: row
      visible: root.rowTypes.length > 0
      Layout.alignment: Qt.AlignCenter
      types: root.rowTypes
      tiles: root.tiles
      changed: root.changed
      vertical: root.edgeVertical
      hasCaption: root._types.includes("message")
      toggleable: root.toggleable
      onToggled: type => root.toggle(type)
      allTypes: root._allTypes
    }
  }

  OSDMediaCard {
    id: card
    visible: root.shown === "media"
  }

  OSDDeviceCard {
    id: deviceCard
    visible: root.shown === "device"
    tile: root.tiles[root._cardType] ?? ({})
    role: root.deviceRole
  }

  // The types watched, as a string: any edit to an OSD parses every OSD
  // anew (OSDConfig.osds), and a new array as the model would rebuild
  // every watcher, deaf while it settles; the string changes only with
  // the types
  readonly property string _watchKey: root.statusTypes.concat(root.hasMedia ? ["media"] : []).join(",")

  // The statuses' and the card's watchers (they draw nothing)
  Repeater {
    model: root._watchKey === "" ? [] : root._watchKey.split(",")

    delegate: OSDStatusSource {
      id: watcher
      required property string modelData

      type: watcher.modelData
      mediaOptions: root.osd.media
      onTileChanged: root._setTile(watcher.type, watcher.tile)
      Component.onCompleted: {
        root._setTile(watcher.type, watcher.tile);
        root._register(watcher, true);
      }
      Component.onDestruction: root._register(watcher, false)
      onFired: switched => {
        if (watcher.type === "media") {
          root._shown = "media";
          root.poked(true);
        } else {
          root.showStatus(watcher.type, !root.osd.statuses.quiet.includes(watcher.type), switched);
        }
      }
    }
  }

  Connections {
    target: ShellManager

    function onOsdMessage(id, icon, text) {
      if (id !== root.osd.id)
        return;
      root._setTile("message", OSDItems.tile("message", {
        "icon": icon,
        "text": text
      }));
      root.showStatus("message", !root.osd.statuses.quiet.includes("message"));
    }

    function onShowOsd(id) {
      if (id === root.osd.id)
        root.preview();
    }
  }
}
