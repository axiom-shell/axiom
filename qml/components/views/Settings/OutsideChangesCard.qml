pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.services.system
import qs.components.reusable
import qs.components.methods

// Settings page, General (a category card, wide): what axiom changed
// outside its own folders (the footprint ledger,
// docs/dev/backend/footprint.md), grouped by the setting that caused it,
// each with its status and an Undo that takes out only axiom's own change,
// and Undo all (not the system's own choices, not what axiom only inferred).
// Its chip says how many, in the warning color while the compositor mode is
// detached (axiom stopping leaves them).
FoldingCard {
  id: root

  // The settings group key it folds under, from SettingsContent
  property string foldKey: "General:OutsideChanges"

  readonly property var groups: Footprint.groups(FootprintManager.rows)
  // Headers and rows in one list, for the ListView
  readonly property var entries: {
    let out = [];
    for (const group of root.groups) {
      out.push({
        "kind": "header",
        "owner": group.owner
      });
      out = out.concat(group.rows.map(row => ({
            "kind": "row",
            "row": row
          })));
    }
    return out;
  }
  // id of the row (or "all") waiting for its confirmation
  property string confirming: ""

  // I18n.tr("None")
  // I18n.tr("{0} changes", count)
  status: FootprintManager.count === 0 ? I18n.tr("None") : I18n.tr("{0} changes", FootprintManager.count)
  statusColor: CompositorConfig.mode === "detached" && FootprintManager.count > 0 ? Theme.warning : Theme.foregroundAlt
  collapsed: SettingsManager.isCollapsed(root.foldKey)
  onToggled: SettingsManager.setCollapsed(root.foldKey, !root.collapsed)

  // A group's name: its setting's title, else the path ("Compositor lines" for none)
  function groupTitle(owner) {
    if (owner === "")
      // I18n.tr("Compositor lines")
      return I18n.tr("Compositor lines");
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

  StyledText {
    text: I18n.tr("Files and settings axiom changed outside its own folders. Undo takes out only axiom's own change.")
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  RowLayout {
    visible: FootprintManager.count > 0
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      visible: root.confirming === "all"
      text: I18n.tr("Undo all skips the system's own choices and what axiom only inferred. Undo all?")
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    Item {
      visible: root.confirming !== "all"
      Layout.fillWidth: true
    }

    StyledTextButton {
      visible: root.confirming === "all"
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Cancel")
      onClicked: root.confirming = ""
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      text: I18n.tr("Undo all")
      onClicked: {
        if (root.confirming !== "all") {
          root.confirming = "all";
          return;
        }
        root.confirming = "";
        FootprintManager.undoAll();
      }
    }
  }

  // An unbounded list: a ListView, as tall as its rows
  ListView {
    id: list
    Layout.fillWidth: true
    implicitHeight: contentHeight
    interactive: false
    spacing: Widget.spacing
    model: root.entries
    delegate: Loader {
      id: entry
      required property var modelData
      width: list.width
      sourceComponent: entry.modelData.kind === "header" ? headerLine : rowLine

      Component {
        id: headerLine
        StyledText {
          text: root.groupTitle(entry.modelData.owner)
          font.bold: true
          color: Theme.foregroundAlt
        }
      }

      Component {
        id: rowLine
        ColumnLayout {
          id: line
          readonly property var row: entry.modelData.row
          readonly property string note: root.outcomeText(line.row.id)
          width: list.width
          spacing: Widget.spacing / 2

          RowLayout {
            Layout.fillWidth: true
            spacing: Widget.spacing

            StyledText {
              text: FootprintManager.labelOf(line.row)
              elide: Text.ElideMiddle
              Layout.fillWidth: true
            }

            StatusChip {
              visible: line.row.inferred === true
              text: I18n.tr("Inferred")
            }

            StatusChip {
              visible: line.row.status === "changed"
              text: I18n.tr("Changed since")
              color: Theme.warning
            }

            StatusChip {
              visible: line.row.status === "gone"
              text: I18n.tr("Gone")
            }

            StatusChip {
              visible: line.row.system === true
              text: I18n.tr("System")
            }

            StyledTextButton {
              visible: root.confirming !== line.row.id
              implicitHeight: Widget.height - Widget.px(4)
              text: I18n.tr("Undo")
              onClicked: {
                if (line.row.inferred === true) {
                  root.confirming = line.row.id;
                  return;
                }
                FootprintManager.undo([line.row.id]);
              }
            }
          }

          RowLayout {
            visible: root.confirming === line.row.id
            Layout.fillWidth: true
            spacing: Widget.spacing

            StyledText {
              text: I18n.tr("axiom found this without a record of writing it. Undo anyway?")
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            StyledTextButton {
              implicitHeight: Widget.height - Widget.px(4)
              text: I18n.tr("Cancel")
              onClicked: root.confirming = ""
            }

            StyledTextButton {
              implicitHeight: Widget.height - Widget.px(4)
              text: I18n.tr("Undo")
              onClicked: {
                root.confirming = "";
                FootprintManager.undo([line.row.id], true);
              }
            }
          }

          StyledText {
            visible: line.note !== ""
            text: line.note
            color: Theme.warning
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }
      }
    }
  }
}
