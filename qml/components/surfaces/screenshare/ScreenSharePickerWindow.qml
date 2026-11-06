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
  readonly property int pad: Widget.px(24)

  // "screen" | "window" | "region": the tab shown
  property string tab: "screen"
  // The tile picked ({ kind, output } | { kind, window })
  property var selection: null

  readonly property var outputs: root.request?.outputs ?? []
  // The request's windows, matched as it comes in: a binding would rebuild
  // the grid (its scroll and captures) at each title change
  property var windows: []
  readonly property bool canCaptureOutputs: CompositorManager.supports.outputCapture === true

  onRequestChanged: {
    if (!root.request)
      return;
    root.windows = ScreenShareSources.windowTiles(root.request, CompositorManager.windows);
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
    if (root.tab === "window")
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
  // Gone at once for a region drag, so the screenshot picker's frozen
  // frame doesn't take it in
  visible: shown || (dim.opacity > 0 && !ScreenShareManager.pickingRegion)

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

  // The gap a tile's selection ring leaves around its picture
  readonly property int ring: Widget.px(4)
  readonly property int tileGap: Widget.px(14)
  // A tile's two label lines and the gap above them
  readonly property real labelsHeight: titleMetrics.implicitHeight + subtitleMetrics.implicitHeight + Widget.spacing

  // A screen's width over its height (logical, so rotated screens are tall)
  function aspectOf(output) {
    const s = General.outputs.find(o => o.name === output.name);
    return s && s.width > 0 && s.height > 0 ? s.width / s.height : 16 / 9;
  }
  readonly property var aspects: root.outputs.map(o => root.aspectOf(o))
  // The screens in one row at one height, like the screens stand: as tall
  // as fits the card's width, at most screenMaxHeight
  readonly property int screenMaxHeight: Widget.px(340)
  readonly property real screensWidth: content.width
  readonly property real screenHeightForWidth: {
    const n = root.aspects.length;
    if (n === 0)
      return root.screenMaxHeight;
    const sum = root.aspects.reduce((a, b) => a + b, 0);
    return Math.min(root.screenMaxHeight, (root.screensWidth - root.tileGap * (n - 1) - root.ring * 2 * n) / sum);
  }
  // The body's height for the screens: every tab keeps it, so the card
  // doesn't jump between tabs
  readonly property real bodyHeight: Math.max(Widget.px(300), root.screenHeightForWidth + root.ring * 2 + root.labelsHeight)

  StyledText {
    id: titleMetrics
    visible: false
    text: "Ag"
    textSize: Appearance.fontSizeBy(-1)
    font.weight: Font.DemiBold
  }
  StyledText {
    id: subtitleMetrics
    visible: false
    text: "Ag"
    textSize: Appearance.fontSizeBy(-2)
  }

  // A screen or window tile: its picture in a ring that shows it's picked,
  // its name and a detail under it
  Component {
    id: tileDelegate

    Item {
      id: tile

      required property var modelData
      required property int index
      readonly property bool isScreen: root.tab === "screen"
      readonly property string token: isScreen ? modelData.name : modelData.token
      readonly property bool selected: root.isSelected(root.tab, token)
      readonly property bool hovered: tileMouse.containsMouse
      readonly property var shellScreen: isScreen ? General.outputs.find(s => s.name === tile.modelData.name) ?? null : null
      readonly property real pictureHeight: isScreen ? body.screenHeight : (grid.cellWidth - root.tileGap - root.ring * 2) * 10 / 16

      width: isScreen ? body.screenHeight * root.aspectOf(modelData) + root.ring * 2 : grid.cellWidth
      height: isScreen ? body.height : grid.cellHeight

      Item {
        id: picture
        x: tile.isScreen ? root.ring : root.ring + root.tileGap / 2
        y: root.ring
        width: tile.width - x * 2
        height: tile.pictureHeight

        Rectangle {
          anchors.fill: parent
          anchors.margins: -root.ring
          radius: Widget.radius + root.ring
          color: "transparent"
          border.width: Widget.px(2)
          border.color: tile.selected ? Theme.accent : tile.hovered ? Theme.border : "transparent"

          ColorGlide on border.color {}
        }

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

        // A window: its live capture where there is one, else its icon
        // (its own frame: the ring alone shows hover and the pick)
        WindowPreview {
          visible: !tile.isScreen
          anchors.fill: parent
          radius: Widget.radius
          windowData: tile.isScreen ? null : (tile.modelData.match ?? {
              "id": "",
              "appId": tile.modelData.appId,
              "title": tile.modelData.title
            })
          capturing: !tile.isScreen && root.shown
          live: tile.selected || tile.hovered
          showTitle: false
        }

        // The picked one's check
        Rectangle {
          z: 1
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Widget.spacing
          width: Widget.px(24)
          height: width
          radius: width / 2
          color: Theme.accent
          opacity: tile.selected ? 1 : 0
          scale: tile.selected ? 1 : 0.6

          Glide on opacity {}
          Glide on scale {}

          StyledIcon {
            anchors.centerIn: parent
            text: "check"
            textSize: Appearance.fontSizeBy(-1)
            textColor: Theme.background
          }
        }
      }

      ColumnLayout {
        anchors.top: picture.bottom
        anchors.topMargin: root.ring + Widget.spacing / 2
        x: picture.x
        width: picture.width
        spacing: 0

        StyledText {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-1)
          font.weight: Font.DemiBold
          textColor: tile.selected ? Theme.accent : Theme.foreground
          text: tile.isScreen ? tile.modelData.name : (tile.modelData.title || tile.modelData.appId || tile.modelData.token)

          ColorGlide on textColor {}
        }

        StyledText {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          textSize: Appearance.fontSizeBy(-2)
          textColor: Theme.foregroundInactive
          text: {
            if (!tile.isScreen)
              return tile.modelData.title ? tile.modelData.appId : "";
            const s = tile.shellScreen;
            const size = s ? Math.round(s.width * s.devicePixelRatio) + " × " + Math.round(s.height * s.devicePixelRatio) : "";
            const name = tile.modelData.label || (s?.model ?? "");
            return [size, name].filter(t => t !== "").join("  ·  ");
          }
        }
      }

      MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.select(root.tab, tile.token)
        onDoubleClicked: {
          root.select(root.tab, tile.token);
          root.share();
        }
      }
    }
  }

  Rectangle {
    id: card

    visible: root.hasCard
    anchors.centerIn: parent
    width: Math.min(Widget.px(1040), root.width - Widget.px(48))
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
        spacing: Widget.padding

        Rectangle {
          Layout.preferredWidth: Widget.px(40)
          Layout.preferredHeight: Widget.px(40)
          radius: Widget.radius
          color: Qt.alpha(Theme.accent, 0.16)

          StyledIcon {
            anchors.centerIn: parent
            text: "screen_share"
            textSize: Appearance.fontSizeLarge
            textColor: Theme.accent
          }
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
            text: root.request?.appId ? I18n.tr("{0} asks what to share", root.request.appId) : I18n.tr("Pick what to share")
            textColor: Theme.foregroundInactive
            textSize: Appearance.fontSizeBy(-1)
            elide: Text.ElideRight
          }
        }

        SegmentRow {
          Layout.alignment: Qt.AlignVCenter

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
      }

      Item {
        id: body

        // The screens' height in what the card leaves the body
        readonly property real screenHeight: Math.max(Widget.px(40), Math.min(root.screenHeightForWidth, height - root.ring * 2 - root.labelsHeight))

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: root.bodyHeight
        Layout.minimumHeight: Widget.px(120)

        // Screens: side by side, each its own shape
        Row {
          visible: root.tab === "screen"
          anchors.horizontalCenter: parent.horizontalCenter
          height: parent.height
          spacing: root.tileGap

          Repeater {
            model: root.tab === "screen" ? root.outputs : []
            delegate: tileDelegate
          }
        }

        // Windows: a grid that scrolls
        GridView {
          id: grid

          readonly property int columns: Math.max(2, Math.floor(width / Widget.px(230)))

          visible: root.tab === "window"
          anchors.fill: parent
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          cellWidth: width / columns
          cellHeight: (cellWidth - root.tileGap - root.ring * 2) * 10 / 16 + root.ring * 2 + root.labelsHeight + root.tileGap
          model: root.tab === "window" ? root.windows : []
          delegate: tileDelegate
        }

        StyledText {
          anchors.centerIn: parent
          visible: (root.tab === "screen" && root.outputs.length === 0) || (root.tab === "window" && grid.count === 0)
          text: root.tab === "screen" ? I18n.tr("No screen to share") : I18n.tr("No window to share")
          textColor: Theme.foregroundInactive
        }

        // Region: what happens next
        ColumnLayout {
          visible: root.tab === "region"
          anchors.centerIn: parent
          width: Math.min(parent.width, Widget.px(420))
          spacing: Widget.padding

          Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Widget.px(72)
            Layout.preferredHeight: Widget.px(72)
            radius: Widget.radius
            color: Qt.alpha(Theme.accent, 0.12)
            border.width: Widget.px(2)
            border.color: Qt.alpha(Theme.accent, 0.5)

            StyledIcon {
              anchors.centerIn: parent
              text: "screenshot_region"
              textSize: Appearance.fontSizeBy(14)
              textColor: Theme.accent
            }
          }

          StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: I18n.tr("Share a part of a screen: drag a rectangle over it. Escape there comes back here.")
            textColor: Theme.foregroundInactive
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        Flow {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
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
