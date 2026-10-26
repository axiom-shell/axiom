pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.services.session
import qs.components.reusable
import qs.components.surfaces.onboarding
import qs.services.ui

// The first-run onboarder (OnboardingManager), on the primary monitor over
// the dimmed screen. Built only while it's open; when the primary monitor
// changes (the Monitors step) it moves there, on the same step.
Scope {
  Variants {
    model: {
      if (!OnboardingManager.shown)
        return [];
      const screens = General.outputs;
      return [screens.find(screen => screen.name === General.primaryMonitor) ?? screens[0]].filter(screen => !!screen);
    }

    delegate: Scope {
      id: onboarding
      required property ShellScreen modelData

      BackdropRequest {
        screen: onboarding.modelData
        // Away while another polkit agent's prompt needs the screen
        shown: !ShellManager.steppedAside
      }

      OnboardingWindow {
        screen: onboarding.modelData
      }
    }
  }
}
