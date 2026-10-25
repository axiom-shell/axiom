pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.forms

// The apps the keybinds open (terminal, file manager, browser), with the
// installed ones offered to pick from, the main modifier, and the keys
// that matter most on day one. The keys only where axiom binds them
// (CompositorManager.supports.keybinds)
OnboardingPage {
  id: root

  readonly property bool binds: CompositorManager.supports.keybinds === true

  title: root.binds ? I18n.tr("Apps & keys") : I18n.tr("Apps")
  intro: root.binds ? I18n.tr("Which apps should the keybinds open? Pick one that's installed, or type the command. Empty file manager and browser use your system's default.") : I18n.tr("Which apps should axiom open? Pick one that's installed, or type the command. Empty file manager and browser use your system's default.")

  // Candidates offered as chips when they're installed
  readonly property var candidates: ({
      "Apps.terminal": ["kitty", "foot", "alacritty", "wezterm", "ghostty", "konsole", "gnome-terminal", "xfce4-terminal"],
      "Apps.fileManager": ["nautilus", "thunar", "dolphin", "nemo", "pcmanfm-qt", "pcmanfm"],
      "Apps.browser": ["firefox", "zen-browser", "librewolf", "chromium", "google-chrome-stable", "brave", "vivaldi-stable"]
    })

  Component.onCompleted: DependencyManager.check([].concat(...Object.keys(candidates).map(key => candidates[key])).concat([Apps.terminal, Apps.fileManager, Apps.browser]))

  Connections {
    target: ConfigManager
    function onConfigChanged() {
      DependencyManager.check([Apps.terminal, Apps.fileManager, Apps.browser]);
    }
  }

  Repeater {
    model: Object.keys(root.candidates)

    delegate: ColumnLayout {
      id: app
      required property string modelData
      readonly property string current: String(SettingsManager.configValueAt(modelData) ?? "")
      readonly property var installed: root.candidates[modelData].filter(command => DependencyManager.found[command])
      Layout.fillWidth: true
      spacing: Widget.spacing

      SettingRows {
        id: rows
        Layout.fillWidth: true
        paths: [app.modelData]
      }

      Flow {
        Layout.fillWidth: true
        visible: app.installed.length > 0
        spacing: Widget.spacing

        Repeater {
          model: app.installed

          delegate: StyledTextButton {
            required property string modelData
            text: modelData
            backgroundColor: app.current === modelData ? Theme.accent : Theme.backgroundHighlight
            textColor: app.current === modelData ? Theme.background : Theme.foreground
            onClicked: {
              const values = {};
              values[app.modelData] = modelData;
              SettingsManager.commitValues(values);
            }
          }
        }
      }

      Notice {
        visible: app.current.trim() !== "" && DependencyManager.has(app.current) === false
        tone: "warning"
        text: I18n.tr("\"{0}\" isn't installed.", app.current.trim().split(/\s+/)[0])
      }
    }
  }

  // The main modifier: Super everywhere, or Alt (they trade places, so
  // Super + Alt binds stay distinct)
  readonly property string modifier: {
    const launcher = KeybindsConfig.activeBinds.find(bind => bind.action === "launcher");
    return /^\s*ALT\b/i.test(launcher?.key ?? "") ? "ALT" : "SUPER";
  }

  function setModifier(modifier) {
    if (modifier === root.modifier)
      return;
    const swap = {
      "SUPER": "ALT",
      "ALT": "SUPER"
    };
    const binds = KeybindsConfig.binds.map(bind => Object.assign({}, bind, {
        "key": String(bind.key ?? "").split("+").map(part => swap[part.trim().toUpperCase()] ?? part.trim()).join(" + ")
      }));
    SettingsManager.commitValues({
      "Keybinds.binds": binds
    });
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    visible: root.binds
    text: I18n.tr("Main modifier key")
    font.bold: true
  }

  RowLayout {
    Layout.fillWidth: true
    visible: root.binds
    spacing: Widget.spacing

    OptionCard {
      icon: "keyboard_command_key"
      title: I18n.tr("Super")
      description: I18n.tr("The Windows / Command key. Leaves Alt to your apps.")
      selected: root.modifier === "SUPER"
      recommended: true
      onClicked: root.setModifier("SUPER")
    }

    OptionCard {
      icon: "keyboard_option_key"
      title: I18n.tr("Alt")
      description: I18n.tr("For keyboards without a Super key.")
      selected: root.modifier === "ALT"
      onClicked: root.setModifier("ALT")
    }
  }

  StyledText {
    Layout.topMargin: Widget.spacing
    visible: root.binds
    text: I18n.tr("Keys to know")
    font.bold: true
  }

  BindsTable {
    Layout.fillWidth: true
    visible: root.binds
    entries: [
      {
        "action": "launcher",
        "label": I18n.tr("App launcher")
      },
      {
        "action": "terminal",
        "label": I18n.tr("Terminal")
      },
      {
        "action": "overlay",
        "label": I18n.tr("Overlay")
      },
      {
        "action": "fileManager",
        "label": I18n.tr("File manager")
      },
      {
        "action": "closeWindow",
        "label": I18n.tr("Close window")
      },
      {
        "action": "browser",
        "label": I18n.tr("Browser")
      },
      {
        "action": "workspaceOverview",
        "label": I18n.tr("Workspace overview")
      },
      {
        "action": "screenshot",
        "argument": "region",
        "label": I18n.tr("Screenshot a region")
      },
      {
        "action": "powerMenu",
        "label": I18n.tr("Power menu")
      },
      {
        "action": "lock",
        "label": I18n.tr("Lock")
      }
    ]
  }

  StyledText {
    Layout.fillWidth: true
    visible: root.binds
    text: I18n.tr("Every key can be changed on the overlay's Keybinds page.")
    wrapMode: Text.WordWrap
    textColor: Theme.foregroundAlt
  }
}
