pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.core
import qs.components.reusable

// One line atop the settings page while dev mode is on (SettingsContent):
// which tree and checkout run, and on which config. A click opens the
// Development category (turning the developer options on first)
Notice {
  id: root
  status: "accent"
  clickable: true
  spinning: DevManager.building
  icon: DevManager.building ? "progress_activity" : DevManager.buildFailed ? "error" : "code"
  text: {
    const parts = [I18n.tr("Dev mode"), Paths.shortenHome(DevManager.tree)];
    if (DevManager.checkout !== "")
      parts.push(DevManager.checkout);
    parts.push(DevManager.active ? I18n.tr("dev config") : I18n.tr("live config until the dev build runs"));
    return parts.filter(part => part !== "").join(" · ");
  }
  onClicked: DevManager.openDevelopment()
}
