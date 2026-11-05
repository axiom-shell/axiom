pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.services.ui
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// The input sources (InputSourceManager), the one in use marked: a click
// on one switches to it; the header's button opens the Input settings.
// The KeyboardLayout widget's popout.
Panel {
  id: root

  readonly property var sources: InputSourceManager.sources

  implicitWidth: Widget.px(280)

  ModuleHeader {
    icon: "keyboard"
    title: I18n.tr("Input sources")

    StyledText {
      visible: InputSourceManager.running
      text: InputSourceManager.framework
      textSize: Appearance.fontSizeBy(-2)
      textColor: Theme.foregroundAlt
    }
    FlatIconButton {
      iconText: "settings"
      tooltipText: I18n.tr("Input settings")
      onClicked: SettingsManager.openSetting("Input", true)
    }
  }

  StyledSeparator {
    Layout.fillWidth: true
    separatorColor: Theme.backgroundHighlight
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: 0

    // A count: the list is the config's (and the compositor's layouts)
    Repeater {
      model: root.sources.length

      ItemRow {
        id: row
        required property int index
        readonly property string sourceId: root.sources[index]?.id ?? ""
        readonly property bool current: sourceId === InputSourceManager.current

        icon: row.current ? "check" : InputSourceManager.iconFor(row.sourceId)
        marked: row.current
        title: InputSourceManager.nameFor(row.sourceId)
        detail: InputSourceManager.labelFor(row.sourceId, "short")
        onActivated: InputSourceManager.set(row.sourceId)
      }
    }
  }
}
