pragma Singleton
import QtQuick
import qs.services.core

// Reader for the CommunitySetups section: whether the community setups
// gallery is on, and where its catalog is (CommunitySetupsManager)
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.CommunitySetups

  readonly property bool enabled: _c.enabled
  // The catalog's index.json; its files are relative to it
  readonly property string indexUrl: _c.indexUrl
}
