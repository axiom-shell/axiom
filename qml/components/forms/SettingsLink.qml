pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable

// i18n: keys from the schema (titles, categories) and view labels
// A link to where something else is set: a setting on the settings page
// (`setting`, a key path: opens its card and outlines its row) or another
// overlay page (`page`, a view type, or "Layouts:lockscreen": see
// OverlayManager.followPageLink). Named from what it leads to unless
// `text` is set. Followed as a link, so the navigator offers the way back.
// Hidden when the setting has no card (hidden by the compositor, say) or
// the page isn't in the overlay (`available`).
Item {
  id: root

  // A key path ("Appearance.font.size") or a section ("BarStyle")
  property string setting: ""
  // Or a page link ("Themes", "Layouts:greeter")
  property string page: ""
  property string text: ""

  readonly property var target: root.setting !== "" ? SettingsManager.locate(root.setting) : null
  readonly property string label: {
    if (root.text !== "")
      return root.text;
    if (root.target)
      return I18n.tr("{0} in {1}", I18n.tr(root.target.title), I18n.tr(root.target.category));
    return root.page !== "" ? OverlayManager.pageLinkLabel(root.page) : "";
  }

  signal followed

  function follow() {
    if (root.target)
      SettingsManager.openSetting(root.setting, true);
    else if (root.page !== "")
      OverlayManager.followPageLink(root.page);
    root.followed();
  }

  // Whether it leads anywhere (a host that hides it on a condition of its
  // own binds `visible` to this as well)
  readonly property bool available: root.target !== null || (root.setting === "" && root.page !== "" && OverlayManager.pageLinkAvailable(root.page))

  visible: root.available
  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight

  RowLayout {
    id: content
    spacing: Widget.spacing / 2

    StyledIcon {
      text: root.target ? "settings" : OverlayManager.pageLinkIcon(root.page)
      textColor: Theme.accent
      textSize: Appearance.fontSizeBy(-1)
    }

    StyledText {
      Layout.fillWidth: true
      text: root.label
      textColor: Theme.accent
      textSize: Appearance.fontSizeBy(-1)
      font.underline: area.containsMouse
      elide: Text.ElideRight
    }

    StyledIcon {
      text: "arrow_forward"
      textColor: Theme.accent
      textSize: Appearance.fontSizeBy(-1)
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.follow()
  }
}
