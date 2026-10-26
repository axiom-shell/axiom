pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.forms
import qs.components.content.ThemePicker
import qs.components.content.WallpaperPicker

// The look: the wallpaper folder, bar style and screen border here, with the Themes
// page's wallpaper picker and theme list beside it
OnboardingPage {
  id: root

  property var screen

  cardWidth: root.grid ? root.grid.unit * 1.5 : 0
  title: I18n.tr("Look")
  intro: I18n.tr("Pick a wallpaper and a theme. Themes can also be generated from a wallpaper: pick one, and a matching light and dark theme appear in the list.")

  // --- Wallpaper folder ---

  readonly property string folder: Appearance.wallpaperFolder
  // WallpaperManager.folderImages: -1 checking, -2 missing
  readonly property int imageCount: WallpaperManager.folderImages
  onFolderChanged: WallpaperManager.checkFolder()
  Component.onCompleted: WallpaperManager.checkFolder()

  SettingRows {
    Layout.fillWidth: true
    paths: ["Appearance.wallpaper.folder"]
  }

  Notice {
    visible: root.imageCount === -2 || root.imageCount === 0
    tone: "warning"
    text: root.imageCount === -2 ? (WallpaperManager.hasHyprlandWallpapers ? I18n.tr("That folder doesn't exist yet. Create it and put some images in it, or use Hyprland's wallpapers for now.") : I18n.tr("That folder doesn't exist yet. Create it and put some images in it.")) : I18n.tr("That folder has no images (jpg, png or bmp) yet.")
  }

  RowLayout {
    visible: root.imageCount === -2 || root.imageCount === 0
    spacing: Widget.spacing

    StyledTextButton {
      visible: root.imageCount === -2
      text: I18n.tr("Create it")
      iconText: "create_new_folder"
      onClicked: WallpaperManager.createFolder()
    }

    StyledTextButton {
      visible: root.imageCount === 0
      text: I18n.tr("Open it")
      iconText: "folder_open"
      onClicked: WallpaperManager.openFolder()
    }

    StyledTextButton {
      visible: WallpaperManager.hasHyprlandWallpapers
      text: I18n.tr("Use Hyprland's wallpapers")
      iconText: "wallpaper"
      onClicked: SettingsManager.commitValues({
        "Appearance.wallpaper.folder": WallpaperManager.hyprlandWallpapers
      })
    }

    StyledTextButton {
      text: I18n.tr("Check again")
      iconText: "refresh"
      onClicked: WallpaperManager.checkFolder()
    }
  }

  // --- Bar ---

  // As saved (ScreenEdgeManager.bars turns `location` into an edge enum)
  readonly property var bar: Bar.savedBars?.[0] ?? null

  function setBar(key, value) {
    const values = {};
    values["Bars.items.0." + key] = value;
    SettingsManager.commitValues(values);
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    visible: root.bar !== null
    text: I18n.tr("Bar")
    font.bold: true
  }

  GridLayout {
    Layout.fillWidth: true
    visible: root.bar !== null
    columns: 1
    columnSpacing: Widget.spacing
    rowSpacing: Widget.spacing

    Repeater {
      model: [
        {
          "value": "pills",
          "icon": "view_agenda",
          "title": I18n.tr("Pills"),
          "description": I18n.tr("A pill per group of widgets")
        },
        {
          "value": "solid",
          "icon": "crop_16_9",
          "title": I18n.tr("Solid"),
          "description": I18n.tr("One bar along the edge")
        },
        {
          "value": "transparent",
          "icon": "blur_on",
          "title": I18n.tr("Transparent"),
          "description": I18n.tr("Widgets on the wallpaper")
        },
        {
          "value": "floating",
          "icon": "toolbar",
          "title": I18n.tr("Floating bar"),
          "description": I18n.tr("One bar held off the edge")
        },
        {
          "value": "floatingPills",
          "icon": "more_horiz",
          "title": I18n.tr("Floating pills"),
          "description": I18n.tr("A floating pill per group")
        }
      ]

      delegate: OptionCard {
        required property var modelData
        icon: modelData.icon
        title: modelData.title
        description: modelData.description
        selected: root.bar?.background === modelData.value
        onClicked: root.setBar("background", modelData.value)
      }
    }
  }

  RowLayout {
    visible: root.bar !== null
    spacing: Widget.spacing

    StyledText {
      text: I18n.tr("Edge")
    }

    Repeater {
      model: ["top", "bottom", "left", "right"]

      delegate: StyledTextButton {
        required property string modelData
        // I18n.tr("Top") I18n.tr("Bottom") I18n.tr("Left") I18n.tr("Right")
        text: I18n.tr(modelData[0].toUpperCase() + modelData.slice(1))
        backgroundColor: root.bar?.location === modelData ? Theme.accent : Theme.backgroundHighlight
        textColor: root.bar?.location === modelData ? Theme.background : Theme.foreground
        onClicked: root.setBar("location", modelData)
      }
    }
  }

  SettingRows {
    Layout.fillWidth: true
    paths: ["Appearance.shape.screenBorder"]
  }

  StyledText {
    Layout.fillWidth: true
    text: I18n.tr("Widgets are arranged in the overlay's Bar editor.")
    wrapMode: Text.WordWrap
    textColor: Theme.foregroundAlt
  }

  extras: [
    Item {
      implicitWidth: root.grid.span(4)
      implicitHeight: root.grid.span(8)

      WallpaperPicker {
        slotRect: [0, 0, 4, 8]
      }
    },
    Item {
      implicitWidth: root.grid.span(4)
      implicitHeight: root.grid.span(8)

      ThemePicker {
        slotRect: [0, 0, 4, 8]
      }
    }
  ]
}
