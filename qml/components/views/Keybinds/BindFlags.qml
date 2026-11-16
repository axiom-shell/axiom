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

    delegate: FormRow {
      id: flag
      required property var modelData
      required property int index
      readonly property bool on: root.bind[flag.modelData[0]] === true
      // Greyed out, saying why, where the compositor can't do it; a flag
      // already on (a bind merged from another compositor) can still be
      // turned off
      readonly property bool allowed: flag.modelData[3] === "" || CompositorManager.supports[flag.modelData[3]] === true
      enabled: flag.allowed || flag.on
      opacity: flag.allowed ? 1 : Style.opacityDisabled
      first: flag.index === 0
      hoverable: true
      bodyHeight: flagSwitch.implicitHeight
      onRowClicked: flagSwitch.activate()

      SchemaSwitch {
        id: flagSwitch
        width: parent.width
        label: flag.modelData[1]
        description: flag.allowed ? flag.modelData[2] : CompositorManager.unsupportedNote(flag.modelData[3])
        checked: flag.on
        onToggled: newValue => root.flagSet(flag.modelData[0], newValue)
      }
    }
  }
}
