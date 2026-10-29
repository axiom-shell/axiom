pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable

// One action of the keybinds reference, keys first: its key combos
// (alternatives separated by a slash; a folded direction set as one
// keycap), its action's icon (a person for the user's own binds), its
// label, and a warning where it holds the key of an axiom bind that was
// skipped. An axiom bind's row opens it in the editor.
Item {
  id: root

  // { label, combos: [{ mods, keys, cluster? }], axiom, user, ids, action,
  // overrides } (KeybindManager.keybindings)
  required property var bind
  // The modifiers its section's sub-group shows above it, left out of its
  // first combo
  property var groupMods: []
  // The key column's width (the widest in the section), or -1 for its own
  property real keyWidth: -1
  readonly property real keyImplicitWidth: keys.implicitWidth

  readonly property bool compact: KeybindManager.page.refDensity === "compact"
  readonly property bool glyphs: KeybindManager.page.refGlyphs
  readonly property int bindIndex: root.bind.axiom ? KeybindManager.editor.bindIndexFor(root.bind.ids) : -1
  readonly property bool editable: root.bindIndex >= 0

  signal editRequested(int bindIndex)

  Layout.fillWidth: true
  implicitWidth: line.implicitWidth + Widget.padding
  implicitHeight: line.implicitHeight + (root.compact ? 2 : Widget.spacing)

  Rectangle {
    anchors.fill: parent
    radius: Widget.radius / 2
    color: Qt.alpha(Theme.backgroundHighlight, root.editable && area.containsMouse ? 0.6 : 0)

    ColorGlide on color {
      duration: Appearance.animFast
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: root.editable
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.editRequested(root.bindIndex)
  }

  RowLayout {
    id: line
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Widget.padding / 2
    anchors.rightMargin: Widget.padding / 2
    anchors.verticalCenter: parent.verticalCenter
    spacing: Widget.spacing * 1.5

    Row {
      id: keys
      Layout.preferredWidth: root.keyWidth >= 0 ? root.keyWidth : implicitWidth
      spacing: Widget.spacing / 2

      Repeater {
        model: root.bind.combos

        delegate: Row {
          id: combo
          required property var modelData
          required property int index
          readonly property bool ownMods: combo.index > 0 || combo.modelData.mods.join("+") !== root.groupMods.join("+")
          // A folded direction set's alternatives, else each key alone
          readonly property var alternatives: combo.modelData.cluster ?? combo.modelData.keys.map(key => [key])
          anchors.verticalCenter: parent?.verticalCenter
          spacing: Widget.spacing / 2

          Slash {
            visible: combo.index > 0
          }

          ModifierCap {
            visible: combo.ownMods && combo.modelData.mods.length > 0
            anchors.verticalCenter: parent.verticalCenter
            mods: combo.modelData.mods
            glyphs: root.glyphs
            compact: root.compact
          }

          Repeater {
            model: combo.alternatives

            delegate: Row {
              id: alternative
              required property var modelData
              required property int index
              anchors.verticalCenter: parent?.verticalCenter
              spacing: Widget.spacing / 2

              Slash {
                visible: alternative.index > 0
              }

              KeyCap {
                visible: alternative.modelData.length === 1
                anchors.verticalCenter: parent.verticalCenter
                text: alternative.modelData[0] ?? ""
                compact: root.compact
              }

              KeyCluster {
                visible: alternative.modelData.length > 1
                anchors.verticalCenter: parent.verticalCenter
                keys: alternative.modelData
                compact: root.compact
              }
            }
          }
        }
      }
    }

    StyledIcon {
      text: root.bind.action ? KeybindManager.actionIcon(root.bind.action) : (root.bind.user ? "person" : "keyboard")
      textColor: root.bind.action ? Theme.accent : Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-1)
      opacity: root.bind.action ? 1 : 0.6
    }

    StyledText {
      text: root.bind.label || I18n.tr("No description")
      opacity: root.bind.label ? 1 : 0.5
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    IssueIcon {
      visible: root.bind.overrides !== ""
      tip: I18n.tr("Axiom's \"{0}\" is skipped: this bind holds its key", root.bind.overrides)
      textSize: Appearance.fontSizeBy(-1)
    }
  }

  component Slash: StyledText {
    anchors.verticalCenter: parent.verticalCenter
    text: "/"
    opacity: 0.4
  }
}
