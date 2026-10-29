pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.services.system
import qs.config
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// Volume mixer: the default device on top, then an Applications tab
// (per-app volume, one row per app however many streams it has) and a
// Devices tab (pick the default, adjust each device). As the Volume
// ("output") and Microphone ("input") widgets' popout, or an overlay card
// with its own output/input switch (a wide card puts the device beside
// the list; a short one is just the device's slider; compact, its figure).
// properties: { mode: "output" | "input" }
Panel {
  id: root

  // A card's configured mode; a popout sets it from its anchor's payload
  property string mode: root.properties.mode ?? "output"
  property real maxVolume: 1.0

  property int currentTab: 0

  readonly property bool isInput: mode === "input"
  readonly property var defaultDevice: isInput ? AudioManager.defaultSource : AudioManager.defaultSink
  readonly property var apps: isInput ? AudioManager.recordingApps : AudioManager.playbackApps
  readonly property var devices: isInput ? AudioManager.sources : AudioManager.sinks
  readonly property string mutedGlyph: isInput ? "mic_off" : "volume_off"
  readonly property string unmutedGlyph: isInput ? "mic" : "volume_up"
  // A wide card puts the default device beside the tabs and list
  readonly property bool sideBySide: root.embedded && !root.sliderOnly && root.shape === "horizontal" && root.innerWidth >= Appearance.fontSize * 40
  // A short card: the default device's slider alone
  readonly property bool sliderOnly: root.embedded && root.height < Appearance.fontSize * 13
  // Each side's width in a horizontal card (from the card's size, not the
  // grid's, which depends on it)
  readonly property real sideWidth: (root.innerWidth - Appearance.borderWidth - root.pad * 2) / 2

  // A popout's list is as high as its rows, from two (also when empty) to
  // four, then it scrolls: the popout grows away from its controls, which
  // stay by the bar (Panel.growth: growing up, they go below the list)
  function rowsHeight(rows) {
    return defaultRow.implicitHeight * rows + list.spacing * (rows - 1);
  }
  readonly property real listHeight: root.rowsHeight(4) // fixed px: a row count, not a size
  readonly property real shownListHeight: Math.max(root.rowsHeight(2), Math.min(list.implicitHeight, root.listHeight))
  maxImplicitHeight: root.embedded ? 0 : root.implicitHeight + root.listHeight - scroll.height

  implicitWidth: Widget.px(380)
  fullMinWidth: Appearance.fontSize * 12
  // Grows to list every app or device (a short card stays the slider)
  wantedHeight: root.sliderOnly || scroll.height <= 0 ? 0 : root.height + list.implicitHeight - scroll.height
  fullMinHeight: Appearance.fontSize * 3.5

  function deviceName(node) {
    return node?.description || node?.nickname || node?.name || I18n.tr("No device");
  }
  function deviceIcon(node, muted, level) {
    const kind = AudioManager.deviceKind(node);
    return isInput ? AudioManager.inputIcon(kind, muted) : AudioManager.outputIcon(kind, muted, level);
  }

  onCurrentTabChanged: fadeIn.restart()

  // Compact: the default device's volume; click to mute
  compactContent: Item {
    readonly property var node: root.defaultDevice
    readonly property bool muted: node?.audio?.muted ?? false
    CompactFigure {
      anchors.fill: parent
      icon: parent.muted ? root.mutedGlyph : root.unmutedGlyph
      iconColor: parent.muted ? Theme.foregroundAlt : Theme.accent
      value: String(Math.round((parent.node?.audio?.volume ?? 0) * 100))
      unit: "%"
      label: I18n.tr(root.isInput ? "Input" : "Output")
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: AudioManager.toggleNodeMute(parent.node)
    }
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    columns: root.sideBySide ? 3 : 1
    columnSpacing: root.pad
    rowSpacing: Widget.spacing

    ColumnLayout {
      Layout.row: root.growsUp ? 2 : 0
      Layout.column: 0
      Layout.fillWidth: true
      Layout.preferredWidth: root.sideBySide ? root.sideWidth : -1
      Layout.alignment: root.sliderOnly ? Qt.AlignVCenter : Qt.AlignTop
      spacing: Widget.spacing

      StyledText {
        visible: !root.embedded
        text: I18n.tr(root.isInput ? "Input" : "Output")
        font.bold: true
        textColor: Theme.accent
      }

      // A card switches between output and input itself, from its header
      ModuleHeader {
        visible: root.embedded && !root.sliderOnly
        icon: root.unmutedGlyph
        title: I18n.tr(root.isInput ? "Input" : "Output")
        Repeater {
          model: [["output", "volume_up", I18n.tr("Output")], ["input", "mic", I18n.tr("Input")]]
          StyledRectButton {
            required property var modelData
            readonly property bool selected: root.mode === modelData[0]
            iconText: modelData[1]
            iconColor: selected ? Theme.accent : Theme.foregroundAlt
            backgroundColor: Qt.alpha(Theme.backgroundHighlight, selected ? 1 : 0)
            borderHoverColor: Theme.accent
            tooltipText: modelData[2]
            onClicked: root.mode = modelData[0]
          }
        }
      }

      // Default device, visible on both tabs; a short card's opens the
      // whole mixer
      RowLayout {
        Layout.fillWidth: true
        spacing: 0

        AudioRow {
          id: defaultRow
          readonly property var node: root.defaultDevice
          icon: root.deviceIcon(node, muted, volume)
          title: root.deviceName(node)
          volume: node?.audio?.volume ?? 0
          muted: node?.audio?.muted ?? false
          maxVolume: root.maxVolume
          mutedGlyph: root.mutedGlyph
          unmutedGlyph: root.unmutedGlyph
          onVolumeMoved: value => AudioManager.setNodeVolume(node, value, root.maxVolume)
          onMuteToggled: AudioManager.toggleNodeMute(node)
        }

        ExpandButton {
          module: root
          type: root.sliderOnly ? "AudioMixer" : ""
          properties: ({
              "mode": root.mode
            })
        }
      }
    }

    StyledSeparator {
      visible: !root.sliderOnly
      Layout.row: root.sideBySide ? 0 : 1
      Layout.column: root.sideBySide ? 1 : 0
      Layout.fillWidth: !root.sideBySide
      Layout.fillHeight: root.sideBySide
      Layout.preferredWidth: root.sideBySide ? Appearance.borderWidth : -1
      Layout.preferredHeight: root.sideBySide ? -1 : Appearance.borderWidth
      separatorColor: Theme.backgroundHighlight
    }

    GridLayout {
      visible: !root.sliderOnly
      Layout.row: root.sideBySide || root.growsUp ? 0 : 2
      Layout.column: root.sideBySide ? 2 : 0
      Layout.fillWidth: true
      Layout.fillHeight: root.embedded
      Layout.preferredWidth: root.sideBySide ? root.sideWidth : -1
      columns: 1
      rowSpacing: Widget.spacing

      StyledTabBar {
        Layout.row: root.growsUp ? 1 : 0
        Layout.column: 0
        tabs: [I18n.tr("Applications ({0})", root.apps.length), I18n.tr("Devices")]
        currentIndex: root.currentTab
        onTabClicked: index => root.currentTab = index
      }

      StyledScrollView {
        id: scroll
        Layout.row: root.growsUp ? 0 : 1
        Layout.column: 0
        Layout.fillWidth: true
        Layout.preferredHeight: root.embedded ? -1 : root.shownListHeight
        Layout.fillHeight: root.embedded
        contentPadding: 0
        showScrollBar: list.implicitHeight > scroll.height

        ColumnLayout {
          id: list
          width: scroll.availableWidth
          spacing: 2

          NumberAnimation on opacity {
            id: fadeIn
            from: 0
            to: 1
            duration: Appearance.animNormal
          }

          // Applications. Modelled by count, so a row survives its app's
          // streams changing (a new track renames it) instead of being rebuilt
          // under the pointer, mid-drag
          Repeater {
            model: root.currentTab === 0 ? root.apps.length : 0

            AudioRow {
              id: appRow
              required property int index
              readonly property var app: root.apps[index] ?? null
              readonly property var node: app?.nodes[0] ?? null
              icon: root.unmutedGlyph
              iconSource: app?.icon ? Quickshell.iconPath(app.icon, true) : ""
              title: app?.name ?? ""
              subtitle: app?.subtitle ?? ""
              volume: node?.audio?.volume ?? 0
              muted: node?.audio?.muted ?? false
              maxVolume: root.maxVolume
              mutedGlyph: root.mutedGlyph
              unmutedGlyph: root.unmutedGlyph
              onVolumeMoved: value => AudioManager.setNodesVolume(appRow.app?.nodes, value, root.maxVolume)
              onMuteToggled: AudioManager.setNodesMuted(appRow.app?.nodes, !appRow.muted)
            }
          }

          // An empty list says so in the middle of the view (a popout's
          // two rows)
          StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: root.embedded ? scroll.availableHeight : root.rowsHeight(2)
            visible: root.currentTab === 0 ? root.apps.length === 0 : root.devices.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            text: root.currentTab === 1 ? I18n.tr("No devices found") : I18n.tr(root.isInput ? "No apps recording" : "No apps playing audio")
            textColor: Theme.foregroundAlt
          }

          // Devices: click one to make it the default (whose volume is above)
          Repeater {
            model: root.currentTab === 1 ? root.devices.length : 0

            Rectangle {
              id: deviceRow
              required property int index
              readonly property var node: root.devices[index] ?? null
              readonly property bool selected: node !== null && node === root.defaultDevice

              Layout.fillWidth: true
              implicitHeight: deviceLayout.implicitHeight + Widget.spacing * 2
              radius: Widget.radius
              color: selected ? Theme.backgroundHighlight : deviceMouse.containsMouse ? Qt.alpha(Theme.backgroundHighlight, 0.5) : Qt.alpha(Theme.backgroundHighlight, 0)

              ColorGlide on color {}

              MouseArea {
                id: deviceMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: deviceRow.selected ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: AudioManager.setDefault(deviceRow.node)
              }

              RowLayout {
                id: deviceLayout
                anchors.fill: parent
                anchors.margins: Widget.spacing
                anchors.leftMargin: Widget.padding
                anchors.rightMargin: Widget.padding
                spacing: Widget.padding

                StyledIcon {
                  Layout.preferredWidth: Widget.iconButton
                  horizontalAlignment: Text.AlignHCenter
                  text: root.deviceIcon(deviceRow.node, false, 1)
                  textSize: Appearance.fontSize * 1.2
                  textColor: deviceRow.selected ? Theme.accent : Theme.foregroundAlt
                }

                StyledText {
                  Layout.fillWidth: true
                  text: root.deviceName(deviceRow.node)
                  elide: Text.ElideRight
                  textSize: Appearance.fontSizeBy(-1)
                  textColor: deviceRow.selected ? Theme.foreground : Theme.foregroundAlt
                }

                // Always laid out, so selecting a row doesn't reflow it
                StyledIcon {
                  opacity: deviceRow.selected ? 1 : 0
                  text: "check"
                  textColor: Theme.accent
                }
              }
            }
          }
        }
      }
    }
  }
}
