pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.system
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts

// Under the Keyboard card's input method switch (InputSourcesField),
// shown while axiom manages the input method but doesn't write the
// compositor's config (any mode but managed) and a framework is chosen: the session's variables
// and the command starting it, to add by hand, with Copy (InputSources.
// methodSetup: the values the managed session's writer has), and
// Electron's flag.
ColumnLayout {
  id: root

  // As edited, saved or not
  readonly property string chosen: String(SettingsManager.configValueAt("Input.keyboard.method.framework") ?? "")
  readonly property bool managed: CompositorManager.supports.configModes === true && SettingsManager.configValueAt("Compositor.mode") === "managed"
  // The framework the lines are for: auto is the running one, else the
  // one installed (fcitx5 first), else fcitx5
  readonly property string framework: {
    if (root.chosen !== "auto")
      return root.chosen;
    if (InputSourceManager.running)
      return InputSourceManager.framework;
    return DependencyManager.has("ibus-daemon") === true && DependencyManager.has("fcitx5") !== true ? "ibus" : "fcitx5";
  }
  readonly property var setup: InputSources.methodSetup(root.framework, false)
  readonly property var legacy: InputSources.methodSetup(root.framework, true).env.slice(root.setup.env.length)

  readonly property bool shown: SettingsManager.configValueAt("Input.keyboard.method.enabled") === true && !root.managed && root.setup.command !== ""

  spacing: Widget.spacing

  Component.onCompleted: DependencyManager.check(["fcitx5", "ibus-daemon"])

  StyledText {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    text: I18n.tr("axiom doesn't write your compositor's config in this mode, so it doesn't start {0} or set what apps need to type with it. Add these yourself.", root.framework)
  }

  StyledText {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    textColor: Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-1)
    text: I18n.tr("The session's environment (for example ~/.config/environment.d/input-method.conf, or your compositor's own environment settings):")
  }

  CodeLine {
    text: root.setup.env.map(e => e.name + "=" + e.value).join("\n")
  }

  StyledText {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    textColor: Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-1)
    text: I18n.tr("Started with the compositor (its autostart, exec-once or spawn-at-startup):")
  }

  CodeLine {
    text: root.setup.command
  }

  StyledText {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    textColor: Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-2)
    text: I18n.tr("Only if an X11 or older app can't type with it, also {0}: on Wayland they can break typing in GTK apps.", root.legacy.map(e => e.name + "=" + e.value).join(" "))
  }

  StyledText {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    textColor: Theme.foregroundAlt
    textSize: Appearance.fontSizeBy(-2)
    text: I18n.tr("Electron apps (VS Code, Discord, Obsidian, …) type with an input method only when started with --enable-wayland-ime: no variable turns it on.")
  }
}
