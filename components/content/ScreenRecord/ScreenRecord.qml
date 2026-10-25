pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.services.system
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Screen recording (ScreenshotManager, with wf-recorder): record a region
// (picked as for a screenshot) or the whole focused screen (the overlay
// closes first), with the system's sound (with pactl), the microphone or
// none; while recording, a stop button and the time so far. The newest
// recordings in the recording folder (the Screenshots section) are listed
// under it when there's room: click to open, copy the path or move one to
// the trash. Also the ScreenRecord widget's popout.
// A short card is one row; compact, a figure that starts or stops it.
Panel {
  id: root

  readonly property bool recording: ScreenshotManager.recording
  readonly property bool missing: DependencyManager.found["wf-recorder"] === false
  readonly property string elapsed: root.durationText(ScreenshotManager.recordingElapsed)
  readonly property var recordings: ScreenshotManager.recordings
  // The sound recorded with: the system's only with pactl
  readonly property bool systemAudio: ScreenshotManager.hasSystemAudio !== false
  readonly property string audio: ScreenshotManager.recordAudio === "system" && !root.systemAudio ? "none" : ScreenshotManager.recordAudio

  // One row: the state and its buttons
  readonly property bool strip: root.embedded && root.innerHeight < Appearance.fontSize * 7
  readonly property bool showHeader: !root.embedded || root.innerHeight >= Appearance.fontSize * 12
  readonly property bool showAudio: !root.strip && (!root.embedded || root.innerHeight >= Appearance.fontSize * 9.5)
  readonly property bool showList: !root.strip && (!root.embedded || root.innerHeight >= Appearance.fontSize * 15 || (root.sideBySide && root.innerHeight >= Appearance.fontSize * 9))
  // The list beside the controls in a wide card
  readonly property bool sideBySide: root.embedded && root.innerWidth >= Appearance.fontSize * 34 && root.innerWidth >= root.innerHeight * 1.4

  implicitWidth: Widget.px(360)
  fullMinWidth: Appearance.fontSize * 10
  fullMinHeight: Appearance.fontSize * 3.5
  spacing: Widget.spacing
  wantedHeight: root.compact || root.strip ? 0 : root.height > 0 && root.showList ? root.height + list.contentHeight - list.height : 0

  // "1:05", "1:02:03"
  function durationText(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor(seconds / 60) % 60;
    const sec = String(seconds % 60).padStart(2, "0");
    return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
  }

  function start(mode) {
    if (mode === "screen")
      ShellManager.closeOverlay();
    ScreenshotManager.startRecording({
      "mode": mode,
      "audio": root.audio
    });
  }

  function toggle() {
    if (root.recording)
      ScreenshotManager.stopRecording();
    else
      root.start("pick");
  }

  Component.onCompleted: {
    DependencyManager.check(["wf-recorder", "pactl"]);
    ScreenshotManager.refreshRecordings();
  }

  compactContent: Item {
    CompactFigure {
      anchors.fill: parent
      icon: root.recording ? "stop_circle" : "screen_record"
      iconColor: root.recording ? Theme.error : Theme.accent
      value: root.recording ? root.elapsed : ""
      label: root.recording ? I18n.tr("Recording") : I18n.tr("Record")
      valueColor: Theme.error
    }
    TapHandler {
      enabled: !root.missing
      onTapped: root.toggle()
    }
    HoverHandler {
      cursorShape: root.missing ? Qt.ArrowCursor : Qt.PointingHandCursor
    }
  }

  // A dot that pulses while recording
  component RecordingDot: Rectangle {
    id: dot
    implicitWidth: Appearance.fontSize * 0.7
    implicitHeight: implicitWidth
    radius: width / 2
    color: Theme.error

    SequentialAnimation on opacity {
      running: root.recording && Appearance.animations
      loops: Animation.Infinite
      onRunningChanged: {
        if (!running)
          dot.opacity = 1;
      }
      NumberAnimation {
        to: 0.25
        duration: Appearance.animSlow * 2
        easing.type: Appearance.easing
      }
      NumberAnimation {
        to: 1
        duration: Appearance.animSlow * 2
        easing.type: Appearance.easing
      }
    }
  }

  ModuleHeader {
    visible: root.showHeader && !root.missing
    icon: "screen_record"
    iconColor: root.recording ? Theme.error : Theme.accent
    title: I18n.tr("Screen recording")
    StyledText {
      visible: root.recording
      text: root.elapsed
      textColor: Theme.error
      font.bold: true
      font.features: {
        "tnum": 1
      }
    }
  }

  Item {
    visible: root.missing
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredHeight: root.embedded ? -1 : Appearance.fontSize * 6
    EmptyState {
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: parent.height
      icon: "videocam_off"
      text: I18n.tr("Recording needs wf-recorder")
    }
  }

  // A short card: the state and its buttons in a row
  RowLayout {
    visible: root.strip && !root.missing
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Widget.spacing

    RecordingDot {
      visible: root.recording
    }
    StyledIcon {
      visible: !root.recording
      text: "screen_record"
      textColor: Theme.accent
      textSize: Appearance.fontSizeBy(2)
    }
    StyledText {
      Layout.fillWidth: true
      text: root.recording ? I18n.tr("Recording · {0}", root.elapsed) : I18n.tr("Screen recording")
      textColor: root.recording ? Theme.error : Theme.foreground
      elide: Text.ElideRight
    }
    FlatIconButton {
      visible: !root.recording
      size: Widget.iconButton
      iconText: "screenshot_region"
      tooltipText: I18n.tr("Record a region")
      onClicked: root.start("pick")
    }
    FlatIconButton {
      visible: !root.recording
      size: Widget.iconButton
      iconText: "screenshot_monitor"
      tooltipText: I18n.tr("Record the screen")
      onClicked: root.start("screen")
    }
    FlatIconButton {
      visible: root.recording
      size: Widget.iconButton
      iconText: "stop"
      iconColor: Theme.error
      tooltipText: I18n.tr("Stop")
      onClicked: ScreenshotManager.stopRecording()
    }
  }

  GridLayout {
    visible: !root.strip && !root.missing
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    columns: root.sideBySide ? 2 : 1
    columnSpacing: root.pad
    rowSpacing: Widget.spacing

    // Start (region or screen) or stop, and the sound
    ColumnLayout {
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.fillHeight: root.embedded && !root.showList || root.sideBySide
      Layout.alignment: Qt.AlignTop
      spacing: Widget.spacing

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: root.embedded && (!root.showList || root.sideBySide)
        Layout.preferredHeight: root.embedded ? Math.max(Appearance.fontSize * 5, Math.min(Appearance.fontSize * 8, root.innerHeight * 0.3)) : Appearance.fontSize * 5
        Layout.maximumHeight: Appearance.fontSize * 8
        spacing: Widget.spacing

        ActionTile {
          visible: !root.recording
          Layout.fillWidth: true
          Layout.fillHeight: true
          icon: "screenshot_region"
          label: I18n.tr("Region")
          onClicked: root.start("pick")
        }
        ActionTile {
          visible: !root.recording
          Layout.fillWidth: true
          Layout.fillHeight: true
          icon: "screenshot_monitor"
          label: I18n.tr("Screen")
          onClicked: root.start("screen")
        }
        // Recording: the time so far, and stop
        ActionTile {
          visible: root.recording
          Layout.fillWidth: true
          Layout.fillHeight: true
          icon: "stop"
          label: I18n.tr("Stop · {0}", root.elapsed)
          active: true
          activeColor: Theme.error
          onClicked: ScreenshotManager.stopRecording()
        }
      }

      SegmentRow {
        visible: root.showAudio
        Layout.fillWidth: true
        enabled: !root.recording
        opacity: root.recording ? 0.5 : 1

        Repeater {
          // Short names where it's narrow.
          // I18n.tr("No sound") I18n.tr("System") I18n.tr("Microphone") I18n.tr("Mute") I18n.tr("Mic")
          model: [
            {
              "audio": "none",
              "label": "No sound",
              "short": "Mute"
            },
            {
              "audio": "system",
              "label": "System",
              "short": "System"
            },
            {
              "audio": "mic",
              "label": "Microphone",
              "short": "Mic"
            }
          ]

          SegmentButton {
            required property var modelData
            // The system's sound needs pactl
            available: modelData.audio !== "system" || root.systemAudio
            Layout.fillWidth: true
            text: I18n.tr((root.sideBySide ? root.innerWidth / 2 : root.innerWidth) < Appearance.fontSize * 18 ? modelData.short : modelData.label)
            active: root.audio === modelData.audio
            onClicked: ScreenshotManager.setRecordAudio(modelData.audio)
          }
        }
      }
    }

    // The newest recordings in the folder
    ColumnLayout {
      visible: root.showList
      Layout.fillWidth: true
      Layout.preferredWidth: 1
      Layout.fillHeight: root.embedded
      Layout.preferredHeight: root.embedded ? -1 : Math.min(list.contentHeight, Appearance.fontSize * 14) + listTitle.implicitHeight
      spacing: Widget.spacing / 2

      RowLayout {
        id: listTitle
        Layout.fillWidth: true
        StyledText {
          Layout.fillWidth: true
          text: I18n.tr("Recent recordings")
          textSize: Appearance.fontSizeBy(-2)
          textColor: Theme.foregroundAlt
          font.bold: true
          elide: Text.ElideRight
        }
        FlatIconButton {
          size: Widget.smallHeight
          iconText: "folder_open"
          tooltipText: I18n.tr("Open the folder")
          onClicked: Qt.openUrlExternally("file://" + ScreenshotManager.recordingFolder)
        }
      }

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.recordings.length

        delegate: ItemRow {
          id: row
          required property int index
          readonly property var recording: root.recordings[index] ?? ({
              "path": "",
              "name": "",
              "time": 0,
              "size": 0
            })
          width: ListView.view.width
          icon: "movie"
          title: row.recording.time > 0 ? I18n.formatDate(new Date(row.recording.time), I18n.dateFormat("shortDate")) + " · " + I18n.formatDate(new Date(row.recording.time), I18n.dateFormat("time24")) : row.recording.name
          subtitle: Utils.formatBytes(row.recording.size)
          onActivated: Qt.openUrlExternally("file://" + row.recording.path)

          FlatIconButton {
            size: Widget.iconButton
            iconText: "content_copy"
            tooltipText: I18n.tr("Copy the path")
            onClicked: ClipboardManager.copyText(row.recording.path)
          }
          FlatIconButton {
            size: Widget.iconButton
            iconText: "delete"
            tooltipText: I18n.tr("Move to the trash")
            onClicked: ScreenshotManager.deleteRecording(row.recording.path)
          }
        }

        EmptyState {
          visible: root.recordings.length === 0
          anchors.centerIn: parent
          maxWidth: parent.width
          availableHeight: parent.height
          icon: "movie"
          text: I18n.tr("No recordings yet")
        }
      }
    }
  }
}
