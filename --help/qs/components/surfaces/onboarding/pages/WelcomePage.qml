pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable
import qs.components.forms

// First page: what axiom is, language and name, and the overlay's size
// (this window is sized as the overlay is, so it's the preview)
OnboardingPage {
  id: root

  title: I18n.tr("Welcome to axiom")
  intro: I18n.tr("axiom is your desktop shell: the bar, notifications, launcher, lock screen, power menu and an overlay full of cards. A few steps set up the essentials. Everything applies as you go, and you can change all of it later in Settings.")

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

  Notice {
    text: I18n.tr("Next to the step names at the bottom are the arrows, and you can click any step to jump to it. Skip setup keeps what you chose so far.")
  }
}
