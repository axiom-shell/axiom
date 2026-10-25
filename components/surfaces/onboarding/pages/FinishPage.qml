pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.compositor
import qs.services.session
import qs.components.reusable

// The last page: what Finish does to the compositor's config, whether
// axiom starts with the session, and where to go from here
OnboardingPage {
  id: root

  readonly property string mode: OnboardingManager.chosenMode
  // No Compositor step where axiom can't set the compositor up
  readonly property bool hasCompositorPage: OnboardingManager.pages.some(page => page.id === "compositor")
  readonly property bool changesMode: root.hasCompositorPage && OnboardingManager.compositorSupported && OnboardingManager.modeAllowed && root.mode !== CompositorConfig.mode
  readonly property string compositor: CompositorManager.displayName
  readonly property string config: Paths.shortenHome(CompositorConfigManager.managedPath)

  title: I18n.tr("All set")
  intro: I18n.tr("That's the essentials. Press Finish to apply the {0} setup and start using axiom.", root.compositor)

  Notice {
    visible: root.changesMode && root.mode === "managed"
    tone: "info"
    text: OnboardingManager.configState === "stock" ? I18n.tr("Finish replaces {0}'s example {1} with axiom's (a dated backup stays beside it) and reloads {0}. axiom starts with every session from then on.", root.compositor, root.config) : OnboardingManager.configState === "custom" ? I18n.tr("Finish moves your {1} into user/ (a dated backup stays too), writes axiom's in its place and reloads {0}. axiom starts with every session from then on.", root.compositor, root.config) : I18n.tr("Finish writes {1} and reloads {0}. axiom starts with every session from then on.", root.compositor, root.config)
  }

  Notice {
    visible: root.changesMode && CompositorConfig.mode !== "detached"
    tone: "warning"
    text: I18n.tr("Finish changes how axiom sets up {0}: what the mode it's in now set up is given back.", root.compositor)
  }

  Notice {
    visible: root.mode === "included"
    tone: OnboardingManager.includeDone && OnboardingManager.autostartDone ? "info" : "warning"
    text: !OnboardingManager.includeDone ? I18n.tr("Finish writes axiom's module, but your {0} doesn't load it yet: Apply the lines on the Compositor step. Until then, axiom adds its keybinds while it runs.", root.config) : !OnboardingManager.autostartDone ? I18n.tr("Finish writes axiom's module, which your {0} loads. It doesn't start axiom yet: Apply the autostart line on the Compositor step.", root.config) : I18n.tr("Finish writes axiom's module, which your {0} loads.", root.config)
  }

  Notice {
    visible: root.hasCompositorPage && root.mode === "detached" && !OnboardingManager.autostartDone
    tone: "warning"
    text: I18n.tr("{0} won't start axiom by itself: Apply the autostart line on the Compositor step, or add it to your {1} yourself.", root.compositor, root.config)
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    text: I18n.tr("Where things are")
    font.bold: true
  }

  BindsTable {
    Layout.fillWidth: true
    entries: [
      {
        "action": "launcher",
        "label": I18n.tr("Launch apps, and type / for commands")
      },
      {
        "action": "overlay",
        "label": I18n.tr("Overlay: cards, Settings, Keybinds, Monitors")
      },
      {
        "action": "terminal",
        "label": I18n.tr("Terminal")
      },
      {
        "action": "workspaceOverview",
        "label": I18n.tr("Workspace overview")
      },
      {
        "action": "powerMenu",
        "label": I18n.tr("Power menu")
      },
      {
        "action": "restartShell",
        "label": I18n.tr("Restart axiom if it gets stuck")
      },
      {
        "action": "exitSession",
        "label": I18n.tr("Log out")
      }
    ]
  }

  StyledText {
    Layout.fillWidth: true
    Layout.topMargin: Widget.spacing
    text: I18n.tr("In the launcher, / lists commands: /config sets any setting, /monitors opens the monitor layout, and /welcome brings this setup back. The overlay's pages hold Settings, the Keybinds editor, the Bar and overlay editors, and themes.")
    wrapMode: Text.WordWrap
  }
}
