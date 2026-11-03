pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.compositor
import qs.services.session
import qs.services.system
import qs.components.reusable
import qs.components.forms

// How axiom and the compositor's config fit together, on any compositor
// axiom can set up (configModes): what its config folder holds
// (OnboardingManager.configState), the three modes (always all three:
// managed recommended, included for complex setups, detached for testing;
// an unavailable one says why), the lines the included and detached modes
// need in the compositor's config (IntegrationHookup: copy or Apply) and
// the keyboard and touchpad. The mode is only applied on Finish. Its paths
// and names come from the compositor's config writer
// (CompositorConfigManager), so nothing here is one compositor's.
OnboardingPage {
  id: root

  readonly property string configState: OnboardingManager.configState
  readonly property string compositor: CompositorManager.displayName
  // The config axiom manages ("~/.config/sway/config"), and where the
  // user's own files go then
  readonly property string config: Paths.shortenHome(CompositorConfigManager.managedPath)
  readonly property string userDir: Paths.shortenHome(CompositorConfigManager.userDir)

  title: I18n.tr("Compositor")
  intro: {
    switch (root.configState) {
    case "stock":
    case "none":
      return I18n.tr("Looks like you're running {0}'s example config. It has its own keys and apps that clash with axiom's. Let axiom manage {0} instead: you get a complete setup with sane keybinds, and your own tweaks go in {1}/.", root.compositor, root.userDir);
    case "custom":
      return I18n.tr("We noticed you have your own {0} config. How should axiom fit in with it?", root.compositor);
    case "blocked":
      return I18n.tr("Your {0} config is a symlink or lives in a git repository (dotfiles), so axiom will never take it over. Load axiom's part from it instead.", root.compositor);
    case "legacy":
      return OnboardingManager.legacyNote;
    case "ours":
      return I18n.tr("axiom already manages your {0} config. Keep it that way, or pick another mode.", root.compositor);
    }
    return I18n.tr("Looking at your {0} config…", root.compositor);
  }

  // Why axiom can't set this compositor up (an older Hyprland)
  Notice {
    visible: OnboardingManager.setupProblem !== ""
    tone: "error"
    text: OnboardingManager.setupProblem
  }

  // What this compositor can't do that another build can (plain sway:
  // SwayFX blurs, rounds corners and casts shadows)
  Notice {
    readonly property string hint: CompositorManager.unsupportedHint("blur")
    visible: hint !== ""
    tone: "info"
    text: I18n.tr("{0} can't blur, round window corners or cast shadows, so axiom's surfaces are solid. {1}", root.compositor, hint)
  }

  Repeater {
    model: [
      {
        "mode": "managed",
        "icon": "auto_awesome",
        "tag": I18n.tr("Recommended"),
        "title": I18n.tr("Let axiom manage {0}", root.compositor),
        "description": root.configState === "stock" ? I18n.tr("Replaces the example {0} (a dated backup stays beside it) with one axiom writes from its settings, then loads your files in {1}/ after it.", root.config, root.userDir) : root.configState === "custom" ? I18n.tr("Moves your {0} into {1}/, where it keeps working, loaded after axiom's (a dated backup stays too). Its binds move into axiom's Keybinds page and out of that file; any that can't move stay there and win over axiom's.", root.config, root.userDir) : I18n.tr("axiom writes {0} from its settings, and loads your own files in {1}/ after it.", root.config, root.userDir)
      },
      {
        "mode": "included",
        "icon": "input",
        "tag": I18n.tr("For complex setups"),
        "title": I18n.tr("Load axiom from my config"),
        // Where the writer puts the lines (its include target): niri's go
        // at the end
        "description": CompositorConfigManager.includeTarget?.place === "end" ? I18n.tr("Your {0} stays yours: a line at its end loads axiom's keybinds, borders and input.", root.config) : I18n.tr("Your {0} stays yours: lines at its top load axiom's keybinds, borders and input.", root.config)
      },
      {
        "mode": "detached",
        "icon": "link_off",
        "tag": I18n.tr("For testing"),
        "title": I18n.tr("Keep them apart"),
        "description": I18n.tr("axiom writes no {0} files: it adds its keybinds while it runs, skipping keys your config already uses. Your {1} only starts axiom.", root.compositor, root.config)
      }
    ]

    delegate: OptionCard {
      required property var modelData
      icon: modelData.icon
      title: modelData.title
      description: modelData.description
      selected: OnboardingManager.chosenMode === modelData.mode
      tag: modelData.tag
      tagColor: modelData.mode === "managed" ? Theme.accent : Theme.warning
      available: !(modelData.mode === "managed" && root.configState === "blocked")
      unavailableReason: modelData.mode === "managed" ? OnboardingManager.blockedReason : ""
      onClicked: OnboardingManager.chooseMode(modelData.mode)
    }
  }

  // What the chosen mode needs in the user's config: copy the lines, or
  // Apply them (a backup first), as a theme integration's hookup
  IntegrationHookup {
    Layout.fillWidth: true
    integration: "compositorInclude"
    active: OnboardingManager.chosenMode === "included"
    doneText: I18n.tr("Your {0} loads axiom and starts it. After Finish, axiom writes the file it loads.", root.config)
    todoText: I18n.tr("Your {0} needs to load axiom's file and start axiom: copy the lines, or Apply to add them for you.", root.config)
  }

  Notice {
    visible: OnboardingManager.chosenMode === "detached" && !OnboardingManager.autostartDone
    tone: "warning"
    text: I18n.tr("{0} won't start axiom by itself in this mode until your {1} does:", root.compositor, root.config)
  }

  IntegrationHookup {
    Layout.fillWidth: true
    integration: "compositorAutostart"
    active: OnboardingManager.chosenMode === "detached"
    doneText: I18n.tr("Your {0} starts axiom with every session.", root.config)
    todoText: I18n.tr("Start axiom with every session: copy the line, or Apply to add it for you.")
  }

  Notice {
    visible: CompositorConfigManager.skippedKeys.length > 0 && OnboardingManager.chosenMode !== "managed"
    tone: "warning"
    text: I18n.tr("Your config already binds {0}, so axiom's binds on those keys are skipped. Free them in your config, or pick other keys on the Keybinds page.", CompositorConfigManager.skippedKeys.join(", "))
  }

  // Input settings, applied in any mode once their part is on
  ColumnLayout {
    Layout.fillWidth: true
    visible: CompositorManager.supports.inputConfig === true
    spacing: Widget.spacing

    StyledText {
      Layout.topMargin: Widget.spacing
      text: I18n.tr("Keyboard")
      font.bold: true
    }

    SettingRows {
      Layout.fillWidth: true
      paths: ["Input.keyboard.enabled", "Input.keyboard.layout", "Input.keyboard.variant"]
    }

    StyledText {
      Layout.topMargin: Widget.spacing
      visible: BatteryManager.isAvailable
      text: I18n.tr("Touchpad")
      font.bold: true
    }

    SettingRows {
      Layout.fillWidth: true
      visible: BatteryManager.isAvailable
      paths: ["Input.touchpad.enabled", "Input.touchpad.naturalScroll", "Input.touchpad.tapToClick"]
    }
  }

  StyledText {
    Layout.fillWidth: true
    text: I18n.tr("The mode is applied when you press Finish; only Apply above changes {0} right away. You can switch modes later in Settings → Compositor.", root.config)
    wrapMode: Text.WordWrap
    textColor: Theme.foregroundAlt
  }
}
