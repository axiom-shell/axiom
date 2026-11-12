pragma Singleton
import QtQuick

// What the uninstall dialog (Settings › General's "Remove axiom from this
// system", docs/dev/backend/uninstall.md) shows of the daemon's plan: the
// actions grouped by step in the order they run, the questions that apply to
// it (a switch is shown only when there is something to decide) with their
// defaults, and the answers the dialog sends. No file access, processes or
// services.
QtObject {
  id: root

  // The steps a plan's actions come under, in the order they run
  readonly property var steps: ["managed", "ledger", "lines", "session", "files", "portal", "secrets", "folders"]

  // The answers' defaults: keep what the user could want back, undo what
  // axiom found without a record, put back no system choices, restart the
  // portal
  readonly property var defaults: ({
      "keepConfig": true,
      "keepUserContent": true,
      "keepSecrets": true,
      "undoInferred": true,
      "restoreSystem": false,
      "restartPortal": true
    })

  // The plan's actions by step, in run order, empty steps left out:
  // [{ step, actions: [{ kind, path, status, owner, count, asks, ... }] }]
  function groups(plan) {
    const out = [];
    for (const step of root.steps) {
      const actions = (plan?.actions ?? []).filter(action => action.step === step);
      if (actions.length > 0)
        out.push({
          "step": step,
          "actions": actions
        });
    }
    return out;
  }

  // The questions that apply, in the order they are asked:
  // [{ field, answer, count }]. `field` is the Answers name the daemon
  // uses (KeepConfig), `answer` the key of `defaults`, `count` how many
  // things it is about (0: not a count)
  function questions(plan) {
    const counts = plan?.counts ?? {};
    const out = [
      {
        "field": "KeepConfig",
        "answer": "keepConfig",
        "count": 0
      },
      {
        "field": "KeepUserContent",
        "answer": "keepUserContent",
        "count": 0
      }
    ];
    if ((counts.secrets ?? 0) > 0 || counts.secretsFile === true)
      out.push({
        "field": "KeepSecrets",
        "answer": "keepSecrets",
        "count": counts.secrets ?? 0
      });
    if ((counts.inferred ?? 0) > 0)
      out.push({
        "field": "UndoInferred",
        "answer": "undoInferred",
        "count": counts.inferred
      });
    if ((counts.system ?? 0) > 0)
      out.push({
        "field": "RestoreSystem",
        "answer": "restoreSystem",
        "count": counts.system
      });
    if (counts.portal === true)
      out.push({
        "field": "RestartPortal",
        "answer": "restartPortal",
        "count": 0
      });
    return out;
  }

  // The answers to send: the defaults, over which `chosen` (answer key ->
  // boolean) says what the user switched
  function answers(chosen) {
    const out = {};
    for (const key of Object.keys(root.defaults))
      out[key] = chosen && chosen[key] !== undefined ? chosen[key] === true : root.defaults[key];
    return out;
  }

  // Whether the dialog may start: the plan is there, nothing it can't
  // remove stands in the way (the login screen is removed first), and
  // another axiom isn't running (`running` lists displays other than this
  // one's; this one quits itself)
  function canStart(plan, greeterBusy) {
    return plan !== null && plan !== undefined && !plan.greeter && greeterBusy !== true && (plan.running ?? []).length === 0;
  }
}
