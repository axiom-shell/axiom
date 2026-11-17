pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.compositor
import qs.components.methods

// The keybinds reference as a keyboard: under the modifiers picked
// (`mods`), each key shows what it does (KeyMap.labels), coloured by whose
// bind it is. A click on one of axiom's opens it in the editor.
KeyboardMap {
  id: root

  // KeybindManager.keybindings, or some of them
  required property var sections

  readonly property var labels: KeyMap.labels(root.sections, root.mods)

  signal editRequested(int bindIndex)

  // The modifiers held, and chips to change them (the page's, shared with
  // the editor's key map); a Cheatsheet passes its own without chips
  mods: KeybindManager.page.keyMapMods
  showMods: true
  tall: true
  sourceOf: key => root.labels[key]?.source ?? ""
  toneFor: source => KeySourceTone.tone(source)
  legend: [["free", I18n.tr("Free")], ["axiom", I18n.tr("Axiom")], ["user", I18n.tr("Your compositor config")], ["both", I18n.tr("Both")]]
  labelOf: key => root.labels[key]?.label ?? ""
  iconOf: key => root.labels[key]?.action ? KeybindManager.actionIcon(root.labels[key].action) : ""
  clickableOf: key => KeybindManager.editor.bindIndexFor(root.labels[key]?.ids ?? []) >= 0
  onClicked: key => root.editRequested(KeybindManager.editor.bindIndexFor(root.labels[key].ids))
}
