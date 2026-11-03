pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.components.reusable
import qs.components.forms
import qs.components.content.parts
import qs.components.content.base

// The theme list: one tile per theme (a dark/light pair is one theme), in
// folding groups (built-in, imported, generated), each painted in its own
// colors, plus the Dark/Light switch that picks the variant and Auto, which
// switches it by time of day (WallpaperManager). Themes apply immediately,
// so there's nothing to save.
// Compact, the current theme's name; a click switches Dark/Light.
TitledCard {
  id: root

  readonly property var family: ThemeManager.currentFamily
  readonly property bool hasDark: !!root.family?.dark
  readonly property bool hasLight: !!root.family?.light
  // The theme list's groups: shipped with axiom, brought by community
  // setups, made from the wallpaper. Rebuilt only when the theme folders
  // are rescanned.
  readonly property var groups: {
    const families = ThemeManager.themeFamilies;
    return [
      {
        "key": "builtin",
        "title": I18n.tr("Built-in Themes"),
        "description": "",
        "empty": "",
        "families": families.filter(family => !family.generated && !family.community)
      },
      {
        "key": "imported",
        "title": I18n.tr("Imported Themes"),
        "description": I18n.tr("Brought by community setups you've applied."),
        "empty": I18n.tr("None yet. Themes that come with a community setup show here."),
        "families": families.filter(family => family.community)
      },
      {
        "key": "generated",
        "title": I18n.tr("Generated Themes"),
        "description": I18n.tr("Made from your wallpaper when you pick one."),
        "empty": I18n.tr("None yet"),
        "families": families.filter(family => family.generated)
      }
    ];
  }
  // As many tiles across as fit
  readonly property int tileColumns: Math.max(1, Math.floor((root.width - Widget.padding * 2) / (Appearance.fontSize * 13)))

  fullMinWidth: Appearance.fontSize * 14
  fullMinHeight: Appearance.fontSize * 14

  compactContent: Item {
    CompactFigure {
      anchors.fill: parent
      icon: Appearance.darkMode ? "dark_mode" : "light_mode"
      label: root.family?.label ?? I18n.tr("Theme")
    }
    MouseArea {
      anchors.fill: parent
      enabled: root.hasDark && root.hasLight
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: ThemeManager.setLightMode(Appearance.darkMode)
    }
  }

  title: I18n.tr("Theme")
  showActions: false

  headerExtras: [
    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      SegmentRow {
        Layout.fillWidth: true

        SegmentButton {
          text: I18n.tr("Dark")
          active: Appearance.darkMode
          available: root.hasDark
          onClicked: ThemeManager.setLightMode(false)
        }

        SegmentButton {
          text: I18n.tr("Light")
          active: !Appearance.darkMode
          available: root.hasLight
          onClicked: ThemeManager.setLightMode(true)
        }
      }

      // A switch of its own: picking Dark or Light by hand lasts until the
      // schedule's next change
      SegmentButton {
        Layout.fillWidth: false
        iconText: "schedule"
        text: I18n.tr("Auto")
        active: Appearance.themeScheduled
        onClicked: SettingsManager.commitValues({
          "Appearance.theme.schedule.enabled": !Appearance.themeScheduled
        })
      }
    },
    RowLayout {
      visible: Appearance.themeScheduled
      Layout.fillWidth: true
      spacing: Widget.spacing

      SettingRows {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        paths: ["Appearance.theme.schedule.lightAt"]
      }

      SettingRows {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        paths: ["Appearance.theme.schedule.darkAt"]
      }
    },
    StyledText {
      visible: root.family !== null && !(root.hasDark && root.hasLight)
      Layout.fillWidth: true
      text: root.hasDark ? I18n.tr("This theme has no light variant.") : I18n.tr("This theme has no dark variant.")
      opacity: 0.6
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
    }
  ]

  // A theme painted in the variant the current mode would apply: its
  // background, name in its foreground, and a strip of its accent colors
  component ThemeTile: Rectangle {
    id: tile
    required property var modelData
    readonly property var preview: (Appearance.darkMode ? (modelData.darkPreview ?? modelData.lightPreview) : (modelData.lightPreview ?? modelData.darkPreview)) ?? ({})
    readonly property bool current: root.family !== null && (root.family.dark || root.family.light) === (modelData.dark || modelData.light)

    Layout.fillWidth: true
    Layout.preferredHeight: tileColumn.implicitHeight + Widget.padding * 2
    radius: Widget.radius
    color: Appearance.fill(preview.background ?? Theme.backgroundAlt)
    border.width: current ? Appearance.borderWidth * 2 + 1 : Appearance.borderWidth + 1
    border.color: current ? Theme.accent : tileArea.containsMouse ? Qt.alpha(Theme.foreground, 0.5) : Qt.alpha(Theme.border, 0.6)

    ColorGlide on border.color {}

    ColumnLayout {
      id: tileColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Widget.padding
      spacing: Widget.spacing

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        StyledText {
          Layout.fillWidth: true
          text: tile.modelData.label
          textColor: tile.preview.foreground ?? Theme.foreground
          font.bold: true
          elide: Text.ElideRight
        }

        // Has both variants
        StyledIcon {
          visible: !!tile.modelData.dark && !!tile.modelData.light
          text: "contrast"
          textColor: tile.preview.foreground ?? Theme.foreground
          opacity: 0.6
        }

        StyledIcon {
          visible: tile.current
          text: "check"
          textColor: tile.preview.accent ?? Theme.accent
          font.bold: true
        }
      }

      Row {
        spacing: Widget.spacing

        Repeater {
          model: tile.preview.colors ?? []

          delegate: Rectangle {
            required property string modelData
            width: Widget.px(12)
            height: Widget.px(12)
            radius: width / 2
            color: modelData
          }
        }
      }
    }

    MouseArea {
      id: tileArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ThemeManager.applyFamily(tile.modelData)
    }
  }

  // One folding group per source, each fold remembered (ThemeManager)
  Repeater {
    model: root.groups

    delegate: FoldingSection {
      id: group
      required property var modelData

      title: modelData.title
      description: modelData.key === "generated" && ThemeManager.isGenerating ? I18n.tr("Generating from the wallpaper...") : modelData.description
      collapsed: ThemeManager.foldedGroups.includes(modelData.key)
      onToggled: ThemeManager.toggleGroup(modelData.key)

      GridLayout {
        Layout.fillWidth: true
        columns: root.tileColumns
        columnSpacing: Widget.spacing
        rowSpacing: Widget.spacing

        Repeater {
          model: group.modelData.families
          delegate: ThemeTile {}
        }
      }

      StyledText {
        visible: group.modelData.families.length === 0
        Layout.fillWidth: true
        text: group.modelData.empty
        opacity: 0.6
        wrapMode: Text.WordWrap
      }
    }
  }
}
