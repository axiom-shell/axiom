pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.session
import qs.components.reusable
import qs.components.hosts.overlay

// The onboarder's steps where the overlay has its page navigator (the same
// navigator, so the pages get the overlay's room): Skip setup, the steps,
// and Next (Finish on the last). Skipping asks first.
RowLayout {
  id: root

  property real maxWidth: 0
  property bool confirmingQuit: false

  signal quitRequested
  signal quitCancelled
  signal quitConfirmed

  spacing: Widget.spacing * 2

  readonly property real buttonHeight: Math.round(Widget.height * 1.5)

  StyledTextButton {
    id: skipButton
    visible: !root.confirmingQuit
    Layout.preferredHeight: root.buttonHeight
    text: I18n.tr("Skip setup")
    iconText: "close"
    backgroundColor: Theme.backgroundAlt
    borderColor: Theme.foreground
    borderWidth: Appearance.borderWidth
    onClicked: root.quitRequested()
  }

  // The navigator sizes itself (width, not implicitWidth): a plain item
  // gives the layout its size
  Item {
    visible: !root.confirmingQuit
    implicitWidth: navigator.width
    implicitHeight: navigator.height

    OverlayPageNavigator {
      id: navigator
      // I18n.tr: page titles are declared in OnboardingManager
      pages: OnboardingManager.pages.map(page => ({
            "icon": page.icon,
            "label": I18n.tr(page.title)
          }))
      currentIndex: OnboardingManager.step
      maxWidth: root.maxWidth > 0 ? root.maxWidth - root.spacing * 2 - skipButton.implicitWidth - nextButton.implicitWidth : 0
      onPrevious: OnboardingManager.back()
      onNext: OnboardingManager.goTo(OnboardingManager.step + 1)
      onSelect: index => OnboardingManager.goTo(index)
    }
  }

  StyledTextButton {
    id: nextButton
    visible: !root.confirmingQuit
    Layout.preferredHeight: root.buttonHeight
    text: OnboardingManager.isLast ? I18n.tr("Finish") : I18n.tr("Next")
    iconText: OnboardingManager.isLast ? "check" : "arrow_forward"
    iconAfter: true
    backgroundColor: Theme.accent
    textColor: Theme.background
    hoverColor: Theme.accentAlt
    onClicked: OnboardingManager.next()
  }

  // Confirming a skip
  Rectangle {
    visible: root.confirmingQuit
    Layout.preferredHeight: root.buttonHeight
    implicitWidth: confirmRow.implicitWidth + Widget.padding * 2
    radius: Widget.radius
    color: Theme.backgroundAlt
    border.color: Theme.foreground
    border.width: Appearance.borderWidth

    RowLayout {
      id: confirmRow
      anchors.centerIn: parent
      spacing: Widget.spacing * 2

      StyledText {
        text: I18n.tr("Skip the rest? Your choices so far are kept, and /welcome in the launcher brings this back.")
      }

      StyledTextButton {
        text: I18n.tr("Keep going")
        onClicked: root.quitCancelled()
      }

      StyledTextButton {
        text: I18n.tr("Skip setup")
        backgroundColor: Theme.error
        textColor: Theme.background
        onClicked: root.quitConfirmed()
      }
    }
  }
}
