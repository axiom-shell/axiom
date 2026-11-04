pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.content.base

// Bar editor: the selected bar's three sections, each a lane of draggable
// widget chips that wrap (SectionLane), one row under another whatever
// the bar's edge. Its header has undo and redo, the drop order badges'
// switch, an Unsaved chip and the help in a "?" (Save and Discard are
// BarsPanel's); under it, how the running bar fits on each screen it's
// on, the widgets it has no room for as buttons selecting them, with
// Raise priority / Set max length for a selected one. A chip's right
// click opens its menu; while the board has focus (a chip clicked) it
// takes Delete, Ctrl+D, Alt+arrows, Escape and Ctrl+Z / Ctrl+Shift+Z /
// Ctrl+Y.
FocusScope {
  id: root

  required property var dragLayer

  property string _pendingZone: ""
  // Each chip shows its place in the order a crowded bar drops widgets in
  property bool showDropOrder: false

  // The selected bar as it's running, one report per screen
  readonly property var reports: BarManager.liveReports()
  // Per screen, the widgets ({zone, index}) hidden there for want of room
  readonly property var crowded: root.reports.map(report => ({
        "screen": report.screen,
        "widgets": [].concat(...Object.keys(report.hidden).map(zone => report.hidden[zone].map(index => ({
                "zone": zone,
                "index": index
              }))))
      })).filter(screen => screen.widgets.length > 0)
  readonly property bool turnedOff: BarManager.selectedBar()?.enabled === false
  // The narrowest screen the bar is on (the least room in all), whose
  // fit the lanes' meters show
  readonly property var narrowest: root._narrowestOf(root.reports)
  // The narrowest screen with no room for the selected widget, where its
  // actions make it fit (null when it fits everywhere)
  readonly property var selectedCrowdedOn: {
    const sel = BarManager.selectedWidget;
    return root._narrowestOf(root.reports.filter(report => (report.hidden[sel.zone] ?? []).includes(sel.index)));
  }
  // The length to cap the selected (elastic) widget at so its section
  // fits there, or 0 when no cap would do
  readonly property int fittingMax: {
    const report = root.selectedCrowdedOn;
    const measure = report?.selected;
    const fit = report?.sections?.[BarManager.selectedWidget.zone];
    if (!measure || !fit)
      return 0;
    return Math.max(0, measure.preferred - measure.insets - (fit.used - fit.room));
  }
  readonly property bool selectedElastic: root.dragLayer.typeInfo(BarManager.selectedWidgetConfig()?.type ?? "")?.elastic ?? false

  function _narrowestOf(reports) {
    const room = report => Object.values(report.sections ?? {}).reduce((sum, section) => sum + section.room, 0);
    return reports.reduce((best, report) => best === null || room(report) < room(best) ? report : best, null);
  }

  // Per section (BarsConfig.sectionNames), each widget's drop order
  // (BarLayout.dropOrder): a widget hidden in config or a spacer never
  // drops
  readonly property var dropOrders: {
    if (!root.showDropOrder)
      return ({});
    const widgets = BarManager.selectedBar()?.widgets ?? {};
    const names = BarsConfig.sectionNames;
    const orders = BarLayout.dropOrder(names.map(zone => (widgets[zone] ?? []).map(w => w.visible === false || w.type === "Spacer" ? null : BarManager.priorityOf(w))));
    return names.reduce((out, zone, s) => {
      out[zone] = orders[s];
      return out;
    }, {});
  }

  implicitHeight: column.implicitHeight + Widget.padding * 2

  // The bar editor's keys, while the board has focus
  Keys.onPressed: event => {
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
    const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
    const alt = (event.modifiers & Qt.AltModifier) !== 0;
    const sel = BarManager.selectedWidget;
    const has = BarManager.selectedWidgetConfig() !== null;
    if (ctrl && ((event.key === Qt.Key_Z && shift) || event.key === Qt.Key_Y))
      BarManager.history.redo();
    else if (ctrl && event.key === Qt.Key_Z)
      BarManager.history.undo();
    else if (has && ctrl && event.key === Qt.Key_D)
      BarManager.duplicateWidget(sel.zone, sel.index);
    else if (has && !ctrl && event.key === Qt.Key_Delete)
      BarManager.removeWidget(sel.zone, sel.index);
    else if (has && alt && (event.key === Qt.Key_Left || event.key === Qt.Key_Up))
      BarManager.stepWidget(-1);
    else if (has && alt && (event.key === Qt.Key_Right || event.key === Qt.Key_Down))
      BarManager.stepWidget(1);
    else if (has && event.key === Qt.Key_Escape)
      BarManager.clearSelection();
    else
      return;
    event.accepted = true;
  }

  TypePickerPopup {
    id: addPopup
    types: LibraryOrder.sorted(BarsConfig.libraryWidgetTypes, type => I18n.tr(type.label))
    parent: root
    placeholderText: I18n.tr("Search widgets")
    onTypeSelected: type => BarManager.addWidget(root._pendingZone, type)
  }

  // A chip's menu: for the selected widget (a right click selects it)
  StyledContextMenu {
    id: chipMenu
    parent: root
    onTriggered: id => root._menuAction(id)
  }

  function _openMenu(zone, index, chip, x, y) {
    BarManager.selectWidget(zone, index);
    root.forceActiveFocus();
    const widget = BarManager.selectedWidgetConfig();
    const length = BarManager.selectedBar()?.widgets?.[zone]?.length ?? 0;
    const others = (BarManager.localConfig ?? []).map((bar, i) => ({
          "id": "copy:" + i,
          "text": BarManager.barLabel(i)
        })).filter((item, i) => i !== BarManager.selectedBarIndex);
    chipMenu.items = [
      {
        "id": "edit",
        "text": I18n.tr("Edit"),
        "icon": "edit"
      },
      {
        "id": "visible",
        "text": widget?.visible === false ? I18n.tr("Show on the bar") : I18n.tr("Hide on the bar"),
        "icon": widget?.visible === false ? "visibility" : "visibility_off"
      },
      {
        "id": "duplicate",
        "text": I18n.tr("Duplicate"),
        "icon": "content_copy",
        "shortcut": I18n.tr("Ctrl+D")
      },
      {
        "id": "remove",
        "text": I18n.tr("Remove"),
        "icon": "delete",
        "shortcut": I18n.tr("Del")
      },
      {
        "separator": true
      }
    ].concat(root.dragLayer.zones.map(z => ({
          "id": "zone:" + z.key,
          "text": I18n.tr("Move to {0}", z.label),
          "icon": "arrow_forward",
          "enabled": z.key !== zone
        }))).concat([
      {
        "id": "start",
        "text": I18n.tr("Move to the start"),
        "icon": "first_page",
        "enabled": index > 0
      },
      {
        "id": "end",
        "text": I18n.tr("Move to the end"),
        "icon": "last_page",
        "enabled": index < length - 1
      },
      {
        "separator": true
      },
      {
        "id": "spacerBefore",
        "text": I18n.tr("Add a spacer before"),
        "icon": "space_bar"
      },
      {
        "id": "spacerAfter",
        "text": I18n.tr("Add a spacer after"),
        "icon": "space_bar"
      },
      {
        "id": "copy",
        "text": I18n.tr("Copy to bar"),
        "icon": "move_group",
        "enabled": others.length > 0,
        "submenu": others
      }
    ]);
    chipMenu.openAt(chip, x, y);
  }

  function _menuAction(id) {
    const sel = BarManager.selectedWidget;
    const widget = BarManager.selectedWidgetConfig();
    if (!widget)
      return;
    if (id === "visible")
      BarManager.setWidgetVisible(sel.zone, sel.index, widget.visible === false);
    else if (id === "duplicate")
      BarManager.duplicateWidget(sel.zone, sel.index);
    else if (id === "remove")
      BarManager.removeWidget(sel.zone, sel.index);
    else if (id.startsWith("zone:"))
      BarManager.moveWidgetTo(id.slice(5), true);
    else if (id === "start" || id === "end")
      BarManager.moveWidgetTo(sel.zone, id === "end");
    else if (id === "spacerBefore" || id === "spacerAfter")
      BarManager.addWidget(sel.zone, "Spacer", sel.index + (id === "spacerAfter" ? 1 : 0));
    else if (id.startsWith("copy:"))
      BarManager.copyWidgetToBar(Number(id.slice(5)));
    // "edit": the right click selected it, so the inspector shows it
  }

  Card {
    anchors.fill: parent
    color: Theme.background
    border.color: Theme.border

    ColumnLayout {
      id: column
      anchors.fill: parent
      anchors.margins: Widget.padding
      spacing: Widget.spacing

      CardHeader {
        title: I18n.tr("Widgets")
        showActions: false
        help: I18n.tr("Drag widgets to arrange them, across sections too. Click one to edit it, right-click it for more: the bar outlines it. Keys: Delete, Ctrl+D, Alt+arrows to move it, Escape, Ctrl+Z to undo. Changes show on the bar as you make them; Save keeps them.")

        UndoRedoButtons {
          canUndo: BarManager.history.canUndo
          canRedo: BarManager.history.canRedo
          onUndo: BarManager.history.undo()
          onRedo: BarManager.history.redo()
        }

        FlatIconButton {
          iconText: "format_list_numbered"
          iconColor: root.showDropOrder ? Theme.accent : Theme.foregroundAlt
          tooltipText: root.showDropOrder ? I18n.tr("Hide the drop order") : I18n.tr("Show the order widgets drop in when the bar is crowded")
          onClicked: root.showDropOrder = !root.showDropOrder
        }

        StatusChip {
          shown: BarManager.isDirty
          text: I18n.tr("Unsaved")
          color: Theme.warning
        }
      }

      // How the bar fits: the screens it fits, or per screen the widgets
      // it has no room for, each a button selecting it; for a selected
      // one, what would make it fit
      StyledText {
        visible: root.turnedOff || (root.reports.length > 0 && root.crowded.length === 0)
        Layout.fillWidth: true
        text: root.turnedOff ? I18n.tr("Turned off") : I18n.tr("Fits {0}", root.reports.map(report => report.screen).join(", "))
        opacity: 0.6
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.WordWrap
      }

      Flow {
        visible: !root.turnedOff && root.crowded.length > 0
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        Repeater {
          model: root.turnedOff ? [] : root.crowded

          // Wrapping at the board's width
          delegate: Flow {
            id: screenFit
            required property var modelData
            width: parent?.width ?? 0
            spacing: Widget.spacing / 2

            StyledText {
              height: Widget.height
              verticalAlignment: Text.AlignVCenter
              text: I18n.tr("No room on {0} for", screenFit.modelData.screen)
              textColor: Theme.warning
              textSize: Appearance.fontSizeBy(-2)
            }

            Repeater {
              model: screenFit.modelData.widgets

              delegate: StyledTextButton {
                required property var modelData
                readonly property bool isSelected: BarManager.selectedWidget.zone === modelData.zone && BarManager.selectedWidget.index === modelData.index
                text: root.dragLayer.widgetLabel(BarManager.selectedBar()?.widgets?.[modelData.zone]?.[modelData.index])
                textSize: Appearance.fontSizeBy(-2)
                textPadding: Widget.smallPadding
                backgroundColor: isSelected ? Theme.warning : Theme.backgroundHighlight
                textColor: isSelected ? Theme.background : Theme.foreground
                tooltipText: I18n.tr("Select it")
                onClicked: {
                  BarManager.selectWidget(modelData.zone, modelData.index);
                  root.forceActiveFocus();
                }
              }
            }
          }
        }

        StyledTextButton {
          visible: root.selectedCrowdedOn !== null
          iconText: "keyboard_double_arrow_up"
          text: I18n.tr("Raise priority")
          textSize: Appearance.fontSizeBy(-2)
          textPadding: Widget.smallPadding
          tooltipText: I18n.tr("Drop it last when the bar is crowded")
          onClicked: BarManager.raiseWidgetPriority(BarManager.selectedWidget.zone, BarManager.selectedWidget.index)
        }

        StyledTextButton {
          visible: root.selectedCrowdedOn !== null && root.selectedElastic && root.fittingMax > 0
          iconText: "width"
          text: I18n.tr("Set max length")
          textSize: Appearance.fontSizeBy(-2)
          textPadding: Widget.smallPadding
          tooltipText: I18n.tr("Cap it at {0} px, so it fits on {1}", root.fittingMax, root.selectedCrowdedOn?.screen ?? "")
          onClicked: BarManager.updateWidgetLayout(BarManager.selectedWidget.zone, BarManager.selectedWidget.index, "maxSize", root.fittingMax)
        }
      }

      // The sections, one row under another
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        Repeater {
          model: root.dragLayer.zones

          delegate: SectionLane {
            id: lane
            required property var modelData

            Layout.fillWidth: true
            dragLayer: root.dragLayer
            reports: root.reports
            zone: lane.modelData.key
            title: lane.modelData.label
            dropOrders: root.dropOrders[lane.modelData.key] ?? []
            fit: root.turnedOff ? null : root.narrowest?.sections?.[lane.modelData.key] ?? null
            fitScreen: root.narrowest?.screen ?? ""
            onAddRequested: anchor => {
              root._pendingZone = lane.modelData.key;
              addPopup.openAt(anchor);
            }
            onChipClicked: root.forceActiveFocus()
            onMenuRequested: (index, chip, x, y) => root._openMenu(lane.modelData.key, index, chip, x, y)
          }
        }
      }

      Item {
        Layout.fillHeight: true
      }
    }
  }
}
