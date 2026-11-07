pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs.components.methods
import qs.components.reusable
import qs.config
import qs.services.compositor
import qs.services.apps
import qs.services.ui

// One screen's screenshot picker: the screen frozen (one ScreencopyView
// frame, or grim's picture of it where Quickshell can't capture it
// safely: ScreenshotManager.grimFrames), dimmed except for its part of
// what a click or release would capture (ScreenshotManager.picker.selection,
// shared by every screen's picker so it can cross monitors), with the
// window under the cursor highlighted. `region`: drag a region, or click
// for the window under the cursor (the whole screen where there's none),
// Enter for the screen. `window`: click a window. Esc or right-click
// cancels; Shift on release, or E, opens it in the annotator. An
// immediate `screen` capture shows the same frame with nothing over it
// and grabs as soon as it arrives. The capture is cropped from the frame
// at the screen's own resolution; one over several screens is each
// picker's piece, stitched by ScreenshotManager.captureAcross. `record`
// picks the same way (on one screen), but hands the area to
// ScreenshotManager.record instead of a picture; R or the Screenshot /
// Record switch turns a picker into one or the other.
PanelWindow {
  id: root

  readonly property var request: ScreenshotManager.request
  readonly property bool interactive: request?.kind === "region" || request?.kind === "window" || recording
  // Picking an area to record, not a picture
  readonly property bool recording: request?.kind === "record"
  // The save / copy / annotate controls apply
  readonly property bool picture: !ScreenshotManager.forCaller && !recording
  // Can switch between a screenshot and a recording
  readonly property bool canSwitch: !ScreenshotManager.forCaller && ScreenshotManager.hasRecorder
  // Only whole windows: no dragging, and a click off a window does nothing
  readonly property bool windowsOnly: request?.kind === "window"
  readonly property bool focusedScreen: screen?.name === CompositorManager.focusedOutput
  // Buffer pixels per logical pixel
  readonly property real pixelRatio: root._frameSize.width > 0 && root.width > 0 ? root._frameSize.width / root.width : (screen?.devicePixelRatio ?? 1)
  readonly property rect fullRect: Qt.rect(0, 0, root.width, root.height)

  property bool grabbing: false
  // The frame is in (SurfaceManager.captureFrozen)
  readonly property bool frozen: ScreenshotManager.grimFrames ? still.status === Image.Ready : frame.hasContent
  // What the frozen frame is drawn by, and its size in buffer pixels
  readonly property Item _frameItem: ScreenshotManager.grimFrames ? still : frame
  readonly property size _frameSize: ScreenshotManager.grimFrames ? still.sourceSize : frame.sourceSize

  // This screen in global logical pixels
  readonly property var _box: ({
      "name": root.screen?.name ?? "",
      "x": root.screen?.x ?? 0,
      "y": root.screen?.y ?? 0,
      "width": root.width,
      "height": root.height
    })
  // A drag or a window marks the selection
  readonly property bool marked: ScreenshotManager.picker.dragging || ScreenshotManager.picker.hoveredWindow !== null
  // This screen's part of what a release would capture (local), else the
  // screen (a click takes it), or nothing for `window`
  readonly property rect selection: {
    const global = ScreenshotManager.picker.selection;
    if (global) {
      const part = ScreenRegion.local(global, root._box);
      return Qt.rect(part.x, part.y, part.width, part.height);
    }
    return root.windowsOnly ? Qt.rect(0, 0, 0, 0) : root.fullRect;
  }
  // The pointer is here: the size label shows on this screen
  readonly property bool hasPointer: ScreenshotManager.picker.pointerScreen === root._box.name

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "axiom-screenshot"
  WlrLayershell.keyboardFocus: root.interactive && root.focusedScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  // Crops `area` (local logical pixels) out of the frame and hands it over
  function capture(area) {
    if (root.grabbing)
      return;
    const rect = Qt.rect(Math.round(area.x), Math.round(area.y), Math.round(area.width), Math.round(area.height));
    if (rect.width < 1 || rect.height < 1) {
      ScreenshotManager.cancel();
      return;
    }
    if (ScreenshotManager.forArea) {
      ScreenshotManager.finishArea(root.screen.name, rect);
      return;
    }
    if (root.recording) {
      const whole = rect.x === 0 && rect.y === 0 && rect.width === Math.round(root.width) && rect.height === Math.round(root.height);
      ScreenshotManager.record(Qt.rect(rect.x + root.screen.x, rect.y + root.screen.y, rect.width, rect.height), whole ? root.screen.name : "");
      return;
    }
    root._grab(rect, result => ScreenshotManager.finish(result));
  }

  // A pointer position here, in global pixels: a drag goes on past this
  // screen's edge (the compositor keeps sending the pointer here), into
  // the shared selection
  function _toGlobal(mouse) {
    return Qt.point(mouse.x + root._box.x, mouse.y + root._box.y);
  }

  // What a release or click takes (global): over several screens, each
  // one's piece (ScreenshotManager.captureAcross), else this screen's part
  function captureGlobal(area) {
    if (!ScreenshotManager.picker.oneScreen && ScreenRegion.covered(area, ScreenshotManager.picker.screenBoxes()).length > 1) {
      ScreenshotManager.captureAcross(area);
      return;
    }
    const part = ScreenRegion.local(area, root._box);
    root.capture(Qt.rect(part.x, part.y, part.width, part.height));
  }

  // Grabs `rect` (local, whole pixels) of the frame at the buffer's
  // resolution: done(grabToImage result, or null)
  function _grab(rect, done) {
    root.grabbing = true;
    const size = Qt.size(Math.round(rect.width * root.pixelRatio), Math.round(rect.height * root.pixelRatio));
    cropper.width = rect.width;
    cropper.height = rect.height;
    crop.sourceRect = rect;
    crop.textureSize = size;
    if (!cropper.grabToImage(result => done(result), size))
      done(null);
  }

  // This screen's piece of a capture across screens
  Connections {
    target: ScreenshotManager

    function onPieceRequestChanged() {
      const request = ScreenshotManager.pieceRequest;
      const piece = request?.pieces.find(p => p.screen === root._box.name);
      if (!piece || root.grabbing)
        return;
      const part = ScreenRegion.local(piece.rect, root._box);
      const name = root._box.name;
      root._grab(Qt.rect(Math.round(part.x), Math.round(part.y), Math.round(part.width), Math.round(part.height)), result => ScreenshotManager.pieceDone(request.stamp, name, result));
    }
  }

  // The frame arrives once; an immediate capture takes it straight away.
  // On `frozen` itself: a handler on the Image's status or the view's
  // hasContent runs before this binding updates, and saw it still false
  onFrozenChanged: root._onFrame()
  function _onFrame() {
    if (!root.frozen)
      return;
    ScreenshotManager.frameArrived();
    if (root.interactive || root.request?.screen !== root.screen?.name)
      return;
    // After the frame's first render, so the crop has something to sample
    Qt.callLater(() => root.capture(root.fullRect));
  }

  Component.onCompleted: SurfaceManager.captureWindows = SurfaceManager.captureWindows.concat([root])

  Component.onDestruction: SurfaceManager.captureWindows = SurfaceManager.captureWindows.filter(w => w !== root)

  // Under the frame (never seen), rendered only for the grab
  Item {
    id: cropper
    z: -1

    ShaderEffectSource {
      id: crop
      anchors.fill: parent
      sourceItem: root._frameItem
      hideSource: false
      smooth: true
    }
  }

  ScreencopyView {
    id: frame
    anchors.fill: parent
    captureSource: ScreenshotManager.grimFrames ? null : root.screen
    live: false
    paintCursor: false
  }

  // grim's picture of the screen, taken before the picker opened
  Image {
    id: still
    anchors.fill: parent
    visible: ScreenshotManager.grimFrames
    readonly property string path: ScreenshotManager.grimFrames ? (ScreenshotManager.frames[root.screen?.name ?? ""] ?? "") : ""
    source: still.path === "" ? "" : "file://" + still.path
    asynchronous: true
    cache: false
    smooth: true
    // A picture grim wrote but that can't be read fails at once, not
    // after the watchdog
    onStatusChanged: {
      if (still.status === Image.Error)
        ScreenshotManager.fail(I18n.tr("Couldn't read grim's picture of the screen."));
    }
  }

  Item {
    id: chrome
    anchors.fill: parent
    visible: root.interactive && root.frozen && !root.grabbing
    focus: true

    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape)
        ScreenshotManager.cancel();
      else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !root.windowsOnly)
        root.capture(root.fullRect);
      else if (event.key === Qt.Key_C && root.picture)
        ScreenshotManager.setCopyOnly(!ScreenshotManager.copyOnly);
      else if (event.key === Qt.Key_R && root.canSwitch)
        ScreenshotManager.setRecordMode(!root.recording);
      else if (event.key === Qt.Key_E && ScreenshotManager.annotator !== "" && root.picture)
        ScreenshotManager.annotate = !ScreenshotManager.annotate;
      else
        return;
      event.accepted = true;
    }

    // Dim everything but the selection
    Repeater {
      model: [Qt.rect(0, 0, root.width, root.selection.y), Qt.rect(0, root.selection.y + root.selection.height, root.width, root.height - root.selection.y - root.selection.height), Qt.rect(0, root.selection.y, root.selection.x, root.selection.height), Qt.rect(root.selection.x + root.selection.width, root.selection.y, root.width - root.selection.x - root.selection.width, root.selection.height)]

      Rectangle {
        required property rect modelData
        x: modelData.x
        y: modelData.y
        width: Math.max(0, modelData.width)
        height: Math.max(0, modelData.height)
        color: Qt.rgba(0, 0, 0, 0.45)
      }
    }

    Rectangle {
      x: root.selection.x
      y: root.selection.y
      width: root.selection.width
      height: root.selection.height
      readonly property color tint: root.recording ? Theme.error : Theme.accent
      color: ScreenshotManager.picker.dragging ? "transparent" : Qt.alpha(tint, 0.12)
      border.color: tint
      border.width: Math.max(2, Appearance.borderWidth)
      visible: root.marked && root.selection.width > 0 && root.selection.height > 0
    }

    // Size in the picture's own pixels
    Rectangle {
      readonly property bool below: root.selection.y + root.selection.height + height + 6 < root.height
      x: Math.min(root.width - width, Math.max(0, root.selection.x))
      y: below ? root.selection.y + root.selection.height + Widget.smallPadding : Math.max(0, root.selection.y - height - Widget.smallPadding)
      width: sizeText.implicitWidth + Widget.smallPadding * 2
      height: sizeText.implicitHeight + Widget.smallPadding
      radius: Appearance.borderRadius / 2
      color: Theme.background
      visible: root.marked && root.hasPointer && root.selection.width > 0 && root.selection.height > 0
      // The whole selection's, over every screen it's on
      readonly property size pixels: ScreenshotManager.picker.selection ? ScreenshotManager.picker.pixelSize(ScreenshotManager.picker.selection) : Qt.size(0, 0)

      StyledText {
        id: sizeText
        anchors.centerIn: parent
        text: `${parent.pixels.width} × ${parent.pixels.height}`
        textSize: Appearance.fontSizeBy(-3)
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      cursorShape: Qt.CrossCursor

      onPositionChanged: mouse => {
        if (pressed && (mouse.buttons & Qt.LeftButton) && !root.windowsOnly)
          ScreenshotManager.picker.dragTo(root._toGlobal(mouse));
        else
          ScreenshotManager.picker.hover(root._box.name, root._toGlobal(mouse));
      }
      onPressed: mouse => {
        if (mouse.button === Qt.RightButton) {
          ScreenshotManager.cancel();
          return;
        }
        ScreenshotManager.picker.press(root._box.name, root._toGlobal(mouse));
      }
      onReleased: mouse => {
        if (mouse.button !== Qt.LeftButton)
          return;
        if (mouse.modifiers & Qt.ShiftModifier && ScreenshotManager.annotator !== "" && root.picture)
          ScreenshotManager.annotate = true;
        // null: no drag and no window under the pointer
        const area = ScreenshotManager.picker.release();
        if (area && !ScreenRegion.isEmpty(area))
          root.captureGlobal(area);
        else if (!area && !root.windowsOnly)
          root.capture(root.fullRect);
      }
    }

    // Controls, out of the way while dragging: what a pick does (a
    // screenshot or a recording; for a screenshot, save or only copy, and
    // whether it opens in the annotator), then the keys
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Widget.px(40)
      width: controls.implicitWidth + Widget.px(24)
      height: controls.implicitHeight + Widget.px(16)
      radius: Appearance.borderRadius
      color: Theme.background
      border.color: Theme.border
      border.width: Appearance.borderWidth
      visible: root.focusedScreen && !ScreenshotManager.picker.dragging

      // Clicks between the buttons aren't captures
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
      }

      Column {
        id: controls
        anchors.centerIn: parent
        spacing: Widget.spacing

        RowLayout {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.canSwitch || root.picture
          spacing: Widget.spacing * 3

          SegmentRow {
            visible: root.canSwitch

            SegmentButton {
              Layout.fillWidth: false
              iconText: "screenshot_region"
              text: I18n.tr("Screenshot")
              active: !root.recording
              onClicked: ScreenshotManager.setRecordMode(false)
            }

            SegmentButton {
              Layout.fillWidth: false
              iconText: "radio_button_checked"
              text: I18n.tr("Record")
              active: root.recording
              onClicked: ScreenshotManager.setRecordMode(true)
            }
          }

          SegmentRow {
            visible: root.picture

            SegmentButton {
              Layout.fillWidth: false
              iconText: "save"
              text: I18n.tr("Save and copy")
              active: !ScreenshotManager.copyOnly
              onClicked: ScreenshotManager.setCopyOnly(false)
            }

            SegmentButton {
              Layout.fillWidth: false
              iconText: "content_copy"
              text: I18n.tr("Copy only")
              active: ScreenshotManager.copyOnly
              onClicked: ScreenshotManager.setCopyOnly(true)
            }
          }

          // A switch: on, the capture opens in the annotator instead of
          // being notified
          SegmentButton {
            Layout.fillWidth: false
            visible: root.picture && ScreenshotManager.annotator !== ""
            iconText: ScreenshotManager.annotate ? "check_box" : "check_box_outline_blank"
            text: I18n.tr("Edit in {0}", ScreenshotManager.annotatorName)
            active: ScreenshotManager.annotate
            onClicked: ScreenshotManager.annotate = !ScreenshotManager.annotate
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Widget.spacing * 2

          KeyHint {
            visible: !root.windowsOnly
            key: I18n.tr("Drag")
            label: I18n.tr("region")
          }

          KeyHint {
            key: I18n.tr("Click")
            label: root.windowsOnly ? I18n.tr("window") : I18n.tr("window (screen off a window)")
          }

          KeyHint {
            visible: !ScreenshotManager.forCaller && !root.windowsOnly
            key: "↵"
            label: I18n.tr("screen")
          }

          KeyHint {
            visible: root.canSwitch
            key: "R"
            label: root.recording ? I18n.tr("screenshot") : I18n.tr("record")
          }

          KeyHint {
            visible: root.picture
            key: "C"
            label: I18n.tr("copy only")
          }

          KeyHint {
            visible: ScreenshotManager.annotator !== "" && root.picture
            key: "E"
            label: I18n.tr("edit in {0}", ScreenshotManager.annotatorName)
          }

          KeyHint {
            key: "Esc"
            label: I18n.tr("cancel")
          }
        }
      }
    }
  }
}
