pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.services.core
import qs.services.session
import qs.components.reusable

// The Recommended setup list (RecommendedSetupManager): a switch per row,
// the reason a row can't be ticked, how each row's apply went, and Apply.
// Shared by the Compositor card and the onboarder's Welcome page. The list
// is plumbing: the rows, ticks and the run live in the manager.
ColumnLayout {
  id: root

  // Paths whose rows are ticked but not committed (the onboarder's compositor
  // mode, applied on Finish), and what to call with (path, value) for each
  // at Apply
  property var later: []
  property var choose: null
  // Show its own Apply button (the Welcome page has one of its own)
  property bool showApply: true

  // The rows by step, for the two the list gives extras to
  readonly property var _rows: RecommendedSetupManager.ids.map(id => RecommendedSetupManager.rows[id])
  readonly property var greeterRow: root._rows.find(row => row.step === "greeter")
  readonly property bool anyChecked: root._rows.some(row => row.checked)

  Layout.fillWidth: true
  spacing: Widget.spacing

  Component.onCompleted: RecommendedSetupManager.begin({
    "later": root.later,
    "choose": root.choose
  })

  // I18n.tr("Your compositor can't do this") I18n.tr("axiom won't take over this config")
  // I18n.tr("{0} isn't installed") I18n.tr("None of the apps axiom colors is installed")
  // I18n.tr("greetd or agreety isn't installed") I18n.tr("Needs sway or Hyprland to run in")
  // I18n.tr("Nothing to install from: axiom isn't a git clone or a package") I18n.tr("Checking...")
  function reasonText(row) {
    switch (row.reason) {
    case "unsupported":
      return I18n.tr("Your compositor can't do this");
    case "blocked":
      return I18n.tr("axiom won't take over this config");
    case "missing":
      return I18n.tr("{0} isn't installed", ScreenShareManager.portal?.package ?? "");
    case "noAxiomPortal":
      return I18n.tr("axiom's own portal file (axiom.portal) isn't installed: run axiom's install.sh again, or reinstall its package.");
    case "noApps":
      return I18n.tr("None of the apps axiom colors is installed");
    case "noGreetd":
      return I18n.tr("greetd or agreety isn't installed");
    case "noCompositor":
      return I18n.tr("Needs sway or Hyprland to run in");
    case "noClone":
      return I18n.tr("Nothing to install from: axiom isn't a git clone or a package");
    case "unknown":
      return I18n.tr("Checking...");
    }
    return "";
  }

  // I18n.tr("Applies when you finish") I18n.tr("Takes effect after the portal restarts or next login.")
  function noteText(row) {
    if (row.note === "later")
      return I18n.tr("Applies when you finish");
    if (row.note === "deferred")
      return I18n.tr("Takes effect after the portal restarts or next login.");
    return "";
  }

  // The chip's word: how the last Apply went, else whether it's on already
  // I18n.tr("Waiting") I18n.tr("Applying...") I18n.tr("Done") I18n.tr("Skipped") I18n.tr("Failed") I18n.tr("Already on")
  function chipText(row) {
    switch (row.state) {
    case "pending":
      return I18n.tr("Waiting");
    case "running":
      return I18n.tr("Applying...");
    case "done":
      return I18n.tr("Done");
    case "skipped":
      return I18n.tr("Skipped");
    case "failed":
      return I18n.tr("Failed");
    }
    return row.state === "idle" && row.done ? I18n.tr("Already on") : "";
  }

  function chipColor(row) {
    switch (row.state) {
    case "done":
      return Theme.success;
    case "failed":
      return Theme.error;
    case "running":
      return Theme.accent;
    case "idle":
      return row.done ? Theme.success : Theme.foregroundAlt;
    }
    return Theme.foregroundAlt;
  }

  // The apps row names the apps it's on for (their schema titles)
  // i18n: keys from the schema (integration titles)
  readonly property string appTitles: RecommendedSetupManager.appKeys.map(key => I18n.tr(ThemeManager.integrationTitle(key))).join(", ")

  Repeater {
    model: RecommendedSetupManager.ids

    delegate: RowLayout {
      id: item
      required property string modelData
      readonly property var row: RecommendedSetupManager.rows[item.modelData]
      // i18n: keys from the schema (the detail is a title or enum label)
      readonly property string detail: item.row.step === "apps" ? I18n.tr("On for {0}", root.appTitles) : item.row.detail !== "" ? I18n.tr(item.row.detail) : ""
      readonly property string problem: item.row.error !== "" ? item.row.error : root.reasonText(item.row)
      readonly property string note: root.noteText(item.row)
      readonly property bool restartable: item.row.step === "portal" && (item.row.note === "deferred" || item.row.state === "failed")

      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledSwitch {
        checked: item.row.checked
        enabled: item.row.available && !item.row.done && !RecommendedSetupManager.running
        onToggled: RecommendedSetupManager.setChecked(item.modelData, checked)
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        // i18n: keys from the schema (section titles and field titles)
        StyledLabel {
          Layout.fillWidth: true
          text: I18n.tr(item.row.label) + (item.detail !== "" ? " · " + item.detail : "")
          elide: Text.ElideRight
          textColor: item.row.available || item.row.done ? Theme.foreground : Theme.foregroundInactive
        }

        StyledText {
          visible: item.problem !== "" || item.note !== ""
          Layout.fillWidth: true
          text: item.problem !== "" ? item.problem : item.note
          textColor: item.row.state === "failed" ? Theme.error : Theme.foregroundInactive
          textSize: Appearance.fontSizeBy(-1)
          wrapMode: Text.WordWrap
        }

        StyledText {
          visible: item.restartable && item.problem !== ""
          Layout.fillWidth: true
          text: I18n.tr("Takes effect after the portal restarts or next login.")
          textColor: Theme.foregroundInactive
          textSize: Appearance.fontSizeBy(-1)
          wrapMode: Text.WordWrap
        }

        // What restarting costs
        StyledText {
          visible: item.restartable
          Layout.fillWidth: true
          text: I18n.tr("The portal reads its config as it starts: restart it once after applying. A share running now stops.")
          textColor: Theme.foregroundInactive
          textSize: Appearance.fontSizeBy(-1)
          wrapMode: Text.WordWrap
        }

        StyledTextButton {
          visible: item.restartable
          Layout.topMargin: Widget.spacing / 2
          implicitHeight: Widget.height - Widget.px(4)
          iconText: "restart_alt"
          text: I18n.tr("Restart the portal")
          onClicked: RecommendedSetupManager.restartPortal()
        }
      }

      StatusChip {
        visible: text !== ""
        text: root.chipText(item.row)
        color: root.chipColor(item.row)
      }
    }
  }

  StyledTextButton {
    visible: root.showApply
    enabled: root.anyChecked && !RecommendedSetupManager.running
    iconText: "verified"
    text: I18n.tr("Apply")
    onClicked: RecommendedSetupManager.apply()
  }

  GreeterSetup {
    visible: root.greeterRow !== undefined && (root.greeterRow.state === "done" || root.greeterRow.state === "failed")
    Layout.fillWidth: true
  }
}
