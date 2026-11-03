pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// The DevMode widget's popout, from DevManager: the dev tree, its checkout
// and the last build, then Rebuild, Open Development settings and Turn off.
Panel {
  id: root

  spacing: Widget.spacing
  implicitWidth: Math.max(Widget.px(280), body.implicitWidth + margins * 2)

  ColumnLayout {
    Layout.fillWidth: true
    spacing: 0

    StyledText {
      Layout.fillWidth: true
      text: DevManager.checkout !== "" ? I18n.tr("Dev mode · {0}", DevManager.checkout) : I18n.tr("Dev mode")
      font.bold: true
      textColor: Theme.accent
      elide: Text.ElideRight
    }
    StyledText {
      Layout.fillWidth: true
      visible: text !== ""
      text: Paths.shortenHome(DevManager.tree)
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
      elide: Text.ElideMiddle
    }
    StyledText {
      Layout.fillWidth: true
      text: DevManager.buildText
      textColor: DevManager.buildFailed && !DevManager.building ? Theme.error : Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
      elide: Text.ElideRight
    }
  }

  StyledSeparator {
    Layout.fillWidth: true
  }

  ItemRow {
    icon: "build"
    title: I18n.tr("Rebuild")
    subtitle: DevManager.available ? "" : DevManager.unavailable
    clickable: DevManager.available && !DevManager.building
    opacity: clickable ? 1 : 0.5
    onActivated: DevManager.rebuild()
  }

  ItemRow {
    icon: "settings"
    title: I18n.tr("Open Development settings")
    onActivated: DevManager.openDevelopment()
  }

  ItemRow {
    icon: "power_settings_new"
    title: I18n.tr("Turn off")
    onActivated: DevManager.setEnabled(false)
  }
}
