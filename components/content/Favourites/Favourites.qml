pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// App launcher buttons. `apps` lists desktop entry ids (e.g. firefox,
// kitty); left empty, it shows the most recently launched apps.
// properties: { apps: [...], showLabels }
Card {
  id: root

  // Recent apps: one per unit along a strip, else one per two units
  readonly property int capacity: Math.max(1, Math.min(root.cols, root.rows) === 1 ? root.cols * root.rows : Math.floor(root.cols * root.rows / 2))
  readonly property var ids: {
    const configured = root.properties.apps;
    if (configured.length > 0)
      return configured;
    const times = LauncherManager.launchTimes ?? {};
    return Object.keys(times).sort((a, b) => times[b] - times[a]).slice(0, root.capacity);
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
      model: root.entries

      Rectangle {
        id: app
        required property var modelData
        required property int index
        readonly property bool labelled: root.properties.showLabels && height > Appearance.fontSize * 5
        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        radius: Widget.radius
        color: appArea.containsMouse ? Theme.backgroundHighlight : "transparent"

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
            source: Quickshell.iconPath(app.modelData.icon, "application-x-executable")
          }
          StyledText {
            visible: app.labelled
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: app.modelData.name
            textSize: Appearance.fontSizeBy(-2)
          }
        }

        MouseArea {
          id: appArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            LauncherManager.launchApp(app.modelData);
            ShellManager.closeOverlay();
          }
        }

        LazyLoader {
          active: appArea.containsMouse && !app.labelled
          StyledToolTip {
            target: app
            text: app.modelData.name
          }
        }
      }
    }
  }
}
