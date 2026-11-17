pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.services.session
import qs.services.system
import qs.components.reusable
import qs.components.forms
import qs.components.views.base
import qs.components.methods

// The confirm step of Settings › General's "Remove axiom from this system"
// (docs/dev/backend/uninstall.md), opened by OutsideChangesCard: what the
// daemon says an uninstall would do (grouped by step), the lines it leaves
// for you and the backups it keeps, the same questions `axiom uninstall`
// asks as switches (each with its default), and, while the login screen is
// installed, the step that removes it first (one admin prompt). Starting it
// closes axiom: the daemon runs the uninstall detached.
ColumnLayout {
  id: root

  signal closed

  // answer key -> boolean, what the user switched (the rest are defaults)
  property var chosen: ({})
  property bool starting: false

  readonly property var plan: UninstallManager.plan
  readonly property var groups: UninstallPlan.groups(root.plan)
  readonly property var questions: UninstallPlan.questions(root.plan)
  readonly property bool canStart: UninstallPlan.canStart(root.plan, GreeterManager.elevating) && !root.starting

  Layout.fillWidth: true
  spacing: Widget.spacing

  function stepTitle(step) {
    switch (step) {
    case "managed":
      return I18n.tr("Compositor configs given back");
    case "ledger":
      return I18n.tr("Changes undone");
    case "lines":
      return I18n.tr("Lines taken out of your configs");
    case "session":
      return I18n.tr("Left by an unclean stop");
    case "files":
      return I18n.tr("Files deleted");
    case "portal":
      return I18n.tr("Screen sharing");
    case "secrets":
      return I18n.tr("Saved passwords");
    default:
      return I18n.tr("Folders");
    }
  }

  // What an action does, worded here from its step and kind (the daemon
  // sends those and the data, never a sentence)
  function actionText(action, path) {
    switch (action.step) {
    case "managed":
      return I18n.tr("Give back the config axiom manages");
    case "ledger":
      switch (action.kind) {
      case "file":
        return I18n.tr("Delete the file axiom made");
      case "dir":
        return I18n.tr("Remove the folder axiom made");
      case "hookup":
        return I18n.tr("Take axiom's lines out of {0}", path);
      case "gsetting":
        return I18n.tr("Put back the setting");
      case "ini-groups":
        return I18n.tr("Put back the keys in {0}", path);
      case "marked-block":
        return I18n.tr("Remove axiom's block from {0}", path);
      case "fcitx-config":
        return I18n.tr("Put back the fcitx5 option");
      case "fcitx-group":
        return I18n.tr("Put back the fcitx5 input methods");
      case "mimeapps":
        return I18n.tr("Put back the default app");
      case "rebuild":
        return I18n.tr("Rebuild once the files are out");
      default:
        return I18n.tr("Leave the record of axiom's changes: it can't be read, so nothing is undone from it");
      }
    case "lines":
      return I18n.tr("Remove axiom's line from {0}", path);
    case "session":
      return I18n.tr("Undo what an unclean stop of axiom left");
    case "files":
      return I18n.tr("Delete");
    case "portal":
      return I18n.tr("Restart the screen-share portal (a share running ends)");
    case "secrets":
      return action.kind === "keyring" ? I18n.tr("Remove axiom's {0} items from the keyring", action.count) : I18n.tr("Delete the saved passwords file");
    default:
      switch (action.kind) {
      case "cache":
        return I18n.tr("Delete the cache");
      case "runtime":
        return I18n.tr("Delete the runtime files");
      case "data":
        return I18n.tr("Delete your notes, to-dos, themes, downloaded wallpapers and calendars");
      case "config":
        return I18n.tr("Delete the settings and saved setups");
      default:
        return I18n.tr("Delete the state (logs, dev builds, approvals)");
      }
    }
  }

  // A ledger row's status and owner, as a line
  function statusLine(action) {
    const parts = [];
    if (action.status === "present")
      parts.push(I18n.tr("Present"));
    else if (action.status === "changed")
      parts.push(I18n.tr("Changed since"));
    else if (action.status === "gone")
      parts.push(I18n.tr("Gone"));
    if ((action.owner ?? "") !== "")
      parts.push(action.owner);
    if (action.kind === "unreadable")
      parts.push(action.detail ?? "");
    return parts.join(", ");
  }

  function questionText(q) {
    switch (q.field) {
    case "KeepConfig":
      return I18n.tr("Keep your axiom settings (config.json, saved setups) in case you come back?");
    case "KeepUserContent":
      return I18n.tr("Keep your notes, to-dos, themes, downloaded wallpapers and calendars in {0}?", Paths.shortenHome(Paths.userDataPath.replace(/\/$/, "")));
    case "KeepSecrets":
      return q.count > 0 ? I18n.tr("Keep axiom's saved passwords and API keys in your keyring ({0})?", q.count) : I18n.tr("Keep axiom's saved passwords and API keys?");
    case "UndoInferred":
      return I18n.tr("Also undo {0} changes axiom found without a record of making them?", q.count);
    case "RestoreSystem":
      return I18n.tr("Also put back the default apps and input-method engines you set through axiom ({0})?", q.count);
    default:
      return I18n.tr("Restart the screen-share portal now? A share running ends.");
    }
  }

  function setChosen(key, value) {
    const next = Object.assign({}, root.chosen);
    next[key] = value;
    root.chosen = next;
  }

  Component.onCompleted: UninstallManager.refresh()

  // Once the login screen is gone, the plan no longer says it's there
  Connections {
    target: GreeterManager
    function onPhaseChanged() {
      if (GreeterManager.phase === "done")
        UninstallManager.refresh();
    }
  }

  StatusLine {
    text: I18n.tr("This takes axiom out of your home and session: it gives back your compositor config, undoes the changes listed above, and deletes axiom's files and folders. Your own configs and backups are never deleted.")
    Layout.fillWidth: true
  }

  StatusLine {
    visible: UninstallManager.error !== ""
    text: UninstallManager.error
    tone: "error"
    Layout.fillWidth: true
  }

  // The login screen is installed for the whole system: removed first
  IntroColumn {
    visible: root.plan !== null && root.plan !== undefined && !!root.plan.greeter
    Layout.fillWidth: true

    StatusLine {
      text: I18n.tr("axiom's login screen is installed for the whole system and stays after this. Remove it first (one admin prompt).")
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledText {
        visible: GreeterManager.lastError !== ""
        text: GreeterManager.lastError
        tone: "error"
        overflow: "wrap"
        Layout.fillWidth: true
      }

      Item {
        visible: GreeterManager.lastError === ""
        Layout.fillWidth: true
      }

      StyledTextButton {
        enabled: !GreeterManager.elevating
        iconText: "delete"
        text: GreeterManager.elevating ? I18n.tr("Removing now...") : I18n.tr("Uninstall the login screen first")
        onClicked: GreeterManager.uninstall()
      }
    }
  }

  StatusLine {
    visible: root.plan !== null && root.plan !== undefined && (root.plan.running ?? []).length > 0
    text: I18n.tr("axiom also runs on {0}: quit it there first.", (root.plan?.running ?? []).join(", "))
    tone: "warning"
    Layout.fillWidth: true
  }

  // What goes: an unbounded list, as tall as it is up to a limit; one
  // section a step
  ListView {
    id: list
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(list.contentHeight, Widget.px(280))
    clip: true
    ScrollIndicator.vertical: StyledScrollIndicator {}
    spacing: Widget.spacing
    model: root.groups
    delegate: ListSection {
      id: section
      required property var modelData
      width: list.width
      title: root.stepTitle(section.modelData.step)

      Repeater {
        model: section.modelData.actions

        delegate: ColumnLayout {
          id: action
          required property var modelData
          spacing: 0
          Layout.fillWidth: true

          StyledText {
            text: root.actionText(action.modelData, action.modelData.path ? Paths.shortenHome(action.modelData.path) : "")
            overflow: "line"
            elide: Text.ElideMiddle // style-exempt: middle elides an identifier, keeping its end
            Layout.fillWidth: true
          }

          StyledText {
            visible: root.statusLine(action.modelData) !== ""
            text: root.statusLine(action.modelData)
            role: "caption"
            overflow: "line"
            elide: Text.ElideMiddle // style-exempt: middle elides an identifier, keeping its end
            Layout.fillWidth: true
          }
        }
      }
    }
  }

  // Lines it isn't sure are its own, and what it keeps
  StatusLine {
    visible: (root.plan?.manual ?? []).length > 0
    text: I18n.tr("{0} lines it isn't sure are its own are left for you to remove by hand; the list is saved with the summary.", (root.plan?.manual ?? []).length)
    Layout.fillWidth: true
  }

  StatusLine {
    visible: (root.plan?.backups ?? []).length > 0
    text: I18n.tr("{0} backups of your files are kept and listed: delete them when you're sure.", (root.plan?.backups ?? []).length)
    Layout.fillWidth: true
  }

  // The questions, as switches (on: keep, or undo, as the text says)
  FormColumn {
    Layout.fillWidth: true

    Repeater {
      model: root.questions

      delegate: SwitchRow {
        id: question
        required property var modelData
        label: root.questionText(question.modelData)
        checked: root.chosen[question.modelData.answer] ?? UninstallPlan.defaults[question.modelData.answer]
        onToggled: newValue => root.setChosen(question.modelData.answer, newValue)
      }
    }
  }

  StatusLine {
    text: I18n.tr("axiom closes when this starts. A summary is saved to {0}.", UninstallManager.logPath)
    tone: "muted"
    Layout.fillWidth: true
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    Item {
      Layout.fillWidth: true
    }

    StyledTextButton {
      enabled: !root.starting
      text: I18n.tr("Cancel")
      onClicked: root.closed()
    }

    StyledTextButton {
      enabled: root.canStart
      iconText: "delete_forever"
      text: I18n.tr("Remove axiom")
      kind: "dangerPrimary"
      onClicked: {
        root.starting = true;
        UninstallManager.start(UninstallPlan.answers(root.chosen), ok => {
          if (!ok)
            root.starting = false;
        });
      }
    }
  }
}
