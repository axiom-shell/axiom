pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable
import qs.components.content.parts

// Settings page, System (a category `card`, wide): the optional programs
// axiom's features use, which are installed, and the command that installs
// the rest here (ToolChecks, as the onboarder's Checks)
FieldGroup {
  id: root

  headerExtras: [
    StatusChip {
      shown: checks.checked
      text: checks.wanted.length === 0 ? I18n.tr("All installed") : I18n.tr("{0} missing", checks.wanted.length)
      color: checks.wanted.length === 0 ? Theme.success : Theme.warning
    },
    StyledIconButton {
      iconText: "refresh"
      tooltipText: I18n.tr("Check again")
      onClicked: checks.check()
    }
  ]

  StyledText {
    Layout.fillWidth: true
    text: I18n.tr("Programs some features use. Everything else works without them.")
    textColor: Theme.foregroundAlt
    wrapMode: Text.WordWrap
  }

  ToolChecks {
    id: checks
    columns: root.width > Widget.px(640) ? 2 : 1
  }
}
