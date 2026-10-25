pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts

// One row of the Keybinds editor's list: a bind, or a numbered run of
// binds (BindGroups) folded into one. Its switch pauses or resumes it; a
// tap selects a bind for the inspector, or unfolds a run. While every bind
// shows, a bind can be carried to another place in its section.
StyledContainer {
  id: root

  // The bind indices it shows: one, or a run's by number
  required property var indices
  property var dragLayer: null
  // Scrolls the list to an item
  property var scrollTo: null
  // Under its unfolded run
  property bool nested: false

  readonly property bool isRun: root.indices.length > 1
  readonly property int bindIndex: root.indices[0] ?? -1
  readonly property var bind: KeybindManager.binds[root.bindIndex] ?? ({})
  readonly property string runKey: root.isRun ? BindGroups.runKey(root.bind) : ""
  readonly property bool expanded: root.isRun && KeybindManager.expandedRuns[root.runKey] === true
  readonly property bool selected: !root.isRun && KeybindManager.selectedIndex === root.bindIndex
  readonly property bool paused: root.indices.every(i => KeybindManager.binds[i]?.paused === true)
  readonly property var issues: [].concat(...root.indices.map(i => KeybindManager.issues[i] ?? []))
  readonly property bool hasError: root.issues.some(issue => issue.level === "error")
  readonly property bool hasWarning: KeybindManager.hasIssue(root.issues)
  readonly property bool changed: root.indices.some(i => KeybindManager.changedBinds[i] === true)
  readonly property var parts: KeyNames.split(root.bind.key)
  readonly property color ink: root.selected ? Theme.background : Theme.foreground
  readonly property bool hovered: hover.hovered
  // Its own label (less a "Section:" prefix), else its action's
  readonly property string label: {
    if (root.isRun)
      return BindActions.defaultLabel(Object.assign({}, root.bind, {
        "argument": BindGroups.runNumbers(KeybindManager.binds, root.indices)
      }));
    return KeybindManager.bindLabel(root.bind);
  }
  readonly property string actionLabel: KeybindManager.actionLabels[root.bind.action] ?? String(root.bind.action ?? "")

  Layout.fillWidth: true
  Layout.leftMargin: root.nested ? Widget.padding * 2 : 0
  implicitHeight: Widget.height + Widget.padding / 2
  backgroundColor: root.selected ? Theme.accent : Qt.alpha(Theme.backgroundHighlight, root.hovered || area.dragged ? 1 : 0)
  borderWidth: root.hasError && !root.selected ? 1 : 0
  borderColor: Theme.error

  ColorGlide on color {
    duration: Appearance.animFast
  }

  HoverHandler {
    id: hover
  }

  // Centred when asked for, unfolding its run first (its rows, built
  // then, find the ask in KeybindManager.revealIndex)
  function reveal() {
    if (!root.isRun && root.scrollTo)
      Qt.callLater(() => {
        root.scrollTo(root);
        KeybindManager.revealDone(root.bindIndex);
      });
  }

  Component.onCompleted: {
    if (!root.isRun && KeybindManager.revealIndex === root.bindIndex)
      root.reveal();
  }

  Connections {
    target: KeybindManager

    function onRevealRequested(index) {
      if (!root.indices.includes(index))
        return;
      if (root.isRun && !root.expanded)
        KeybindManager.toggleRun(root.runKey);
      root.reveal();
    }
  }

  DragArea {
    id: area
    anchors.fill: parent
    dragEnabled: root.dragLayer !== null && !root.isRun && KeybindManager.reorderable
    dragLayer: dragEnabled ? root.dragLayer : null
    payload: ({
        "kind": "bind",
        "index": root.bindIndex,
        "label": root.label
      })
    onTapped: {
      if (root.isRun)
        KeybindManager.toggleRun(root.runKey);
      else
        KeybindManager.selectBind(root.selected ? -1 : root.bindIndex, false);
    }
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Widget.padding / 2
    anchors.rightMargin: Widget.padding / 2
    spacing: Widget.spacing

    // On while bound; off while paused
    StyledSwitch {
      checkable: false
      checked: !root.paused
      implicitHeight: Widget.smallHeight
      Layout.alignment: Qt.AlignVCenter
      onClicked: KeybindManager.setPaused(root.indices, !root.paused)
    }

    // The combo, as keycaps
    RowLayout {
      Layout.preferredWidth: Math.max(Widget.height * 6, root.width * 0.3)
      Layout.maximumWidth: Layout.preferredWidth
      spacing: Widget.spacing / 2
      clip: true
      opacity: root.paused ? 0.5 : 1

      Repeater {
        model: root.parts.mods

        delegate: KeyCap {
          required property string modelData
          text: KeyNames.modifierLabel(modelData)
        }
      }

      KeyCap {
        visible: root.parts.key !== ""
        text: root.isRun ? BindGroups.runKeys(KeybindManager.binds, root.indices) : KeybindManager.displayKey(root.parts.key)
      }

      StyledText {
        visible: root.parts.key === ""
        text: KeybindManager.recordingIndex === root.bindIndex ? I18n.tr("Press a combo…") : I18n.tr("No key")
        textColor: root.selected ? root.ink : Theme.warning
        textSize: Appearance.fontSizeBy(-1)
      }

      Item {
        Layout.fillWidth: true
      }
    }

    StyledIcon {
      text: root.isRun ? (root.expanded ? "unfold_less" : "unfold_more") : KeybindManager.actionIcon(root.bind.action)
      textColor: root.selected ? root.ink : Theme.accent
      opacity: root.paused ? 0.5 : 1
      Layout.preferredWidth: Appearance.fontSize * 1.5
    }

    StyledText {
      text: root.label || root.actionLabel
      textColor: root.ink
      font.bold: root.selected
      font.strikeout: root.paused
      opacity: root.paused ? 0.5 : 1
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    // The action, when the label doesn't say it
    StyledText {
      visible: root.label !== "" && root.label !== root.actionLabel && root.width > Widget.height * 14
      text: root.isRun ? I18n.tr("{0} binds", root.indices.length) : root.actionLabel
      textColor: root.ink
      opacity: 0.5
      textSize: Appearance.fontSizeBy(-2)
      elide: Text.ElideRight
      Layout.maximumWidth: root.width * 0.25
    }

    // Flags that are on
    Repeater {
      model: [["repeating", "repeat", I18n.tr("Repeats while held")], ["locked", "lock", I18n.tr("Works while locked")], ["release", "keyboard_capslock", I18n.tr("Fires on release")]].filter(flag => root.bind[flag[0]] === true)

      delegate: StyledIcon {
        required property var modelData
        text: modelData[1]
        textColor: root.ink
        opacity: 0.6
        textSize: Appearance.fontSizeBy(-1)
      }
    }

    StyledIcon {
      visible: root.hasWarning
      text: root.hasError ? "error" : "warning"
      textColor: root.selected ? root.ink : (root.hasError ? Theme.error : Theme.warning)
      textSize: Appearance.fontSize
    }

    UnsavedDot {
      shown: root.changed
      onAccent: root.selected
    }

    SquareIconButton {
      visible: !root.isRun
      size: Widget.height - Widget.px(6)
      iconText: "close"
      tooltipText: I18n.tr("Remove")
      iconColor: root.ink
      backgroundColor: "transparent"
      hoverColor: Theme.error
      opacity: root.hovered || root.selected ? 1 : 0
      onClicked: KeybindManager.removeBind(root.bindIndex)
    }
  }
}
