pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable
import qs.components.content.parts
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
    case "inFunction":
      return I18n.tr("it's made inside a function");
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
    case "paired":
      return I18n.tr("it goes with a call on the same key that stays");
    case "crashed":
      return I18n.tr("the merge failed ({0})", entry.detail);
    }
    return entry.detail || String(entry.reason ?? "");
  }

  Component.onDestruction: KeybindManager.editor.stopRecording()

  // Carries rows within their section
  InlineDragLayer {
    id: carrier
    accepts: (target, drag) => target.targetKind === "bindSection" && target.takes(drag.index)
    onDropped: (drag, target, index) => target.dropAt(drag.index, index)
  }

  // Whether the notice block has anything to show
  readonly property bool showRemoveConflicts: !(KeybindManager.editor.canMerge && KeybindManager.editor.mergeableCount > 0) && KeybindManager.editor.userConflicts.length > 0
  readonly property bool showMerge: KeybindManager.editor.canMerge && KeybindManager.editor.mergeableCount > 0
  readonly property bool hasNotices: CompositorConfigManager.lastMerge !== null || KeybindManager.editor.issueCount > 0 || root.showRemoveConflicts || root.showMerge || KeybindManager.editor.undoText !== ""

  // The merge note, the issues and the undo strip, in that order
  Surface {
    visible: root.hasNotices
    tone: "sunken"
    Layout.fillWidth: true
    implicitHeight: notices.implicitHeight + Widget.padding

    ColumnLayout {
      id: notices
      anchors.fill: parent
      anchors.margins: Widget.padding / 2
      spacing: Widget.spacing

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
        visible: KeybindManager.editor.issueCount > 0 || root.showRemoveConflicts || root.showMerge
        Layout.fillWidth: true

        StyledLabel {
          text: KeybindManager.editor.issueCount > 0 ? I18n.tr("{0} with issues", KeybindManager.editor.issueCount) : ""
          role: "caption"
          tone: "warning"
          overflow: "line"
          Layout.fillWidth: true
        }

        StyledTextButton {
          visible: root.showRemoveConflicts
          implicitHeight: Widget.height
          iconText: "delete_sweep"
          text: I18n.tr("Remove {0} binds your compositor config also has", KeybindManager.editor.userConflicts.length)
          onClicked: KeybindManager.editor.removeUserConflicts()
        }

        // Managed mode merges them instead
        SettingsLink {
          id: modeLink
          visible: modeLink.available && root.showRemoveConflicts
          setting: "Compositor.mode"
        }

        // Managed mode: the user's binds move in instead
        StyledTextButton {
          visible: root.showMerge
          enabled: !CompositorConfigManager.merging
          implicitHeight: Widget.height
          iconText: "merge"
          text: I18n.tr("Merge {0} binds from your compositor config", KeybindManager.editor.mergeableCount)
          onClicked: KeybindManager.editor.mergeUserBinds()
        }
      }

      // Undo for the last removal, preset or pause of several binds
      RowLayout {
        visible: KeybindManager.editor.undoText !== ""
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledIcon {
          text: "history"
          tone: "accent"
        }

        StyledLabel {
          text: KeybindManager.editor.undoText
          overflow: "line"
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
          onClicked: KeybindManager.editor.dismissUndo()
        }
      }
    }
  }

  // Nothing yet: how to start
  EmptyState {
    visible: KeybindManager.editor.binds.length === 0
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: Widget.padding
    icon: "keyboard"
    text: I18n.tr("No binds yet")
    hint: I18n.tr("Add one, or start from a preset.")
    actionText: I18n.tr("Add bind")
    onTriggered: KeybindManager.editor.addAndStartRecording({})
  }

  StyledText {
    visible: KeybindManager.editor.binds.length > 0 && KeybindManager.page.visibleIndices.length > 0 && (KeybindManager.page.editQuery.trim() !== "" || KeybindManager.page.editFiltering)
    text: I18n.tr("Showing {0} of {1}", KeybindManager.page.visibleIndices.length, KeybindManager.editor.binds.length)
    role: "caption"
    tone: "muted"
    Layout.fillWidth: true
  }

  // A search or filter matched nothing
  EmptyState {
    visible: KeybindManager.editor.binds.length > 0 && KeybindManager.page.visibleIndices.length === 0 && (KeybindManager.page.editQuery.trim() !== "" || KeybindManager.page.editFiltering)
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: Widget.padding
    icon: "search_off"
    text: KeybindManager.page.editQuery.trim() !== "" ? I18n.tr("No binds match \"{0}\"", KeybindManager.page.editQuery.trim()) : I18n.tr("No keybinds match the filters")
    actionText: I18n.tr("Clear")
    onTriggered: {
      KeybindManager.page.editQuery = "";
      KeybindManager.page.clearEditFilters();
    }
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
