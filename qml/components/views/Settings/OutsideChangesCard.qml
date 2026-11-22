pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.services.system
import qs.components.reusable
import qs.components.forms
import qs.components.views.base
import qs.components.methods

// Settings page, General (a category card, wide): what axiom changed
// outside its own folders (the footprint ledger,
// docs/dev/backend/footprint.md), grouped by the setting that caused it,
// each with its status and an Undo that takes out only axiom's own change,
// and Undo all (not the system's own choices, not what axiom only inferred).
// Its chip says how many, in the warning color while the compositor mode is
// detached (axiom stopping leaves them). At the bottom, "Remove axiom from
// this system…" opens the uninstall's confirm step (RemoveAxiomPanel,
// docs/dev/backend/uninstall.md).
FoldingCard {
  id: root

  // The settings group key it folds under, from SettingsContent
  property string foldKey: "General:OutsideChanges"

  readonly property var groups: Footprint.groups(FootprintManager.rows)
  // id of the row (or "all") waiting for its confirmation
  property string confirming: ""
  // The uninstall's confirm step is open
  property bool removing: false

  // I18n.tr("None")
  // I18n.tr("{0} changes", count)
  status: FootprintManager.count === 0 ? I18n.tr("None") : I18n.tr("{0} changes", FootprintManager.count)
  statusTone: CompositorConfig.mode === "detached" && FootprintManager.count > 0 ? "warning" : "neutral"
  collapsed: SettingsManager.isCollapsed(root.foldKey)
  onToggled: SettingsManager.setCollapsed(root.foldKey, !root.collapsed)

  // A group's name: its setting's title, else the path ("Compositor lines" for none)
  function groupTitle(owner) {
    if (owner === "")
      // I18n.tr("Compositor lines")
      return I18n.tr("Compositor lines");
    if (owner === "DefaultApps")
      return I18n.tr("Default apps");
    const schema = SettingsManager.schemaAt(owner.split("."));
    return schema?.title ? I18n.tr(schema.title) : owner;
  }

  // The undo outcome of a row, as a line
  function outcomeText(id) {
    const result = FootprintManager.results[id];
    if (!result)
      return "";
    if (result.outcome === "changed")
      return I18n.tr("Changed since: left as it is");
    if (result.outcome === "needsRunning")
      return I18n.tr("Start fcitx5 to undo this");
    if (result.outcome === "failed" || result.outcome === "refused")
      return result.detail;
    return "";
  }

  Component.onCompleted: FootprintManager.refresh()

  StatusLine {
    text: I18n.tr("Files and settings axiom changed outside its own folders. Undo takes out only axiom's own change.")
    Layout.fillWidth: true
  }

  ConfirmLine {
    visible: FootprintManager.count > 0 && root.confirming === "all"
    question: I18n.tr("Undo all skips the system's own choices and what axiom only inferred. Undo all?")
    keepText: I18n.tr("Cancel")
    confirmText: I18n.tr("Undo all")
    onKept: root.confirming = ""
    onConfirmed: {
      root.confirming = "";
      FootprintManager.undoAll();
    }
  }

  RowLayout {
    visible: FootprintManager.count > 0 && root.confirming !== "all"
    Layout.fillWidth: true
    spacing: Widget.spacing

    Item {
      Layout.fillWidth: true
    }

    StyledTextButton {
      text: I18n.tr("Undo all")
      onClicked: root.confirming = "all"
    }
  }

  // An unbounded list: a ListView, as tall as its rows
  ListView {
    id: list
    Layout.fillWidth: true
    implicitHeight: contentHeight
    interactive: false
    spacing: Widget.spacing
    model: root.groups
    // A job a group (its rows are the build)
    delegate: StreamedLoader {
      id: slot
      required property var modelData
      width: list.width
      rise: false
      label: "outside changes group"

      sourceComponent: ListSection {
        id: section
        readonly property var modelData: slot.modelData
        title: root.groupTitle(section.modelData.owner)

        Repeater {
          model: section.modelData.rows

          delegate: ColumnLayout {
            id: line
            required property var modelData
            readonly property var row: line.modelData
            readonly property string note: root.outcomeText(line.row.id)
            Layout.fillWidth: true
            spacing: Widget.spacing / 2

            RowLayout {
              Layout.fillWidth: true
              spacing: Widget.spacing

              StyledText {
                text: FootprintManager.labelOf(line.row)
                overflow: "line"
                elide: Text.ElideMiddle // style-exempt: middle elides an identifier, keeping its end
                Layout.fillWidth: true
              }

              Loader {
                active: line.row.inferred === true
                visible: active
                sourceComponent: StatusChip {
                  text: I18n.tr("Inferred")
                }
              }

              Loader {
                active: line.row.status === "changed"
                visible: active
                sourceComponent: StatusChip {
                  text: I18n.tr("Changed since")
                  tone: "warning"
                }
              }

              Loader {
                active: line.row.status === "gone"
                visible: active
                sourceComponent: StatusChip {
                  text: I18n.tr("Gone")
                }
              }

              Loader {
                active: line.row.system === true
                visible: active
                sourceComponent: StatusChip {
                  text: I18n.tr("System")
                }
              }

              StyledTextButton {
                visible: root.confirming !== line.row.id
                text: I18n.tr("Undo")
                onClicked: {
                  if (line.row.inferred === true || line.row.system === true) {
                    root.confirming = line.row.id;
                    return;
                  }
                  FootprintManager.undo([line.row.id]);
                }
              }
            }

            Loader {
              active: root.confirming === line.row.id
              visible: active
              Layout.fillWidth: true
              sourceComponent: ConfirmLine {
                question: line.row.inferred === true ? I18n.tr("axiom found this without a record of writing it. Undo anyway?") : I18n.tr("axiom changed this system default. Put it back?")
                keepText: I18n.tr("Cancel")
                confirmText: I18n.tr("Undo")
                onKept: root.confirming = ""
                onConfirmed: {
                  root.confirming = "";
                  FootprintManager.undo([line.row.id], true);
                }
              }
            }

            Loader {
              active: line.note !== ""
              visible: active
              Layout.fillWidth: true
              sourceComponent: StatusLine {
                text: line.note
                tone: "warning"
              }
            }
          }
        }
      }
    }
  }

  StyledSeparator {
    Layout.fillWidth: true
  }

  RowLayout {
    visible: !root.removing
    Layout.fillWidth: true
    spacing: Widget.spacing

    Item {
      Layout.fillWidth: true
    }

    StyledTextButton {
      iconText: "delete_forever"
      text: I18n.tr("Remove axiom from this system…")
      kind: "danger"
      onClicked: root.removing = true
    }
  }

  // Built only while open
  StreamedLoader {
    Layout.fillWidth: true
    wanted: root.removing
    always: true
    sourceComponent: RemoveAxiomPanel {
      onClosed: root.removing = false
    }
  }
}
