pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.forms
import qs.components.content.base
import qs.components.content.Palette
import qs.components.content.ThemePicker
import qs.components.content.WallpaperPicker
import qs.components.views.base

// The Themes page, in the editors' shape (each piece streamed in as the
// page opens, StreamedLoader): the wallpapers on the left, the
// theme list beside them, then the current palette and a few look
// settings. The pieces are the ordinary WallpaperPicker, ThemePicker and
// Palette modules, so they can go on any page too. A view type with
// nothing to configure.
BaseView {
  id: root

  // The theme list is about one card wide, as tall as the page
  readonly property real themesWidth: root.grid.unit * 0.9
  readonly property real columnWidth: root.editorWidth - root.themesWidth - OverlayConfig.cardSpacing

  Item {
    implicitWidth: root.sideWidth
    implicitHeight: root.pageHeight

    StreamedLoader {
      anchors.fill: parent
      label: "wallpaper picker"
      sourceComponent: WallpaperPicker {
        slotRect: [0, 0, 4, 8]
      }
    }
  }

  Item {
    implicitWidth: root.themesWidth
    implicitHeight: root.pageHeight

    StreamedLoader {
      anchors.fill: parent
      label: "theme picker"
      sourceComponent: ThemePicker {
        slotRect: [0, 0, 4, 8]
      }
    }
  }

  ColumnLayout {
    Layout.preferredWidth: root.columnWidth
    Layout.preferredHeight: root.pageHeight
    spacing: OverlayConfig.cardSpacing

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: root.grid.span(4)

      StreamedLoader {
        anchors.fill: parent
        label: "palette"
        sourceComponent: Palette {
          slotRect: [0, 0, 8, 4]
        }
      }
    }

    // Settings that change the look as much as the theme does; the rest
    // are in Settings
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      StreamedLoader {
        anchors.fill: parent
        label: "look settings"
        sourceComponent: TitledCard {
          title: I18n.tr("Look")
          scrollKey: "Themes"
          showActions: false

          SettingRows {
            Layout.fillWidth: true
            paths: ["Appearance.font.family", "Appearance.font.size", "Appearance.shape.radius", "Appearance.motion.enabled"]
          }

          StyledTextButton {
            Layout.alignment: Qt.AlignRight
            text: I18n.tr("More in Look & Feel")
            iconText: "chevron_right"
            iconAfter: true
            onClicked: SettingsManager.openSetting("Appearance", true)
          }
        }
      }
    }
  }
}
