pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.compositor
import qs.components.forms
import qs.components.reusable

// A bind's flags in words, one switch row each (the inspector's "When it
// fires"): a flag the compositor can't do is greyed out, saying why
FieldGroup {
  id: root

  // The bind's fields (KeybindManager.editor.binds[i])
  property var bind: ({})

  // A flag's row was switched, to `value`
  signal flagSet(string flag, bool value)

  title: I18n.tr("When it fires")

  Repeater {
    // [flag, title, description, the capability it needs or ""]
    model: [["repeating", I18n.tr("Repeat while held"), I18n.tr("Fires again and again while the key stays down, as volume keys do."), ""], ["locked", I18n.tr("Works while locked"), I18n.tr("Also fires on the lock screen."), ""], ["release", I18n.tr("Fire on release"), I18n.tr("Fires when the key is let go rather than pressed."), "releaseBinds"]]

    delegate: SwitchRow {
      id: flag
      required property var modelData
      // Greyed out, saying why, where the compositor can't do it; a flag
      // already on (a bind merged from another compositor) can still be
      // turned off (SwitchRow's rule)
      readonly property bool allowed: flag.modelData[3] === "" || CompositorManager.supports[flag.modelData[3]] === true

      label: flag.modelData[1]
      description: flag.modelData[2]
      unavailableReason: flag.allowed ? "" : CompositorManager.unsupportedNote(flag.modelData[3])
      checked: root.bind[flag.modelData[0]] === true
      onToggled: newValue => root.flagSet(flag.modelData[0], newValue)
    }
  }
}
