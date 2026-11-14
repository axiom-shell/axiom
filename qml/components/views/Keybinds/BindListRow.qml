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
ListEntryRow {
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
  readonly property var bind: KeybindManager.editor.binds[root.bindIndex] ?? ({})
  readonly property string runKey: root.isRun ? BindGroups.runKey(KeybindManager.actionTable, root.bind) : ""
  readonly property bool expanded: root.isRun && KeybindManager.page.expandedRuns[root.runKey] === true
  readonly property bool paused: root.indices.every(i => KeybindManager.editor.binds[i]?.paused === true)
  // Not bound now, by its "Only when" (paused says so itself)
  readonly property bool idle: !root.paused && root.indices.every(i => KeybindManager.editor.held[i] !== true)
  readonly property string condition: KeybindManager.conditionText(root.bind)
  readonly property var issues: [].concat(...root.indices.map(i => KeybindManager.editor.issues[i] ?? []))
  readonly property bool hasError: root.issues.some(issue => issue.level === "error")
  readonly property bool hasWarning: KeybindManager.editor.hasIssue(root.issues)
  readonly property var parts: KeyNames.split(root.bind.key)
  // Its own label (less a "Section:" prefix), else its action's (`label`)
  readonly property string ownLabel: {
    if (root.isRun)
      return BindActions.defaultLabel(KeybindManager.actionTable, Object.assign({}, root.bind, {
        "argument": BindGroups.runNumbers(KeybindManager.editor.binds, root.indices)
      }));
    return KeybindManager.bindLabel(root.bind);
  }
  readonly property string actionLabel: KeybindManager.actionLabels[root.bind.action] ?? String(root.bind.action ?? "")

  Layout.leftMargin: root.nested ? Widget.padding * 2 : 0
  Layout.preferredHeight: Widget.height + Widget.padding / 2
  selected: !root.isRun && KeybindManager.editor.selectedIndex === root.bindIndex
  changed: root.indices.some(i => KeybindManager.editor.changedBinds[i] === true)
  label: root.ownLabel || root.actionLabel
  // A run shows its fold state
  icon: root.isRun ? (root.expanded ? "unfold_less" : "unfold_more") : KeybindManager.actionIcon(root.bind.action)
  // Paused and idle read faint; a paused bind's name is also struck through
  dimmed: root.paused || root.idle
  strikeout: root.paused
  // The action, when the label doesn't say it
  subtitle: root.ownLabel !== "" && root.ownLabel !== root.actionLabel && root.width > Widget.textPx(448) ? (root.isRun ? I18n.tr("{0} binds", root.indices.length) : root.actionLabel) : ""
  issue: root.hasWarning ? (root.hasError ? "error" : "warning") : ""
  issueTip: KeybindManager.editor.issueTip(root.indices)
  escapeClears: true
  border.width: root.hasError && !root.selected ? Style.hairline : 0
  border.color: Style.error

  onClicked: root.isRun ? KeybindManager.page.toggleRun(root.runKey) : KeybindManager.editor.selectBind(root.selected ? -1 : root.bindIndex, false)
  onRemoveRequested: {
    if (!root.isRun)
      KeybindManager.editor.removeBind(root.bindIndex);
  }
  onEscapePressed: KeybindManager.editor.selectBind(-1, false)

  // A run never drags
  dragArea.dragLayer: root.dragLayer !== null && !root.isRun && KeybindManager.page.reorderable ? root.dragLayer : null
  dragArea.payload: ({
      "kind": "bind",
      "index": root.bindIndex,
      "label": root.label
    })

  // Centred when asked for, unfolding its run first (its rows, built
  // then, find the ask in KeybindManager.editor.revealIndex)
  function reveal() {
    if (!root.isRun && root.scrollTo)
      Qt.callLater(() => {
        root.scrollTo(root);
        KeybindManager.editor.revealDone(root.bindIndex);
      });
  }

  Component.onCompleted: {
    if (!root.isRun && KeybindManager.editor.revealIndex === root.bindIndex)
      root.reveal();
  }

  Connections {
    target: KeybindManager.editor

    function onRevealRequested(index) {
      if (!root.indices.includes(index))
        return;
      if (root.isRun && !root.expanded)
        KeybindManager.page.toggleRun(root.runKey);
      root.reveal();
    }
  }

  leading: [
    // On while bound; off while paused
    StyledSwitch {
      id: pauseSwitch
      compact: true
      checkable: false
      checked: !root.paused
      Layout.alignment: Qt.AlignVCenter
      onClicked: KeybindManager.editor.setPaused(root.indices, !root.paused)
      Keys.onTabPressed: root._tabFrom(pauseSwitch, true)
      Keys.onBacktabPressed: root._tabFrom(pauseSwitch, false)
    },
    // The combo, as keycaps: one width in every row, so every icon and
    // label start at one x
    RowLayout {
      Layout.minimumWidth: Math.max(Widget.textPx(192), Math.round(root.width * 0.3))
      Layout.preferredWidth: Layout.minimumWidth
      Layout.maximumWidth: Layout.minimumWidth
      spacing: Widget.spacing / 2
      clip: true
      opacity: root.paused || root.idle ? Style.opacityDisabled : 1

      Repeater {
        model: root.parts.mods

        delegate: KeyCap {
          required property string modelData
          text: KeyNames.modifierLabel(modelData)
        }
      }

      KeyCap {
        visible: root.parts.key !== ""
        text: root.isRun ? BindGroups.runKeys(KeybindManager.editor.binds, root.indices) : KeybindManager.displayKey(root.parts.key)
      }

      StyledLabel {
        visible: root.parts.key === ""
        text: KeybindManager.editor.recordingIndex === root.bindIndex ? I18n.tr("Press a combo…") : I18n.tr("No key")
        role: "caption"
        textColor: root.selected ? root.ink : Style.warningText
      }

      Item {
        Layout.fillWidth: true
      }
    }
  ]

  badges: [
    // Its "Only when", and whether that holds now
    TipIcon {
      visible: root.condition !== ""
      text: "filter_alt"
      tip: root.idle ? I18n.tr("Only when: {0}. Not bound now.", root.condition) : I18n.tr("Only when: {0}", root.condition)
      textColor: root.inkMuted
      size: "sm"
    },
    // Flags that are on
    Repeater {
      model: [["repeating", "repeat", I18n.tr("Repeats while held")], ["locked", "lock", I18n.tr("Works while locked")], ["release", "keyboard_capslock", I18n.tr("Fires on release")]].filter(flag => root.bind[flag[0]] === true)

      delegate: TipIcon {
        required property var modelData
        text: modelData[1]
        tip: modelData[2]
        textColor: root.inkMuted
        size: "sm"
      }
    }
  ]

  RowAction {
    row: root
    danger: true
    iconText: "close"
    tooltipText: I18n.tr("Remove")
    visible: !root.isRun
    onClicked: KeybindManager.editor.removeBind(root.bindIndex)
  }
}
