pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.forms
import qs.components.content.ThemePicker
import qs.components.content.WallpaperPicker

// The look: the wallpaper folder, bar style, screen border and the example
// setups (applied at once) here, with the wallpaper picker and theme list
// beside it
OnboardingPage {
  id: root

  property var screen

  cardWidth: root.grid ? root.grid.unit * 1.5 : 0
  title: I18n.tr("Look")
  intro: I18n.tr("Pick a wallpaper and a theme. Themes can also be generated from a wallpaper: pick one, and a matching light and dark theme appear in the list.")

  // -- Wallpaper folder --

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
    status: "warning"
    text: root.imageCount === -2 ? (WallpaperManager.compositorWallpapers !== "" ? I18n.tr("That folder doesn't exist yet. Create it and put some images in it, or use {0}'s wallpapers for now.", CompositorManager.displayName) : I18n.tr("That folder doesn't exist yet. Create it and put some images in it.")) : I18n.tr("That folder has no images ({0}) yet.", WallpaperManager.extensions.join(", "))
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
      visible: WallpaperManager.compositorWallpapers !== ""
      text: I18n.tr("Use {0}'s wallpapers", CompositorManager.displayName)
      iconText: "wallpaper"
      onClicked: SettingsManager.commitValues({
        "Appearance.wallpaper.folder": WallpaperManager.compositorWallpapers
      })
    }

    StyledTextButton {
      text: I18n.tr("Check again")
      iconText: "refresh"
      onClicked: WallpaperManager.checkFolder()
    }
  }

  // -- Bar --

  // As saved (ScreenEdgeManager.bars turns `edge` into an edge enum)
  readonly property var bar: BarsConfig.savedBars?.[0] ?? null

  function setBar(key, value) {
    const values = {};
    values["Bars.items.0." + key] = value;
    SettingsManager.commitValues(values);
  }

  SectionHeading {
    Layout.topMargin: Widget.spacing
    visible: root.bar !== null
    title: I18n.tr("Bar")
  }

  ChoiceTiles {
    id: kinds
    Layout.fillWidth: true
    visible: root.bar !== null
    layout: "list"
    // Each a surface and whether it floats (BarsConfig.kindOf's kinds)
    options: [
      {
        "value": "pills",
        "surface": "pills",
        "floating": false,
        "icon": "view_agenda",
        "label": I18n.tr("Pills"),
        "description": I18n.tr("A pill per group of widgets")
      },
      {
        "value": "solid",
        "surface": "bar",
        "floating": false,
        "icon": "crop_16_9",
        "label": I18n.tr("Solid"),
        "description": I18n.tr("One bar along the edge")
      },
      {
        "value": "transparent",
        "surface": "none",
        "floating": false,
        "icon": "blur_on",
        "label": I18n.tr("Transparent"),
        "description": I18n.tr("Widgets on the wallpaper")
      },
      {
        "value": "floating",
        "surface": "bar",
        "floating": true,
        "icon": "toolbar",
        "label": I18n.tr("Floating bar"),
        "description": I18n.tr("One bar held off the edge")
      },
      {
        "value": "floatingPills",
        "surface": "pills",
        "floating": true,
        "icon": "more_horiz",
        "label": I18n.tr("Floating pills"),
        "description": I18n.tr("A floating pill per group")
      }
    ]
    value: root.bar !== null ? BarsConfig.kindOf(root.bar) : ""
    onPicked: value => {
      const option = kinds.options.find(entry => entry.value === value);
      const values = {};
      values["Bars.items.0.surface"] = option.surface;
      values["Bars.items.0.floating"] = option.floating;
      SettingsManager.commitValues(values);
    }
  }

  FormColumn {
    Layout.fillWidth: true
    visible: root.bar !== null

    FieldRow {
      label: I18n.tr("Edge")
      shortControl: true

      SegmentRow {
        Repeater {
          model: ["top", "bottom", "left", "right"]

          delegate: SegmentButton {
            required property string modelData
            // I18n.tr("Top") I18n.tr("Bottom") I18n.tr("Left") I18n.tr("Right")
            text: I18n.tr(modelData[0].toUpperCase() + modelData.slice(1))
            implicitHeight: Widget.height
            Layout.fillWidth: false
            active: root.bar?.edge === modelData
            onClicked: root.setBar("edge", modelData)
          }
        }
      }
    }
  }

  SettingRows {
    Layout.fillWidth: true
    paths: ["Appearance.shape.screenBorder"]
  }

  // -- Example setups --

  SectionHeading {
    Layout.topMargin: Widget.spacing
    visible: SavedConfigsManager.examples.length > 0
    title: I18n.tr("Example setups")
    description: I18n.tr("Applies a whole look (bars, theme, menus) at once. Your wallpaper and the rest of this setup stay.")
  }

  TileFlow {
    id: examples
    Layout.fillWidth: true
    minColumns: 2

    Repeater {
      model: SavedConfigsManager.examples

      delegate: PreviewTile {
        id: exampleTile
        required property var modelData
        readonly property bool applied: SavedConfigsManager.activeSource === exampleTile.modelData.name

        width: examples.tileWidth
        title: exampleTile.modelData.title
        caption: exampleTile.modelData.description
        selected: exampleTile.applied
        preview: exampleScreen
        previewProperties: ({
            "example": exampleTile.modelData,
            "applied": exampleTile.applied
          })
        // The screen 16:10 over its palette row
        previewHeight: (examples.tileWidth - Widget.smallPadding) * 10 / 16 + Widget.px(10) + Widget.spacing / 2
        onClicked: SavedConfigsManager.applyExample(exampleTile.modelData.name)
      }
    }
  }

  Component {
    id: exampleScreen

    ExampleScreen {}
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
