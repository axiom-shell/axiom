pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.reusable
import qs.components.content.parts

// The Development category's first card (its `cards`): the dev tree (set
// or clear it), dev mode on or off, the dev build (rebuild, its log) and
// the dev config (replace it with live's copy) (DevManager)
FieldGroup {
  id: root

  // What axiom last answered a click with: a refusal's message, or ""
  property string message: ""

  readonly property bool failed: DevManager.lastBuild !== null && !DevManager.lastBuild.ok

  readonly property string statusLabel: {
    if (!DevManager.enabled)
      return I18n.tr("Off");
    if (DevManager.building)
      return I18n.tr("Building");
    if (root.failed)
      return I18n.tr("Build failed");
    return DevManager.active ? I18n.tr("Running") : I18n.tr("Waiting for the build");
  }

  readonly property color statusColor: {
    if (!DevManager.enabled)
      return Theme.foregroundAlt;
    if (root.failed)
      return Theme.error;
    if (DevManager.building)
      return Theme.accent;
    return DevManager.active ? Theme.success : Theme.warning;
  }

  // A refusal shows its message; anything else clears the last one
  function _answered(error) {
    root.message = error ? error.message : "";
  }

  function _setTree() {
    const path = treeEntry.text.trim();
    if (path === "")
      return;
    treeEntry.typed = false;
    DevManager.setTree(path, error => root._answered(error));
  }

  // The tree axiom has, pushed into the field unless it's being typed in
  function _showTree() {
    if (!treeEntry.input.activeFocus || !treeEntry.typed)
      treeEntry.text = Paths.shortenHome(DevManager.tree);
  }

  Component.onCompleted: root._showTree()

  Connections {
    target: DevManager
    function onTreeChanged() {
      treeEntry.typed = false;
      root._showTree();
    }
  }

  // "Copy live → dev" replaces every dev setting: pressed twice
  ConfirmGate {
    id: gate
  }

  headerExtras: [
    StatusChip {
      text: root.statusLabel
      color: root.statusColor
    }
  ]

  // The dev tree: any clone of axiom, which axiom checks
  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledTextEntry {
      id: treeEntry
      Layout.fillWidth: true
      placeholderText: I18n.tr("A clone of axiom, e.g. ~/dev/axiom")
      onAccepted: root._setTree()
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      enabled: treeEntry.text.trim() !== "" && Paths.expandHome(treeEntry.text.trim()) !== DevManager.tree
      text: I18n.tr("Set")
      onClicked: root._setTree()
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      enabled: DevManager.tree !== "" && !DevManager.enabled
      text: I18n.tr("Clear")
      tooltipText: DevManager.enabled ? I18n.tr("Turn dev mode off first") : ""
      onClicked: DevManager.clearTree(error => root._answered(error))
    }
  }

  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Widget.spacing * 2
    rowSpacing: Widget.spacing / 2

    StyledText {
      text: I18n.tr("Checkout")
      opacity: 0.7
    }
    StyledText {
      elide: Text.ElideRight
      text: DevManager.checkout || "—"
      textFamily: "monospace"
      Layout.fillWidth: true
    }

    StyledText {
      text: I18n.tr("Dev build")
      opacity: 0.7
    }
    StyledText {
      wrapMode: Text.WordWrap
      text: DevManager.tree === "" ? "—" : DevManager.buildFresh ? I18n.tr("Built from the tree as it is") : (DevManager.buildWhy || I18n.tr("Not built yet"))
      Layout.fillWidth: true
    }

    StyledText {
      text: I18n.tr("Dev config")
      opacity: 0.7
    }
    StyledText {
      elide: Text.ElideMiddle
      text: Paths.shortenHome(DevManager.configPath) || "—"
      textFamily: "monospace"
      Layout.fillWidth: true
    }

    StyledText {
      text: I18n.tr("Install tree")
      opacity: 0.7
    }
    StyledText {
      elide: Text.ElideMiddle
      text: Paths.shortenHome(DevManager.installTree) || "—"
      textFamily: "monospace"
      Layout.fillWidth: true
    }
  }

  StyledText {
    visible: text !== ""
    text: DevManager.tree !== "" && !DevManager.available ? DevManager.unavailable : ""
    textColor: Theme.warning
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // What opening the dev config noted (seeded from the defaults: live is
  // newer than the dev tree)
  StyledText {
    visible: DevManager.active && DevManager.configNote !== ""
    text: DevManager.configNote
    textColor: Theme.warning
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      enabled: DevManager.enabled || DevManager.tree !== ""
      text: DevManager.enabled ? I18n.tr("Turn off") : I18n.tr("Turn on")
      iconText: "power_settings_new"
      tooltipText: DevManager.tree === "" ? I18n.tr("Set a dev tree first") : ""
      onClicked: DevManager.setEnabled(!DevManager.enabled, error => root._answered(error))
    }

    StyledTextButton {
      visible: DevManager.enabled && DevManager.available
      enabled: !DevManager.building
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Rebuild")
      iconText: "refresh"
      onClicked: DevManager.rebuild(error => root._answered(error))
    }

    Item {
      Layout.fillWidth: true
    }

    // Only the dev image has the dev config open
    StyledTextButton {
      visible: DevManager.active
      implicitHeight: Widget.height - Widget.px(4)
      text: gate.armed === "replace" ? I18n.tr("Click again to replace the dev config") : I18n.tr("Copy live → dev")
      iconText: "content_copy"
      onClicked: {
        if (gate.pass("replace", true))
          DevManager.pull("replace", error => root._answered(error));
      }
    }
  }

  StyledText {
    visible: root.message !== ""
    text: root.message
    textColor: Theme.error
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // The last build's last lines
  CodeLine {
    visible: text !== ""
    text: (DevManager.lastBuild?.output ?? "").trim().split("\n").slice(-8).join("\n")
  }
}
