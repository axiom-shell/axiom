pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.reusable

// One OSD level bar: a system's bar (an `exposes` entry with part "bar")
// drawn from its state ({ level, muted, icon, available }). An entry
// naming a `design` is drawn by that file of its system's folder
// (Paths.osdDesignUrl: "<Type>/design/<File>", loaded by URL and kept handed
// its `entry`, `orientation` and `showPercent`: Audio's VolumeBar, which
// reads and sets its service itself); else a StyledVolumeBar, its drag
// and scroll and its icon's click handed to the watcher (setLevel,
// iconClicked). Left out while its state isn't `available` (Brightness
// on a monitor with no controller) or, without a design, has no level.
// With `highlight` (its system selected in the settings' preview) it's
// outlined in the accent.
Item {
  id: root

  // Its system (an OSDSystemHost), its `exposes` entry and its state now
  // (an Item's own `state` is taken)
  property var system: null
  property var entry: ({})
  readonly property var levelState: root.system?.snapshot?.[root.entry.key]
  // The system's item ({ type, …its settings }) and the OSD's screen
  readonly property var options: root.system?.options ?? ({})
  readonly property var screen: root.system?.screen ?? null
  // The OSD's own settings: bars run vertically, levels shown as numbers
  property bool vertical: true
  property bool showPercent: true
  // Outlined: its system is selected in the settings' preview
  property bool highlight: false
  readonly property int orientation: root.vertical ? Qt.Vertical : Qt.Horizontal

  readonly property string design: root.entry.design ?? ""
  readonly property bool shown: root.levelState?.available !== false && (root.design !== "" || root.levelState?.level !== undefined)

  visible: root.shown
  implicitWidth: root.shown ? (root.design !== "" ? designLoader.implicitWidth : plain.implicitWidth) : 0
  implicitHeight: root.shown ? (root.design !== "" ? designLoader.implicitHeight : plain.implicitHeight) : 0

  // Its design's file, loaded anew only as it changes
  readonly property string _designUrl: root.design !== "" && root.system ? Paths.osdDesignUrl(root.system.type, root.design) : ""

  Loader {
    id: designLoader
    anchors.fill: parent
    source: root._designUrl
  }
  Binding {
    target: designLoader.item
    property: "entry"
    value: root.entry
    when: designLoader.item !== null
  }
  Binding {
    target: designLoader.item
    property: "orientation"
    value: root.orientation
    when: designLoader.item !== null
  }
  Binding {
    target: designLoader.item
    property: "showPercent"
    value: root.showPercent
    when: designLoader.item !== null
  }

  StyledVolumeBar {
    id: plain
    anchors.fill: parent
    visible: root.design === ""
    orientation: root.orientation
    showPercent: root.showPercent
    scrollStep: OSDConfig.scrollStep
    volumeLevel: root.levelState?.level ?? 0
    isMuted: root.levelState?.muted === true
    iconSource: root.levelState?.icon || root.entry.icon || ""
    iconClickable: root.levelState?.muted !== undefined
    iconTip: root.levelState?.muted === true ? I18n.tr("Unmute") : I18n.tr("Mute")
    onVolumeChanged: newVolume => root.system?.watch?.setLevel(root.entry.key, newVolume)
    onIconClicked: root.system?.watch?.iconClicked(root.entry.key)
  }

  // The preview's outline
  Rectangle {
    anchors.fill: parent
    visible: root.highlight && root.shown
    z: 1
    radius: Widget.radius
    color: "transparent"
    border.width: Widget.px(2)
    border.color: Theme.accent
  }
}
