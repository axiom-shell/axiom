pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

import qs.components.methods
import qs.components.reusable
import qs.components.surfaces.workspaces
import qs.config
import qs.services.apps
import qs.services.compositor
import qs.services.ui

// The screen-share picker on one screen: the whole screen dimmed, over the
// bars, and on the screen ScreenShareManager picked, a card of what an app
// may share: Screens (a frame of each, where Quickshell captures outputs),
// Windows (live on Hyprland, their icons elsewhere) and, where the portal
// can, a Region (dragged in the screenshot picker). It's modal: a click on
// the dimmed screen or Escape cancels, a double click or Enter shares.
PanelWindow {
  id: root

  readonly property var request: ScreenShareManager.request
  readonly property bool shown: request !== null && !ScreenShareManager.pickingRegion
  // The card shows here: the picked screen, else (it's gone) the primary
  readonly property bool hasCard: !!screen && General.screensNamed(ScreenShareManager.screenName)[0] === screen
  readonly property int pad: Widget.px(18)

  // "screen" | "window" | "region": the tab shown
  property string tab: "screen"
  // The tile picked ({ kind, output } | { kind, window })
  property var selection: null

  readonly property var outputs: root.request?.outputs ?? []
  readonly property var windows: ScreenShareSources.windowTiles(root.request, CompositorManager.windows)
  readonly property bool canCaptureOutputs: CompositorManager.supports.outputCapture === true

  onRequestChanged: {
    if (!root.request)
      return;
    root.selection = ScreenShareSources.initialChoice(root.request, CompositorManager.focusedOutput);
    root.tab = root.selection?.kind ?? "screen";
    Qt.callLater(() => keys.forceActiveFocus());
  }

  function share() {
    if (root.tab === "region") {
      ScreenShareManager.pickRegion();
      return;
    }
    if (root.selection && root.selection.kind === root.tab)
      ScreenShareManager.answer(root.selection);
  }

  function select(kind, token) {
    root.selection = kind === "screen" ? {
      "kind": "screen",
      "output": token
    } : {
      "kind": "window",
      "window": token
    };
  }

  function isSelected(kind, token) {
    return root.selection?.kind === kind && (kind === "screen" ? root.selection.output : root.selection.window) === token;
  }

  // The tiles of the tab shown, by token
  readonly property var tokens: root.tab === "screen" ? root.outputs.map(o => o.name) : root.tab === "window" ? root.windows.map(w => w.token) : []

  function step(by) {
    if (root.tokens.length === 0)
      return;
    const current = root.tokens.findIndex(t => root.isSelected(root.tab, t));
    const next = current < 0 ? 0 : ((current + by) % root.tokens.length + root.tokens.length) % root.tokens.length;
    root.select(root.tab, root.tokens[next]);
    grid.positionViewAtIndex(next, GridView.Contain);
  }

  function showTab(tab) {
    root.tab = tab;
    if (tab !== "region" && root.selection?.kind !== tab && root.tokens.length > 0)
      root.select(tab, root.tokens[0]);
  }

  // I18n.tr("Screens") I18n.tr("Windows") I18n.tr("Region")
  readonly property var tabs: [["screen", "Screens", "monitor"], ["window", "Windows", "select_window"]].concat(root.request?.region ? [["region", "Region", "screenshot_region"]] : [])

  // Every focus grab lets input through to it while it shows
  Component.onDestruction: SurfaceManager.unregisterModal(root)

  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  focusable: root.hasCard
  visible: shown || dim.opacity > 0

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "axiom-screenshare"
  WlrLayershell.keyboardFocus: root.shown && root.hasCard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  Component.onCompleted: {
    SurfaceManager.registerModal(root);
    // Where the compositor blurs only what a window asks: the whole dimmed
    // screen, while backdrops blur (LayerStack.blurBackdrops)
    if (CompositorManager.supports.blurRegion === true)
      BackgroundEffect.blurRegion = Qt.binding(() => BlurManager.backdropRegionsOn(root.screen) ? dimBlur : null);
  }
  BoxBlurRegion {
    id: dimBlur
    target: dim
    opacity: dim.opacity
    alpha: dim.color.a
    threshold: 0.01
  }

  Rectangle {
    id: dim
    anchors.fill: parent
    color: Appearance.darkMode ? Theme.background : Theme.foreground
    opacity: root.shown ? 0.75 : 0

    Glide on opacity {
      duration: Appearance.animNormal
    }

    // A click on the dimmed screen cancels
    MouseArea {
      anchors.fill: parent
      enabled: root.shown
      onClicked: ScreenShareManager.cancel()
    }
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Keys.onPressed: event => {
      if (!root.shown || !root.hasCard)
        return;
      if (event.key === Qt.Key_Escape) {
        ScreenShareManager.cancel();
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.share();
      } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        const at = root.tabs.findIndex(t => t[0] === root.tab);
        const by = event.key === Qt.Key_Tab ? 1 : -1;
        root.showTab(root.tabs[((at + by) % root.tabs.length + root.tabs.length) % root.tabs.length][0]);
      } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Up || event.key === Qt.Key_K) {
        root.step(-1);
      } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Down || event.key === Qt.Key_J) {
        root.step(1);
      } else {
        return;
      }
      event.accepted = true;
    }
  }

  Rectangle {
    id: card

    visible: root.hasCard
    anchors.centerIn: parent
    width: Math.min(Widget.px(860), root.width - Widget.px(32))
    height: Math.min(content.implicitHeight + root.pad * 2, root.height - Widget.px(64))
    color: Appearance.fill(Theme.background)
    border.color: Theme.border
    border.width: Appearance.borderWidth
    radius: Appearance.borderRadius
    clip: true

    opacity: root.shown ? 1 : 0
    scale: root.shown ? 1 : 0.97
    Glide on opacity {
      duration: Appearance.animNormal
    }
    Glide on scale {
      duration: Appearance.animNormal
    }

    // Swallow clicks so they don't reach the dimmed screen
    MouseArea {
      anchors.fill: parent
    }

    ColumnLayout {
      id: content
      x: root.pad
      y: root.pad
      width: card.width - root.pad * 2
      height: card.height - root.pad * 2
      spacing: root.pad

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledIcon {
          text: "screen_share"
          textSize: Appearance.fontSizeLarge
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          StyledText {
            Layout.fillWidth: true
            text: I18n.tr("Share your screen")
            textSize: Appearance.fontSizeLarge
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }

          StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.request?.appId ? I18n.tr("{0} asks what to share", root.request.appId) : ""
            textColor: Theme.foregroundInactive
            textSize: Appearance.fontSizeBy(-1)
            elide: Text.ElideRight
          }
        }
      }

      SegmentRow {
        Layout.alignment: Qt.AlignLeft

        Repeater {
          model: root.tabs

          SegmentButton {
            required property var modelData
            Layout.fillWidth: false
            iconText: modelData[2]
            text: I18n.tr(modelData[1])
            active: root.tab === modelData[0]
            onClicked: root.showTab(modelData[0])
          }
        }
      }

      GridView {
        id: grid

        // At least three to a row, so one screen isn't the card's width
        readonly property int columns: Math.max(3, Math.floor(width / Widget.px(250)))
        readonly property real tileHeight: cellWidth * 0.62 + label.implicitHeight + Widget.spacing * 2

        visible: root.tab !== "region"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: Math.min(Math.ceil(count / columns), 2.5) * cellHeight
        Layout.minimumHeight: cellHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: width / columns
        cellHeight: tileHeight
        model: root.tab === "screen" ? root.outputs : root.tab === "window" ? root.windows : []

        // Sizes the tiles' label row
        StyledText {
          id: label
          visible: false
          text: "Ag"
          textSize: Appearance.fontSizeBy(-1)
        }

        delegate: Item {
          id: tile

          required property var modelData
          required property int index
          readonly property bool isScreen: root.tab === "screen"
          readonly property string token: isScreen ? modelData.name : modelData.token
          readonly property bool selected: root.isSelected(root.tab, token)
          readonly property var shellScreen: isScreen ? General.outputs.find(s => s.name === tile.modelData.name) ?? null : null

          width: grid.cellWidth
          height: grid.cellHeight

          Rectangle {
            anchors.fill: parent
            anchors.margins: Widget.spacing / 2
            radius: Widget.radius
            color: tileMouse.containsMouse ? Theme.backgroundHighlight : "transparent"
            border.width: tile.selected ? Appearance.borderWidth * 2 : 0
            border.color: Theme.accent

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Widget.spacing / 2
              spacing: Widget.spacing / 2

              Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // A screen: one frame of it, where outputs can be captured
                ClippingRectangle {
                  visible: tile.isScreen
                  anchors.fill: parent
                  radius: Widget.radius
                  color: Theme.backgroundAlt

                  ScreencopyView {
                    anchors.fill: parent
                    captureSource: tile.isScreen && root.canCaptureOutputs && root.shown ? tile.shellScreen : null
                    constraintSize: Qt.size(Math.round(width), Math.round(height))
                    live: false
                    paintCursor: false
                  }

                  StyledIcon {
                    anchors.centerIn: parent
                    visible: !root.canCaptureOutputs || !tile.shellScreen
                    text: "monitor"
                    textSize: Appearance.fontSizeBy(14)
                    textColor: Theme.foregroundInactive
                  }
                }

                // A window: its live capture where there is one, else its
                // icon
                WindowPreview {
                  visible: !tile.isScreen
                  anchors.fill: parent
                  windowData: tile.isScreen ? null : (tile.modelData.match ?? {
                      "id": "",
                      "appId": tile.modelData.appId,
                      "title": tile.modelData.title
                    })
                  capturing: !tile.isScreen && root.shown
                  live: tile.selected
                  hovered: tileMouse.containsMouse
                  showTitle: false
                }
              }

              StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textSize: Appearance.fontSizeBy(-1)
                text: tile.isScreen ? (tile.modelData.label ? I18n.tr("{0} ({1})", tile.modelData.name, tile.modelData.label) : tile.modelData.name) : (tile.modelData.title || tile.modelData.appId || tile.modelData.token)
              }
            }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.select(root.tab, tile.token)
              onDoubleClicked: {
                root.select(root.tab, tile.token);
                root.share();
              }
            }
          }
        }

        StyledText {
          anchors.centerIn: parent
          visible: grid.count === 0
          text: root.tab === "screen" ? I18n.tr("No screen to share") : I18n.tr("No window to share")
          textColor: Theme.foregroundInactive
        }
      }

      StyledText {
        visible: root.tab === "region"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: I18n.tr("Share a part of a screen: drag a rectangle over it. Escape there comes back here.")
        textColor: Theme.foregroundInactive
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        Flow {
          Layout.fillWidth: true
          spacing: Widget.padding

          // I18n.tr("pick") I18n.tr("tab") I18n.tr("share") I18n.tr("cancel")
          Repeater {
            model: [["← →", "pick"], ["Tab", "tab"], ["↵", "share"], ["Esc", "cancel"]]

            KeyHint {
              required property var modelData
              key: modelData[0]
              label: I18n.tr(modelData[1])
            }
          }
        }

        StyledTextButton {
          text: I18n.tr("Cancel")
          onClicked: ScreenShareManager.cancel()
        }

        StyledTextButton {
          iconText: root.tab === "region" ? "screenshot_region" : "screen_share"
          text: root.tab === "region" ? I18n.tr("Drag a region") : I18n.tr("Share")
          enabled: root.tab === "region" || root.selection?.kind === root.tab
          backgroundColor: Theme.accent
          textColor: Theme.background
          onClicked: root.share()
        }
      }
    }
  }
}
