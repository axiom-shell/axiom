pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.components.methods
import qs.components.reusable

// The Development category's second card (its `cards`): every setting the
// dev config and live differ on, which of them changed it since dev last
// took live over, and a copy either way (a dev-only setting, which the
// installed axiom doesn't have, can't go to live). Nothing merges by
// itself. Asked of axiom when shown and after each change, while a dev
// tree is set, dev mode on or off (DevManager.diff; rows labelled by
// methods/DevDiff)
FieldGroup {
  id: root

  // dev.config.diff's rows: [{ path, side, dev?, live?, devOnly }]
  property var rows: []
  // The config versions of the dev tree's and the install's schemas
  property var versions: ({})
  property bool loaded: false
  // A call is out: the buttons wait
  property bool busy: false
  // What the last action said: a refusal (`error`) or what it did
  property string message: ""
  property bool error: false

  readonly property var schema: ConfigManager.configSchema
  // There's a dev config to compare: a dev tree is set
  readonly property bool comparable: DevManager.tree !== ""

  // Asks axiom again
  function refresh() {
    if (!root.comparable) {
      root.rows = [];
      root.loaded = false;
      return;
    }
    DevManager.diff((error, result) => {
      root.loaded = !error;
      root._show(error ? null : result);
      if (error)
        root._said(error.message, true);
    });
  }

  // Shows a diff (null: none)
  function _show(diff) {
    root.rows = diff?.rows ?? [];
    root.versions = {
      "dev": diff?.devVersion ?? 0,
      "install": diff?.installVersion ?? 0
    };
  }

  function _said(text, isError) {
    root.message = text;
    root.error = isError;
  }

  // Copies one row's setting `to` "live" or "dev"
  function copy(row, to) {
    root.busy = true;
    DevManager.copy([row.path], to, (error, result) => {
      root.busy = false;
      if (error) {
        root._said(error.message, true);
        return;
      }
      root._show(result.diff);
      root._said(to === "live" ? I18n.tr("Copied to live.") : I18n.tr("Copied to dev."), false);
    });
  }

  // Brings live's changes over where dev left the setting alone
  function merge() {
    root.busy = true;
    DevManager.pull("merge", (error, result) => {
      root.busy = false;
      if (error) {
        root._said(error.message, true);
        return;
      }
      root._show(result.diff);
      const kept = result.conflicts?.length ?? 0;
      root._said(kept === 0 ? I18n.tr("Live changes brought over.") : kept === 1 ? I18n.tr("Live changes brought over; 1 setting changed in dev too kept its dev value.") : I18n.tr("Live changes brought over; {0} settings changed in dev too kept their dev values.", kept), false);
    });
  }

  // A row's setting, its titles from the dev schema
  function rowTitle(row) {
    return DevDiff.titleParts(root.schema, row.path).map(part => part.schema ? I18n.tr(part.text) : part.text).join(" › ");
  }

  Component.onCompleted: root.refresh()

  Connections {
    target: DevManager
    function onActiveChanged() {
      root.refresh();
    }
    function onTreeChanged() {
      root.refresh();
    }
    function onLiveChangedChanged() {
      root.refresh();
    }
  }

  // A setting saved in the running config (dev's, or live's with dev mode
  // off) changes the rows
  Connections {
    target: ConfigManager
    function onConfigChanged() {
      root.refresh();
    }
  }

  headerExtras: [
    StyledIconButton {
      visible: root.comparable
      iconText: "refresh"
      tooltipText: I18n.tr("Compare again")
      onClicked: root.refresh()
    }
  ]

  StyledText {
    visible: !root.comparable
    text: I18n.tr("Set a dev tree to compare its config with live.")
    opacity: 0.7
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // Live changed since dev last took it over
  RowLayout {
    visible: root.comparable && DevManager.liveChanged
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledText {
      text: I18n.tr("Live changed since dev last took it over.")
      textColor: Theme.warning
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    StyledTextButton {
      implicitHeight: Widget.height - Widget.px(4)
      enabled: !root.busy
      text: I18n.tr("Bring live changes over")
      iconText: "merge"
      onClicked: root.merge()
    }
  }

  // The install is of another config version: what moved since can't go
  StyledText {
    visible: root.comparable && root.loaded && root.versions.dev !== root.versions.install
    text: I18n.tr("The installed axiom's config is version {0}, the dev tree's {1}: a setting moved or reshaped between them can't be copied to live while they differ.", root.versions.install, root.versions.dev)
    textColor: Theme.warning
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  StyledText {
    visible: root.comparable && root.loaded && root.rows.length === 0
    text: I18n.tr("Dev and live agree on every setting.")
    opacity: 0.7
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  StyledText {
    visible: root.message !== ""
    text: root.message
    textColor: root.error ? Theme.error : Theme.foregroundAlt
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
  }

  // One row per setting; lists compare whole
  ListView {
    id: list
    visible: root.comparable && root.rows.length > 0
    Layout.fillWidth: true
    Layout.preferredHeight: Math.min(contentHeight, Widget.height * 14)
    clip: true
    spacing: Widget.spacing
    boundsBehavior: Flickable.StopAtBounds
    model: root.rows.length

    ScrollIndicator.vertical: ScrollIndicator {}

    delegate: Rectangle {
      id: entry
      required property int index
      readonly property var row: root.rows[index] ?? ({})

      width: ListView.view.width
      implicitHeight: entryColumn.implicitHeight + Widget.smallPadding * 2
      radius: Widget.radius
      color: Theme.backgroundAlt

      ColumnLayout {
        id: entryColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Widget.smallPadding
        spacing: Widget.spacing / 2

        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledLabel {
            text: root.rowTitle(entry.row)
            font.weight: Font.Medium
            elide: Text.ElideMiddle
            Layout.fillWidth: true
          }

          // I18n.tr("Changed in dev") I18n.tr("Changed in live") I18n.tr("Changed in both")
          StatusChip {
            text: I18n.tr(DevDiff.sideLabel(entry.row.side))
            color: entry.row.side === "both" ? Theme.warning : entry.row.side === "live" ? Theme.accent : Theme.success
          }

          StatusChip {
            visible: entry.row.devOnly === true
            text: I18n.tr("Dev only")
            color: Theme.foregroundAlt
          }
        }

        GridLayout {
          Layout.fillWidth: true
          columns: 3
          columnSpacing: Widget.spacing * 2
          rowSpacing: Widget.spacing / 2

          StyledText {
            text: I18n.tr("Dev")
            opacity: 0.7
          }
          StyledText {
            text: DevDiff.has(entry.row, "dev") ? DevDiff.valueText(entry.row, "dev") : I18n.tr("not set")
            opacity: DevDiff.has(entry.row, "dev") ? 1 : 0.6
            textFamily: "monospace"
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          StyledTextButton {
            implicitHeight: Widget.smallHeight
            enabled: !root.busy && DevDiff.toLive(entry.row)
            text: I18n.tr("To live")
            iconText: "arrow_forward"
            iconAfter: true
            tooltipText: DevDiff.toLive(entry.row) ? "" : I18n.tr("The installed axiom has no such setting, or one of another shape")
            onClicked: root.copy(entry.row, "live")
          }

          StyledText {
            text: I18n.tr("Live")
            opacity: 0.7
          }
          StyledText {
            text: DevDiff.has(entry.row, "live") ? DevDiff.valueText(entry.row, "live") : I18n.tr("not set")
            opacity: DevDiff.has(entry.row, "live") ? 1 : 0.6
            textFamily: "monospace"
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          StyledTextButton {
            implicitHeight: Widget.smallHeight
            enabled: !root.busy
            text: I18n.tr("To dev")
            iconText: "arrow_back"
            onClicked: root.copy(entry.row, "dev")
          }
        }
      }
    }
  }
}
