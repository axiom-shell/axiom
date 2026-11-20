pragma Singleton
import QtQuick

// The Claude usage rules, for the ClaudeUsage widget and module: which
// percent an account row shows and which account is the fullest. A row is
// ClaudeUsageManager.stateFor's { status, session, weekly, … } with its
// `label`; a metric is "session" or "weekly".
QtObject {
  id: root

  // The percent a row shows for a metric, -1 with none (no row, or still
  // pending)
  function percentOf(row, metric) {
    return (metric === "weekly" ? row?.weekly : row?.session)?.percent ?? -1;
  }

  // The row with the highest percent for a metric (the first on a tie), null
  // with no rows
  function fullest(rows, metric) {
    return rows.reduce((best, r) => best === null || root.percentOf(r, metric) > root.percentOf(best, metric) ? r : best, null);
  }
}
