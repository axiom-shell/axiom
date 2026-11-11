pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.compositor
import qs.services.session
import qs.components.reusable
import qs.components.forms

// First page: what axiom is, language and name, and the overlay's size
// (this window is sized as the overlay is, so it's the preview), and where the
// compositor can be set up, Use recommended: the Recommended setup list
// (RecommendedSetupManager) applied at once, its rows under a fold. Its
// compositor mode row applies on Finish, like the Compositor page's choice
OnboardingPage {
  id: root

  title: I18n.tr("Welcome to axiom")
  intro: I18n.tr("axiom is your desktop shell: the bar, notifications, launcher, lock screen, power menu and an overlay full of cards. A few steps set up the essentials. Everything applies as you go, and you can change all of it later in Settings.")

  // The Recommended setup rows by state, for the button and its summary
  readonly property var rowList: RecommendedSetupManager.ids.map(id => RecommendedSetupManager.rows[id])
  readonly property int failedCount: root.rowList.filter(row => row.state === "failed").length
  readonly property bool applied: root.rowList.some(row => row.state === "done" || row.state === "later")
  // The fold opens by itself when a row fails, so the error shows
  property bool foldOpen: false
  // The compositor mode row applies on Finish (chooseMode)
  readonly property var later: ["Compositor.mode"]
  readonly property var choose: (path, value) => OnboardingManager.chooseMode(value)

  SettingRows {
    Layout.fillWidth: true
    paths: ["General.language", "General.displayName"]
  }

  StyledText {
    Layout.fillWidth: true
    Layout.topMargin: Widget.spacing
    text: I18n.tr("How big should cards and text be? This window uses the same sizes, so it changes as you drag.")
    wrapMode: Text.WordWrap
  }

  SettingRows {
    Layout.fillWidth: true
    paths: ["Interface.cardSize", "Interface.scale"]
  }

  // The Recommended setup, where the compositor can be set up
  ColumnLayout {
    visible: CompositorManager.supports.configModes
    Layout.fillWidth: true
    Layout.topMargin: Widget.spacing
    spacing: Widget.spacing

    StyledText {
      Layout.fillWidth: true
      text: I18n.tr("Turns on what axiom can run for you, in one go. Untick what you'd rather keep your own under What this turns on. The login screen comes last and asks for your password.")
      wrapMode: Text.WordWrap
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      // Not while the greeter or portal check is still out: a quick press
      // would skip a row whose check hadn't come back
      StyledTextButton {
        iconText: "verified"
        text: I18n.tr("Use recommended")
        enabled: !RecommendedSetupManager.running && !root.rowList.some(row => row.reason === "unknown")
        // Its own later and choose, whatever another host's list set since
        onClicked: RecommendedSetupManager.apply({
          "later": root.later,
          "choose": root.choose
        })
      }

      StyledText {
        Layout.fillWidth: true
        text: RecommendedSetupManager.running ? I18n.tr("Applying...") : root.failedCount > 0 ? I18n.tr("{0} failed", root.failedCount) : root.applied ? I18n.tr("Done") : ""
        textColor: root.failedCount > 0 && !RecommendedSetupManager.running ? Theme.error : Theme.foregroundInactive
      }
    }

    FoldingSection {
      title: I18n.tr("What this turns on")
      collapsed: !(root.foldOpen || root.failedCount > 0)
      onToggled: root.foldOpen = !root.foldOpen
      Layout.fillWidth: true

      RecommendedSetupList {
        later: root.later
        choose: root.choose
        showApply: false
      }
    }
  }

  Notice {
    text: I18n.tr("Next to the step names at the bottom are the arrows, and you can click any step to jump to it. Skip setup keeps what you chose so far.")
  }
}
