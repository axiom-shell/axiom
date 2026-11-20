pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.system
import qs.services.ui
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// App launcher buttons. `source` picks where they come from: `auto` is the
// `apps` list (desktop entry ids, e.g. firefox, kitty) or, left empty, the
// most recently launched apps; `recent`, `frequent` (the launcher's) and
// `dock` (the pinned apps) ignore `apps`.
// properties: { apps: [...], source, count, labels }
Card {
  id: root

  // The apps a derived list fits: one per unit along a strip, else one per
  // two units
  readonly property int capacity: Math.max(1, Math.min(root.cols, root.rows) === 1 ? root.cols * root.rows : Math.floor(root.cols * root.rows / 2))
  readonly property var ids: {
    const source = root.properties.source;
    const configured = root.properties.apps;
    if (source === "auto" && configured.length > 0)
      return root.properties.count === null ? configured : configured.slice(0, root.properties.count);
    let list;
    if (source === "frequent") {
      list = LauncherManager.frequentIds();
    } else if (source === "dock") {
      list = Apps.pinned;
    } else {
      const times = LauncherManager.launchTimes ?? {};
      list = Object.keys(times).sort((a, b) => times[b] - times[a]);
    }
    return list.slice(0, root.properties.count ?? root.capacity);
  }
  readonly property var entries: root.ids.map(id => DesktopEntries.heuristicLookup(id)).filter(e => e)

  EmptyState {
    anchors.centerIn: parent
    visible: root.entries.length === 0
    maxWidth: root.innerWidth
    availableHeight: root.innerHeight
    icon: "star"
    text: I18n.tr("Add apps in this module's settings")
  }

  TileGrid {
    id: grid
    anchors.fill: parent
    anchors.margins: root.pad
    count: root.entries.length
    spacing: Widget.spacing / 2
    maxAspect: 1.25

    Repeater {
      model: root.entries.length

      Rectangle {
        id: app
        required property int index
        // Follows the entries (launch times reorder them)
        readonly property var entry: root.entries[app.index] ?? null
        readonly property bool labelled: root.properties.labels === "show" || root.properties.labels === "auto" && height > Appearance.fontSize * 5
        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        radius: Style.radius
        color: "transparent"

        StateLayer {
          hovered: appArea.containsMouse
          pressed: appArea.pressed
        }

        ColumnLayout {
          anchors.centerIn: parent
          width: parent.width - Widget.px(4)
          spacing: Widget.spacing / 2
          Image {
            readonly property real side: Math.min(Appearance.fontSize * 5, Math.min(app.width, app.height) * (app.labelled ? 0.5 : 0.7))
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: side
            Layout.preferredHeight: side
            sourceSize: Qt.size(128, 128)
            source: AppIconManager.appIcon(app.entry?.icon ?? "")
          }
          StyledText {
            visible: app.labelled
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            overflow: "line"
            role: "caption"
            text: app.entry?.name ?? ""
          }
        }

        MouseArea {
          id: appArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            LauncherManager.launchApp(app.entry);
            ShellManager.closeOverlay();
          }
        }

        LazyLoader {
          active: appArea.containsMouse && !app.labelled
          StyledToolTip {
            target: app
            text: app.entry?.name ?? ""
          }
        }
      }
    }
  }
}
