pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.forms

// How workspaces are laid out (the Workspaces section), with a small
// picture of two monitors in the chosen layout. Windows tile here: strips
// are set up in Settings. Not shown where the compositor makes its
// workspaces itself (OnboardingManager.pages).
OnboardingPage {
  id: root

  readonly property string layout: WorkspacesConfig.layout

  readonly property bool canScroll: CompositorManager.supports.strips === true && CompositorManager.supports.stripsAlways !== true

  title: I18n.tr("Workspaces")
  intro: I18n.tr("Workspaces are the desktops you switch between with Super + a number. The bar, the overview and the keybinds all follow the layout you pick here.")

  Repeater {
    model: [
      {
        "layout": "perMonitor",
        "icon": "view_week",
        "title": I18n.tr("Per monitor"),
        "description": I18n.tr("Each monitor has its own workspaces 1 to N. Super + 3 goes to workspace 3 of the monitor you're on.")
      },
      {
        "layout": "standard",
        "icon": "view_column",
        "title": I18n.tr("Standard"),
        "description": I18n.tr("One set of workspaces, 1 to N, shared by every monitor, as compositors do by default.")
      },
      {
        "layout": "grid",
        "icon": "grid_view",
        "title": I18n.tr("Grid"),
        "description": I18n.tr("Each monitor has a grid of workspaces, and you move up, down, left and right between them.")
      },
      {
        "layout": "scrolling",
        "icon": "view_carousel",
        "title": I18n.tr("Scrolling (niri style)"),
        "description": I18n.tr("As on niri: each monitor has a column of workspaces, made as you fill them, with an empty one at the end, and its windows open side by side on a strip that scrolls sideways to the focused one.")
      }
    ]

    delegate: OptionCard {
      required property var modelData
      // Scrolling needs strips, and is what a compositor that only has
      // strips does already
      visible: modelData.layout !== "scrolling" || root.canScroll
      icon: modelData.icon
      title: modelData.title
      description: modelData.description
      selected: root.layout === modelData.layout
      recommended: modelData.layout === "perMonitor"
      onClicked: SettingsManager.commitValues({
        "Workspaces.layout": modelData.layout
      })
    }
  }

  // Two monitors in the chosen layout
  Row {
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: Widget.spacing
    spacing: Widget.spacing * 2

    Repeater {
      model: 2

      delegate: Rectangle {
        id: monitor
        required property int index
        // Scrolling: a column of workspaces, the last one empty
        readonly property bool column: root.layout === "scrolling" && root.canScroll
        readonly property int columns: root.layout === "grid" ? WorkspacesConfig.columns : column ? 1 : Math.min(WorkspacesConfig.count, 5)
        readonly property int rows: root.layout === "grid" ? WorkspacesConfig.rows : column ? 3 : 1
        width: root.cardWidth * 0.36
        height: width * 0.6
        radius: Widget.radius / 2
        color: Theme.backgroundAlt
        border.color: Theme.border
        border.width: Appearance.borderWidth

        Grid {
          anchors.centerIn: parent
          columns: monitor.columns
          spacing: Widget.spacing

          Repeater {
            model: monitor.columns * monitor.rows

            delegate: Rectangle {
              required property int index
              // Shared ids: each monitor shows a different one of them
              readonly property bool active: index === (root.layout === "standard" ? monitor.index : 0)
              width: Math.min((monitor.width - Widget.px(16)) / monitor.columns - Widget.spacing, (monitor.height - Widget.px(16)) / monitor.rows - Widget.spacing)
              height: width
              radius: Widget.px(3)
              color: active ? Theme.accent : Theme.backgroundHighlight

              StyledText {
                anchors.centerIn: parent
                visible: root.layout !== "grid" && parent.width > Appearance.fontSize
                text: String(parent.index + 1)
                textSize: Math.max(Widget.px(8), parent.width * 0.45)
                textColor: parent.active ? Theme.background : Theme.foreground
              }
            }
          }
        }
      }
    }
  }

  SettingRows {
    Layout.fillWidth: true
    paths: ["Workspaces.count", "Workspaces.columns", "Workspaces.rows", "Workspaces.wrap"]
  }
}
