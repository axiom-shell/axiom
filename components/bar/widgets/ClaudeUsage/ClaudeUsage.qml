pragma ComponentBehavior: Bound
import QtQuick

import qs.services.core
import qs.services.apps
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Claude plan usage from ClaudeUsageManager, for one or more Claude Code
// accounts (one per CLAUDE_CONFIG_DIR, from ClaudeUsageConfig). Shows the
// session or weekly limit's percent: the fullest account's, or every
// account's. Hovering lists every limit per account; right click fetches
// again, left click runs the click command.
BarIconWidget {
  id: root

  // One state per configured account, in the configured order, labelled as
  // configured
  readonly property var rows: ClaudeUsageConfig.accounts.map(a => Object.assign({}, ClaudeUsageManager.stateFor(a.configDir) ?? {
      "status": "pending"
    }, {
      "label": a.label || a.configDir
    }))

  function percentOf(row) {
    return (properties.metric === "weekly" ? row.weekly : row.session)?.percent ?? -1;
  }
  function abbreviation(row) {
    return rows.length > 1 ? String(row.label).charAt(0).toUpperCase() + " " : "";
  }
  function figure(row) {
    const p = percentOf(row);
    return abbreviation(row) + (p < 0 ? "–" : p + "%");
  }

  readonly property var fullest: rows.reduce((best, r) => best === null || percentOf(r) > percentOf(best) ? r : best, null)
  readonly property int maxPercent: fullest ? percentOf(fullest) : -1
  // Every shown account is behind (an expired token or a failed fetch)
  readonly property bool stale: rows.length > 0 && (properties.display === "all" ? rows.every(r => r.status !== "ok") : (fullest?.status ?? "") !== "ok")

  icon: properties.icon
  text: {
    if (rows.length === 0)
      return "–";
    if (properties.display === "all")
      return rows.map(r => figure(r)).join(" · ");
    return figure(properties.display === "first" ? rows[0] : fullest);
  }

  accentColor: Theme.resolveColor(maxPercent >= properties.criticalThreshold ? properties.criticalColor : maxPercent >= properties.warnThreshold ? properties.warnColor : properties.backgroundColor)
  dim: stale ? 0.6 : 1

  // Re-acquiring replaces the old request
  readonly property var usageRequest: ({
      "accounts": ClaudeUsageConfig.accounts,
      "interval": ClaudeUsageConfig.interval
    })
  onUsageRequestChanged: ClaudeUsageManager.acquire(root, usageRequest)
  Component.onCompleted: ClaudeUsageManager.acquire(root, usageRequest)
  Component.onDestruction: ClaudeUsageManager.release(root)

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: button => {
    if (button === Qt.RightButton)
      ClaudeUsageManager.refresh();
    else
      CommandManager.runDetached(root.properties.clickCommand);
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "ClaudeUsage"
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
    extraData: ({
        "accounts": ClaudeUsageConfig.accounts,
        "warnThreshold": root.properties.warnThreshold,
        "criticalThreshold": root.properties.criticalThreshold
      })
  }
}
