pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.core
import qs.services.session
import qs.components.reusable

// The General section's first card (the section's `x-card`): the
// first-time setup (OnboardingManager), to run again
FieldGroup {
  id: root

  description: I18n.tr("Walks through the compositor setup, monitors, apps and keys, workspaces, the look and integrations again.")
  headerExtras: StyledTextButton {
    text: I18n.tr("Run setup")
    iconText: "waving_hand"
    onClicked: {
      ShellManager.closeOverlay();
      OnboardingManager.open();
    }
  }
}
