pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.bar
import qs.components.reusable

// One bar widget in the editor, as a pill (`payload`: what dragging it
// carries, { kind, zone, index, type }). Given its `widget` and the bar's
// `previewConfig` it shows the widget itself, live (alone in a WidgetGroup
// in preview, on its background, taking no input, streamed in a moment
// after the board); a widget showing nothing (a spacer, no updates) and a chip
// with no widget (the drag's ghost) show its type's icon and label, the
// first greyed. A right click asks for its menu (DragChip's
// `menuRequested`).
DragChip {
  id: root

  // `dragLayer` is the DragLayer that carries it and names the types
  // (a library key: a custom widget's is "CustomWidget:<id>")
  property string type: ""
  // The widget's config as its bar has it (its type, properties with the
  // Auto colours picked: the preview bar's `widgets`, layout), or null:
  // icon and label only
  property var widget: null
  // The bar to draw it on (BarManager.previewConfig)
  property var previewConfig: null
  // The widget's own `visible: false` (kept in config, not shown on the bar)
  property bool hiddenWidget: false
  // Hidden by a running bar for want of room
  property bool crowded: false
  // Left in place, faded, while it's being carried
  property bool faded: false
  // Its place in the order a crowded bar drops widgets in (1 goes first;
  // 0 shows none: a spacer, or the badges off)
  property int dropOrder: 0
  // The longest a live widget is drawn (a long window title is cut)
  property real maxPreviewWidth: Widget.px(260)

  readonly property bool live: root.widget !== null && root.previewConfig !== null
  // Live, but drawing nothing (or not built yet)
  readonly property bool empty: !previewLoader.hasContent

  hasMenu: true
  showsLabel: !root.live || root.empty
  icon: root.dragLayer.icon(root.type)
  label: root.dragLayer.label(root.type)
  opacity: root.faded ? 0.3 : (root.hiddenWidget || (root.live && root.empty && previewLoader.item !== null) ? 0.6 : 1)
  // A live widget keeps its own colours: selected, it's tinted, not filled
  color: root.selected ? (root.showsLabel ? Theme.accent : Qt.alpha(Theme.accent, 0.2)) : (root.hovered || root.highlighted ? Theme.backgroundHighlight : Theme.background)

  readonly property color _markInk: root.showsLabel ? root.ink : Theme.foreground

  // The widget as the bar draws it alone in a section: a section of its
  // own (WidgetGroup), so its background takes the look as the bar's do
  // (its caps and their room, split's icon part, a merged run's
  // background, a segmented widget's cells). With no place on a bar it
  // takes no part of the bar's gradient: its Auto color shows.
  component LivePreview: Item {
    readonly property alias group: widgetGroup
    implicitWidth: Math.min(widgetGroup.implicitWidth, root.maxPreviewWidth)
    implicitHeight: widgetGroup.implicitHeight
    enabled: false

    WidgetGroup {
      id: widgetGroup
      preview: true
      panel: null
      screen: null
      barConfig: root.previewConfig
      widgets: [root.widget ?? ({})]
    }
  }

  StreamedLoader {
    id: previewLoader
    readonly property LivePreview shownItem: previewLoader.item as LivePreview
    readonly property bool hasContent: shownItem?.group.hasContent ?? false
    wanted: root.live
    label: "bar editor chip"
    Layout.preferredWidth: root.empty ? 0 : (shownItem?.implicitWidth ?? 0)
    Layout.preferredHeight: shownItem?.implicitHeight ?? 0
    clip: true
    sourceComponent: LivePreview {}
  }

  // Hidden on the bar
  StyledIcon {
    visible: root.hiddenWidget
    text: "visibility_off"
    textColor: root._markInk
    opacity: 0.7
  }

  // No room for it on the bar
  StyledIcon {
    visible: root.crowded && !root.hiddenWidget
    text: "compress"
    textColor: root.selected ? root._markInk : Theme.warning
  }

  // When it goes on a crowded bar
  CountBadge {
    shown: root.dropOrder > 0
    text: String(root.dropOrder)
    color: root.selected && root.showsLabel ? Theme.background : Theme.accent
    textColor: root.selected && root.showsLabel ? Theme.accent : Theme.background
  }
}
