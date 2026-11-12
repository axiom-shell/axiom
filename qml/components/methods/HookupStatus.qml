pragma Singleton
import QtQuick

// What a theme integration's hookup (IntegrationHookupManager's targets)
// says: whether it's done and the status chip's word and tone, shared by the
// hookup panel and the settings card's header. No file access, processes or
// services.
// I18n.tr("Off") I18n.tr("Checking") I18n.tr("Set up") I18n.tr("Not set up") I18n.tr("Copy the text")
QtObject {
  id: root

  // Whether every target Apply can do is done (false until checked, and for
  // an integration that's only copied)
  function done(targets) {
    const doable = (targets ?? []).filter(t => !t.copyOnly && !t.skipped);
    return doable.length > 0 && doable.every(t => t.done);
  }

  // { state, word, tone }: `word` is English (I18n.tr it), `tone` is
  // "success", "warning" or "" (muted)
  function of(enabled, targets) {
    const rows = targets ?? [];
    if (!enabled)
      return {
        "state": "off",
        "word": "Off",
        "tone": ""
      };
    if (rows.length === 0)
      return {
        "state": "checking",
        "word": "Checking",
        "tone": ""
      };
    if (root.done(rows))
      return {
        "state": "done",
        "word": "Set up",
        "tone": "success"
      };
    if (!rows.some(t => !t.copyOnly && !t.skipped))
      return {
        "state": "copy",
        "word": "Copy the text",
        "tone": ""
      };
    const pending = rows.some(t => !t.copyOnly && !t.skipped && !t.done && (t.conflicts ?? []).length === 0);
    return {
      "state": pending ? "todo" : "partial",
      "word": "Not set up",
      "tone": pending ? "warning" : ""
    };
  }
}
