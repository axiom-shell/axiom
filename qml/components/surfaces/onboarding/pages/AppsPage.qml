pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.reusable
import qs.components.content.parts

// The default apps the keybinds open (browser, file manager, terminal)
// and mail (DefaultAppPickers), the main modifier, and the keys that
// matter most on day one. The keys only where axiom binds them
// (CompositorManager.supports.keybinds)
OnboardingPage {
  id: root

  readonly property bool binds: CompositorManager.supports.keybinds === true

  title: root.binds ? I18n.tr("Apps & keys") : I18n.tr("Apps")
  intro: root.binds ? I18n.tr("Which apps open links, folders and the terminal? The keybinds open these too. Every app follows them, and Settings › General › Default apps has the rest.") : I18n.tr("Which apps open links, folders and the terminal? Every app follows them, and Settings › General › Default apps has the rest.")

  // The default apps (the user's mimeapps.list): the ones the keybinds
  // open, and mail
  DefaultAppPickers {
    roles: ["browser", "fileManager", "terminal", "mail"]
  }

  // The main modifier: Super everywhere, or Alt (they trade places, so
  // Super + Alt binds stay distinct)
  readonly property string modifier: {
    const launcher = KeybindManager.boundBinds.find(bind => bind.action === "launcher");
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
