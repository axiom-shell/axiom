pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.content.base

// Bar editor: the selected bar's five sections as a strip, laid out as
// the bar lays them out (BarLayout.layoutSections: the ends hug the ends,
// the center stays centered), each a lane of draggable widget chips. A
// top or bottom bar's can be stacked instead (a column, as a side bar's). Above
// it, how the running bar fits on each screen it's on.
Item {
  id: root

  required property var dragLayer

  readonly property bool vertical: root.dragLayer.vertical
  property string _pendingZone: ""

  // The selected bar as it's running, one report per screen
  readonly property var reports: BarManager.liveReports()
  // Per screen, the names of the widgets hidden there for want of room
  readonly property var crowded: root.reports.map(report => ({
        "screen": report.screen,
        "names": [].concat(...Object.keys(report.hidden).map(zone => report.hidden[zone].map(index => root.dragLayer.shortLabel(BarManager.selectedBar()?.widgets?.[zone]?.[index]?.type ?? ""))))
      })).filter(screen => screen.names.length > 0)
  readonly property string fitText: {
    if (BarManager.selectedBar()?.enabled === false)
      return I18n.tr("Turned off");
    if (root.reports.length === 0)
      return "";
    if (root.crowded.length === 0)
      return I18n.tr("Fits {0}", root.reports.map(report => report.screen).join(", "));
    return root.crowded.map(screen => I18n.tr("No room on {0} for {1}", screen.screen, screen.names.join(", "))).join(" · ");
  }

  // The lanes in bar order (as they're created), for their lengths
  property var _lanes: []
  readonly property real stripPad: Widget.padding / 2
  readonly property var slots: {
    if (root._lanes.length < 5)
      return [];
    return BarLayout.layoutSections(root._lanes.map(lane => lane.naturalLength), root._lanes.map(lane => lane.minLength), root.vertical ? strip.height : strip.width, root.stripPad, Widget.spacing, BarManager.selectedBar()?.lockCenter ?? false);
  }

  implicitHeight: column.implicitHeight + Widget.padding * 2

  TypePickerPopup {
    id: addPopup
    types: LibraryOrder.sorted(BarsConfig.libraryWidgetTypes, type => I18n.tr(type.label))
    parent: root
    placeholderText: I18n.tr("Search widgets")
    onTypeSelected: type => BarManager.addWidget(root._pendingZone, type)
  }

  Card {
    color: Theme.background
    border.color: Theme.border

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.margins: Widget.padding
      spacing: Widget.spacing

      CardHeader {
        title: I18n.tr("Widgets")
        dirty: BarManager.isDirty
        onSave: BarManager.saveChanges()
        onReset: BarManager.resetChanges()

        // A top or bottom bar's sections across the page, or stacked
        FlatIconButton {
          visible: !root.dragLayer.barVertical
          iconText: root.dragLayer.stacked ? "view_column" : "view_agenda"
          iconColor: root.dragLayer.stacked ? Theme.accent : Theme.foregroundAlt
          tooltipText: root.dragLayer.stacked ? I18n.tr("Lay the sections out across the page") : I18n.tr("Stack the sections down the side")
          onClicked: EditsManager.setBarStacked(!root.dragLayer.stacked)
        }
      }

      StyledText {
        visible: root.fitText !== ""
        Layout.fillWidth: true
        text: root.fitText
        textColor: root.crowded.length > 0 ? Theme.warning : Theme.foreground
        opacity: root.crowded.length > 0 ? 1 : 0.6
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.WordWrap
      }

      StyledText {
        Layout.fillWidth: true
        opacity: 0.6
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.WordWrap
        text: I18n.tr("Drag widgets to arrange them, across sections too. Click one to edit it: the bar outlines it. Changes show on the bar as you make them; Save keeps them.")
      }

      // The bar
      Rectangle {
        id: strip
        Layout.fillWidth: true
        Layout.fillHeight: root.vertical
        Layout.topMargin: Widget.spacing / 2
        Layout.preferredHeight: root.vertical ? -1 : Math.max(0, ...root._lanes.map(lane => lane.depth)) + root.stripPad * 2
        radius: Widget.radius
        color: Theme.backgroundAlt

        Repeater {
          model: root.dragLayer.zones

          onItemAdded: (index, item) => {
            const lanes = root._lanes.slice();
            lanes.splice(index, 0, item);
            root._lanes = lanes;
          }
          onItemRemoved: (index, item) => {
            root._lanes = root._lanes.filter(lane => lane !== item);
          }

          delegate: SectionLane {
            id: lane
            required property var modelData
            required property int index
            readonly property var slot: root.slots[lane.index] ?? {
              "offset": 0,
              "extent": 0
            }

            x: root.vertical ? root.stripPad : lane.slot.offset
            y: root.vertical ? lane.slot.offset : root.stripPad
            width: root.vertical ? strip.width - root.stripPad * 2 : lane.slot.extent
            height: root.vertical ? lane.slot.extent : strip.height - root.stripPad * 2
            dragLayer: root.dragLayer
            vertical: root.vertical
            reports: root.reports
            zone: lane.modelData.key
            title: lane.modelData.label
            onAddRequested: anchor => {
              root._pendingZone = lane.modelData.key;
              addPopup.openAt(anchor);
            }
          }
        }
      }
    }
  }
}
