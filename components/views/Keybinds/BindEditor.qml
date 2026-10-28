pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable
import qs.components.forms

// The Keybinds page's list of axiom's own binds (Keybinds.binds), the body
// of its left card: what the last merge did, the binds' issues, the strip
// to undo the last removal or preset, then the binds by section
// (BindSection). The selected bind is edited in the inspector
// (BindInspector); edits wait in KeybindEditor's draft until Save.
ColumnLayout {
  id: root

  // Scrolls the list so an item shows (the card's scrollTo)
  property var scrollTo: null

  spacing: Widget.spacing

  // A merge's reason code (backend/internal/compositor/binds) as
  // text, with its detail
  function reasonText(entry) {
    switch (entry.reason) {
    case "key":
      return I18n.tr("its key isn't plain text");
    case "function":
      return I18n.tr("it runs a Lua function");
    case "options":
      return I18n.tr("axiom binds don't have its options: {0}", entry.detail);
    case "shared":
      return I18n.tr("it's made in a shared module");
    case "notOnly":
      return I18n.tr("it isn't the only call on its line");
    case "statement":
      return I18n.tr("it's part of a larger statement");
    case "followed":
      return I18n.tr("something else follows it on its line");
    case "used":
      return I18n.tr("it's kept in {0}, which the file uses", entry.detail);
    case "unclosed":
      return I18n.tr("the call isn't closed");
    case "changed":
      return I18n.tr("the file changed");
    case "notUser":
      return I18n.tr("it isn't one of your files in user/");
    case "syntax":
      return I18n.tr("the file wouldn't parse without it ({0})", entry.detail);
    case "continued":
      return I18n.tr("it goes on over several lines");
    case "block":
      return I18n.tr("it's inside a bindsym { } block");
    case "io":
      return I18n.tr("the file couldn't be read or written ({0})", entry.detail);
    case "crashed":
      return I18n.tr("the merge failed ({0})", entry.detail);
    }
    return entry.detail || String(entry.reason ?? "");
  }

  Component.onDestruction: KeybindManager.editor.stopRecording()

  // Carries rows within their section. Takes no room: it's only the
  // coordinate space, and draws the carried row's label.
  DragLayer {
    id: carrier
    Layout.fillWidth: true
    Layout.preferredHeight: 0
    z: 10
    accepts: (target, drag) => target.targetKind === "bindSection" && target.takes(drag.index)
    onDropped: (drag, target, index) => target.dropAt(drag.index, index)
    onMoved: point => ghost.at = point

    StyledContainer {
      id: ghost
      property point at: Qt.point(0, 0)
      visible: carrier.dragging !== null
      x: ghost.at.x + Widget.spacing
      y: ghost.at.y - height / 2
      implicitWidth: ghostLabel.implicitWidth + Widget.padding * 2
      implicitHeight: Widget.height
      backgroundColor: Theme.accent

      StyledText {
        id: ghostLabel
        anchors.centerIn: parent
        text: carrier.dragging?.label ?? ""
        textColor: Theme.background
      }
    }
  }

  // What the last merge did, and what it left behind
  IssueList {
    readonly property var merge: CompositorConfigManager.lastMerge
    visible: merge !== null
    Layout.fillWidth: true
    issues: {
      if (!merge)
        return [];
      const name = file => file.split("/").pop();
      const found = [];
      if (merge.saveFailed)
        found.push({
          "level": "error",
          "text": I18n.tr("axiom's config couldn't be saved, so nothing moved")
        });
      else
        found.push({
          "level": "info",
          "text": merge.removed > 0 ? I18n.tr("Moved {0} binds into axiom and saved; the files they came from are backed up beside them", merge.moved) : I18n.tr("Moved {0} binds into axiom", merge.moved)
        });
      for (const moved of merge.remapped ?? [])
        found.push({
          "level": "info",
          "text": I18n.tr("{0} is on {1} now: axiom uses {2}", KeybindManager.actionLabels[moved.action] ?? moved.action, moved.to, moved.from)
        });
      for (const file of merge.tracked ?? [])
        found.push({
          "level": "info",
          "text": I18n.tr("{0} is in a git repository: commit or revert the change there", Paths.shortenHome(file))
        });
      for (const kept of merge.kept)
        found.push({
          "level": "warning",
          "text": I18n.tr("{0} stays in {1}: {2}", kept.key || "?", `${name(kept.file)}:${kept.line}`, root.reasonText(kept))
        });
      for (const failed of merge.failed)
        found.push({
          "level": "error",
          "text": failed.line > 0 ? I18n.tr("Left the bind at {0} where it is, and out of axiom's: {1}", `${name(failed.file)}:${failed.line}`, root.reasonText(failed)) : I18n.tr("Left the binds in {0} where they are, and out of axiom's: {1}", name(failed.file), root.reasonText(failed))
        });
      for (const error of merge.errors)
        found.push({
          "level": "warning",
          "text": error
        });
      return found;
    }
  }

  RowLayout {
    visible: KeybindManager.editor.issueCount > 0 || removeConflicts.visible || mergeButton.visible
    Layout.fillWidth: true

    StyledText {
      text: KeybindManager.editor.issueCount > 0 ? I18n.tr("{0} with issues", KeybindManager.editor.issueCount) : ""
      textColor: Theme.warning
      textSize: Appearance.fontSizeBy(-1)
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    StyledTextButton {
      id: removeConflicts
      visible: !(KeybindManager.editor.canMerge && KeybindManager.editor.mergeableCount > 0) && KeybindManager.editor.userConflicts.length > 0
      implicitHeight: Widget.height
      iconText: "delete_sweep"
      text: I18n.tr("Remove {0} binds your compositor config also has", KeybindManager.editor.userConflicts.length)
      onClicked: KeybindManager.editor.removeUserConflicts()
    }

    // Managed mode merges them instead
    SettingsLink {
      id: modeLink
      visible: modeLink.available && removeConflicts.visible
      setting: "Compositor.mode"
    }

    // Managed mode: the user's binds move in instead
    StyledTextButton {
      id: mergeButton
      visible: KeybindManager.editor.canMerge && KeybindManager.editor.mergeableCount > 0
      enabled: !CompositorConfigManager.merging
      implicitHeight: Widget.height
      iconText: "merge"
      text: I18n.tr("Merge {0} binds from your compositor config", KeybindManager.editor.mergeableCount)
      onClicked: KeybindManager.editor.mergeUserBinds()
    }
  }

  // Undo for the last removal, preset or pause of several binds
  StyledContainer {
    visible: KeybindManager.editor.undoText !== ""
    Layout.fillWidth: true
    implicitHeight: Widget.height + Widget.padding / 2
    backgroundColor: Theme.backgroundHighlight

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Widget.padding
      anchors.rightMargin: Widget.padding / 2
      spacing: Widget.spacing

      StyledIcon {
        text: "history"
        textColor: Theme.accent
      }

      StyledText {
        text: KeybindManager.editor.undoText
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      StyledTextButton {
        implicitHeight: Widget.height - Widget.px(4)
        iconText: "undo"
        text: I18n.tr("Undo")
        onClicked: KeybindManager.editor.undo()
      }

      SquareIconButton {
        size: Widget.height - Widget.px(4)
        iconText: "close"
        tooltipText: I18n.tr("Dismiss")
        backgroundColor: "transparent"
        onClicked: KeybindManager.editor.dismissUndo()
      }
    }
  }

  StyledText {
    visible: KeybindManager.editor.binds.length === 0
    text: I18n.tr("No binds yet. Add one, or start from a preset.")
    opacity: 0.6
    Layout.fillWidth: true
  }

  StyledText {
    visible: KeybindManager.page.editQuery.trim() !== "" || KeybindManager.page.editFiltering
    text: KeybindManager.page.visibleIndices.length > 0 ? I18n.tr("Showing {0} of {1}", KeybindManager.page.visibleIndices.length, KeybindManager.editor.binds.length) : KeybindManager.page.editQuery.trim() !== "" ? I18n.tr("No binds match \"{0}\"", KeybindManager.page.editQuery.trim()) : I18n.tr("No keybinds match the filters")
    opacity: 0.6
    textSize: Appearance.fontSizeBy(-2)
    Layout.fillWidth: true
  }

  Repeater {
    model: KeybindManager.page.editLayout

    delegate: BindSection {
      required property var modelData
      section: modelData
      dragLayer: carrier
      scrollTo: root.scrollTo
      Layout.topMargin: Widget.spacing
    }
  }
}
