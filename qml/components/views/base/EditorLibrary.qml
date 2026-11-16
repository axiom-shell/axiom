pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.content.base

// An editor's library of things to add (the bar editor's widgets, the layouts
// editor's modules, a custom widget's elements): a CardHeader (`title`,
// `icon`), a faint `caption` saying how to add one and a TypeLibrary of the
// `types` ({ type, label, group }, the schema's labels) with its A–Z / By
// category choice kept in EditsManager. `delegate` builds a tile per type
// (given `modelData`) at `tileWidth`; `groups` are the schema's group order,
// `groupable: false` drops the switch (types with no groups), `minColumns`
// and `fitsContent` as the TypeLibrary's.
ColumnLayout {
  id: root

  required property var types
  property string title: ""
  property string icon: ""
  property string caption: ""
  property var groups: []
  property bool groupable: true
  property int minColumns: 1
  property real minTileWidth: Appearance.fontSize * 14
  property bool fitsContent: false
  property Component delegate
  readonly property real tileWidth: library.tileWidth

  Layout.fillWidth: true
  spacing: Widget.spacing

  CardHeader {
    visible: root.title !== ""
    icon: root.icon
    title: root.title
    showActions: false
  }

  StyledText {
    Layout.fillWidth: true
    visible: root.caption !== ""
    text: root.caption
    role: "caption"
    tone: "muted"
    overflow: "wrap"
  }

  TypeLibrary {
    id: library
    Layout.fillWidth: true
    Layout.fillHeight: !root.fitsContent
    Layout.topMargin: Widget.spacing / 2
    types: root.types
    groups: root.groups
    groupable: root.groupable
    grouped: EditsManager.libraryGrouped
    fitsContent: root.fitsContent
    minColumns: root.minColumns
    minTileWidth: root.minTileWidth
    delegate: root.delegate
    // Schema keys (labels, group names)
    labelOf: type => I18n.tr(type.label)
    headingOf: name => name ? I18n.tr(name) : I18n.tr("Other")
    onGroupingChosen: grouped => EditsManager.setLibraryGrouped(grouped)
  }
}
