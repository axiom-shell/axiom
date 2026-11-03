pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.views.Monitors

// The monitor layout: the Monitors page as it is (without its links into
// Settings, which would open the overlay over this), beside a card saying
// what to do with it
OnboardingPage {
  id: root

  property var screen

  cardWidth: root.grid ? root.grid.unit : 0
  title: I18n.tr("Monitors")
  intro: General.outputs.length > 1 ? I18n.tr("Drag the monitors into place as they stand on your desk, then pick each one's resolution, refresh rate and scale. Apply tries it, and asks you to keep it: if the picture goes wrong, it goes back by itself after 15 seconds.") : I18n.tr("Pick your monitor's resolution, refresh rate and scale. Apply tries it, and asks you to keep it: if the picture goes wrong, it goes back by itself after 15 seconds.")

  Notice {
    text: I18n.tr("The primary monitor holds the main bar, and it's where the lock screen and this setup appear. Set it in the monitor's settings.")
  }

  Notice {
    visible: General.outputs.length > 1
    text: I18n.tr("axiom remembers a layout per set of monitors, so plugging a laptop into a dock switches to its own layout.")
  }

  extras: [
    Monitors {
      grid: root.grid
      settingsLinks: false
      viewConfig: ({
          "type": "Monitors"
        })
    }
  ]
}
