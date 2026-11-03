pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui

// The links under a form row or an inspector (`x-link`: { setting } or
// { page }, or a list of them), one SettingsLink each, hidden while none
// of them shows.
ColumnLayout {
  id: root

  // A schema's `x-link`, as written (one link or a list), or undefined
  property var links

  readonly property var _links: [].concat(root.links ?? [])

  // Whether any link shows, worked out as SettingsLink does: not from its
  // height (a hidden layout isn't laid out) or `visible` (false while an
  // ancestor is hidden), so a host can size itself by it
  readonly property bool shows: root._links.some(link => link.setting ? SettingsManager.locate(link.setting) !== null : OverlayManager.pageLinkAvailable(link.page ?? ""))
  visible: root.shows
  spacing: Widget.spacing / 2

  Repeater {
    model: root._links

    delegate: SettingsLink {
      required property var modelData
      Layout.fillWidth: true
      setting: modelData.setting ?? ""
      page: modelData.page ?? ""
    }
  }
}
