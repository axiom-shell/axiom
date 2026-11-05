pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable
import qs.components.content.parts

// What's missing: the programs features use and the commands that install
// them here (ToolChecks)
OnboardingPage {
  id: root

  title: I18n.tr("Checks")
  intro: I18n.tr("axiom uses a few programs for some of its features. Everything else works without them.")

  Notice {
    visible: checks.checked && checks.wanted.length === 0
    tone: "success"
    text: I18n.tr("Everything axiom uses is installed.")
  }

  ToolChecks {
    id: checks
  }

  StyledTextButton {
    text: I18n.tr("Check again")
    iconText: "refresh"
    onClicked: checks.check()
  }
}
