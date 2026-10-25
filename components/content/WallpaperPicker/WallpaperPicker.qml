pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.reusable
import qs.components.forms
import qs.components.content.base
import qs.components.content.parts

// Wallpapers from Appearance.wallpaperFolder as a scrolling strip (a grid in
// taller slots); clicking one sets it and regenerates the themes from it.
// A tall vertical slot (the Themes page) adds a header and the wallpaper
// mode (WallpaperManager): Fixed and Rotate add a monitor picker and a
// preview of that monitor's wallpaper, and set it on the picked monitor
// instead of this overlay's (Rotate adds its settings and Next); Light/Dark
// shows the two wallpapers, and a click sets the selected one's. Compact,
// just this monitor's wallpaper.
Card {
  id: root

  // This overlay's screen
  readonly property string monitor: root.QsWindow.window?.screen?.name ?? ""

  // Tall enough for the header, mode and preview over the thumbnails;
  // high enough for rows of thumbnails rather than one strip
  readonly property bool tall: root.shape === "vertical" && root.height >= Appearance.fontSize * 42
  readonly property bool grid: root.height >= Appearance.fontSize * 20

  // The picked monitor while it's connected, else this overlay's
  property string chosenMonitor: ""
  readonly property var screenNames: General.outputs.map(screen => screen.name)
  readonly property string targetMonitor: root.tall && root.screenNames.includes(root.chosenMonitor) ? root.chosenMonitor : root.monitor
  readonly property string mode: Appearance.wallpaperMode
  readonly property bool variantMode: root.mode === "variant"
  // The variant a click sets in Light/Dark mode: the current one until
  // another is picked
  property string chosenVariant: ""
  readonly property string variant: root.chosenVariant || (Appearance.darkMode ? "dark" : "light")
  // What a thumbnail is marked current against
  readonly property string wallpaper: root.tall && root.variantMode ? (root.variant === "dark" ? Appearance.darkWallpaper : Appearance.lightWallpaper) : ThemeManager.wallpaperFor(root.targetMonitor)

  // A wallpaper cut to the rounded corners, its border drawn over it;
  // children go on top
  component Thumbnail: Item {
    id: thumbnail
    property alias source: picture.source
    property alias sourceSize: picture.sourceSize
    property color fillColor: Theme.backgroundHighlight
    property color borderColor: "transparent"
    property real borderWidth: 2
    default property alias content: overlay.data

    ClippingRectangle {
      anchors.fill: parent
      radius: Widget.radius
      color: thumbnail.fillColor

      Image {
        id: picture
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: Widget.radius
      color: "transparent"
      border.color: thumbnail.borderColor
      border.width: thumbnail.borderWidth
    }

    Item {
      id: overlay
      anchors.fill: parent
    }
  }

  // Compact: this monitor's wallpaper
  compactContent: Thumbnail {
    source: root.wallpaper
    sourceSize: Qt.size(320, 200)
    borderColor: Theme.border
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    ModuleHeader {
      visible: root.tall
      icon: "wallpaper"
      title: I18n.tr("Wallpaper")

      StyledText {
        visible: ThemeManager.isGenerating
        text: I18n.tr("Generating themes...")
        textColor: Theme.accent
      }

      SquareIconButton {
        visible: root.mode === "rotate"
        iconText: "skip_next"
        tooltipText: I18n.tr("Next wallpaper")
        onClicked: WallpaperManager.next()
      }
    }

    SegmentRow {
      visible: root.tall
      Layout.fillWidth: true

      Repeater {
        // I18n.tr("Fixed") I18n.tr("Rotate") I18n.tr("Light/Dark")
        model: [
          {
            "mode": "fixed",
            "label": "Fixed"
          },
          {
            "mode": "rotate",
            "label": "Rotate"
          },
          {
            "mode": "variant",
            "label": "Light/Dark"
          }
        ]

        delegate: SegmentButton {
          required property var modelData
          text: I18n.tr(modelData.label)
          active: root.mode === modelData.mode
          onClicked: SettingsManager.commitValues({
            "Appearance.wallpaper.mode": modelData.mode
          })
        }
      }
    }

    SettingRows {
      visible: root.tall && root.mode === "rotate"
      Layout.fillWidth: true
      paths: ["Appearance.wallpaper.rotation.interval", "Appearance.wallpaper.rotation.order", "Appearance.wallpaper.rotation.sameOnAll"]
    }

    // Light/Dark: the two wallpapers; the selected one is what a click sets
    RowLayout {
      visible: root.tall && root.variantMode
      Layout.fillWidth: true
      spacing: Widget.spacing

      Repeater {
        // I18n.tr("Dark") I18n.tr("Light")
        model: ["dark", "light"]

        delegate: ColumnLayout {
          id: slot
          required property string modelData
          readonly property string url: slot.modelData === "dark" ? Appearance.darkWallpaper : Appearance.lightWallpaper
          readonly property bool selected: root.variant === slot.modelData
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          spacing: Widget.spacing

          Thumbnail {
            Layout.fillWidth: true
            Layout.preferredHeight: width * 10 / 16
            source: root.variantMode ? slot.url : ""
            sourceSize: Qt.size(320, 200)
            borderColor: slot.selected ? Theme.accent : slotArea.containsMouse ? Theme.foreground : Theme.border
            borderWidth: slot.selected ? 3 : 2

            StyledText {
              anchors.centerIn: parent
              visible: slot.url === ""
              text: I18n.tr("Pick one below")
              opacity: 0.6
            }

            MouseArea {
              id: slotArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.chosenVariant = slot.modelData
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Widget.spacing

            StyledIcon {
              text: slot.modelData === "dark" ? "dark_mode" : "light_mode"
              textColor: slot.selected ? Theme.accent : Theme.foreground
            }

            StyledText {
              Layout.fillWidth: true
              text: I18n.tr(slot.modelData === "dark" ? "Dark" : "Light")
              textColor: slot.selected ? Theme.accent : Theme.foreground
              font.bold: slot.selected
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    SchemaComboBox {
      visible: root.tall && !root.variantMode
      label: I18n.tr("Monitor")
      options: root.screenNames
      currentValue: root.targetMonitor
      optionLabels: root.screenNames.reduce((labels, name) => {
        labels[name] = name === General.primaryMonitor ? I18n.tr("{0} (primary)", name) : name;
        return labels;
      }, {})
      onSelectionChanged: value => root.chosenMonitor = value
    }

    // The picked monitor's wallpaper
    Thumbnail {
      visible: root.tall && !root.variantMode
      Layout.fillWidth: true
      Layout.preferredHeight: width * 10 / 16
      source: root.tall ? root.wallpaper : ""
      sourceSize: Qt.size(640, 400)
      borderColor: Theme.accent

      StyledText {
        anchors.centerIn: parent
        visible: root.wallpaper === ""
        text: I18n.tr("No wallpaper set")
        opacity: 0.6
      }
    }

    StyledText {
      visible: root.tall && !root.variantMode && root.wallpaper !== ""
      Layout.fillWidth: true
      text: root.wallpaper.split("/").pop()
      elide: Text.ElideMiddle
      opacity: 0.7
    }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      StyledText {
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: ThemeManager.wallpaperModel.count === 0
        text: I18n.tr("No wallpapers in {0}", Appearance.wallpaperFolder)
        opacity: 0.6
      }

      GridView {
        id: view
        anchors.fill: parent
        clip: true
        flow: root.grid ? GridView.FlowLeftToRight : GridView.FlowTopToBottom
        readonly property real thumbHeight: root.tall ? cellWidth * 10 / 16 : root.grid ? height / Math.max(1, Math.floor(height / 140)) : height
        cellHeight: thumbHeight
        // Two across in the tall layout
        cellWidth: root.tall ? width / 2 : thumbHeight * 16 / 10
        model: ThemeManager.wallpaperModel

        delegate: Item {
          id: thumb
          required property url fileUrl
          required property string filePath
          readonly property bool current: root.wallpaper !== "" && thumb.filePath.endsWith(root.wallpaper.replace("file://", ""))
          width: view.cellWidth
          height: view.cellHeight

          Thumbnail {
            anchors.fill: parent
            anchors.margins: Widget.spacing / 2
            source: thumb.fileUrl
            sourceSize: Qt.size(320, 200)
            fillColor: Theme.backgroundAlt
            borderColor: thumb.current ? Theme.accent : thumbArea.containsMouse ? Theme.foreground : "transparent"
            borderWidth: thumb.current ? 3 : 2
          }

          MouseArea {
            id: thumbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: WallpaperManager.pick(thumb.fileUrl.toString(), root.targetMonitor, root.tall ? root.variant : "")
          }
        }
      }
    }
  }
}
