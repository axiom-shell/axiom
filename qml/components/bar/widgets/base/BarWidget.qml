pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.bar.look

// The base of every bar widget: the inputs it gets from BarWidgetHost, the
// bar's orientation and the colors it draws in (WidgetLook: `colors`,
// `drawnColors`, `paint`), and a template that draws what the widget gives
// it as data. The widget sets data, never builds the drawing:
//   - a row: an icon and a label (`icon`, `text`, ...), with a value graphic
//     before or after the icon (`ratio`, `history`, from its `appearance`)
//     or a spinner while `busy`, laid out by IconTextRow;
//   - segments: `items` shown, each as a row of its own from `segmentData`
//     (WidgetSegments: System Stats' metrics, Lock keys' keys);
//   - its own content (`ownContent`, with a head: `headIcon`, `headText` or
//     `headItem`, WidgetHead), as Time and the tray do.
// A badge, a mark, a pulse (`pulsing`) and the press, hover and click
// handling are the template's too. Its WidgetGroup draws its background
// under it when `hasBackground`, in the bar's widget style, from `drawnColors`.
//
// Clicks: set `clickable` (and `acceptedButtons` beyond the left one) and
// handle clicked(button); a clickable widget shows a pointer and a press
// shows in its colors, and it does nothing while `hidden`. Set `scrollable`
// to get scrolled(steps), +1 per wheel notch up.
Item {
  id: root

  // From its host (BarWidgetHost)
  property var barConfig
  property var panel
  property var screen
  property var properties
  // Drawn one box per item (Boxes: One per item), the one item it draws
  // (BarBoxes; set by its host), else ""
  property string box: ""
  // Where its pointer areas go, in its background's shape (set by its
  // BarWidgetHost; null: its own bounds)
  property var hitArea: null
  // While `segmented`: { sized, drawn: its place in the bar's run ({ index,
  // count }, null alone), from what it shows (its parts' room) and as
  // laid out (their shapes); reachStart, reachEnd: how far its parts reach
  // past it across (a tab's out to its edge); tabLimits: what bounds a tab
  // at its two ends (BarTabs.tabLimits) }; null otherwise, or with no
  // place (a preview)
  property var runPlace: null
  // Its Auto fields' roles and its place along the bar for the gradient
  // (set by its host)
  property alias autoColors: look.autoColors
  property alias barOffset: look.barOffset
  property alias barLength: look.barLength

  // A row: an icon (its glyphs one per line, laid along the bar), or an
  // image in its place (`iconSource`), a label, and the room of the widest
  // one (`minimumText`)
  property string icon: ""
  property string iconSource: ""
  property string text: ""
  // Text.PlainText for text from outside (an event's title), which mustn't
  // render as styled text or load images
  property int textFormat: Text.AutoText
  property string minimumText: ""
  // Draws nothing and takes no room, padding included (a widget with
  // nothing to show)
  property bool hidden: false
  property real iconScale: 1
  property real textScale: 1
  property bool showIcon: true
  property bool showText: root.labelShown && !["icon", "ticker", "stacked"].includes(root.valueStyle)

  // A value, for its display style (docs/dev/bar/display-styles.md): 0-1
  // for ring, fill, segments and pill, below 0 while it has none (those
  // draw as a label then); its history, oldest first, between graphMin and
  // graphMax (null: it keeps none, the sparkline draws as a fill); the
  // ticker's text and stacked's first line, and stacked's second; whether
  // its label shows beside a graphic (its own "show the value" setting)
  property real ratio: -1
  property var history: null
  property real graphMin: 0
  property real graphMax: 1
  property string styleText: root.text
  property string subtext: ""
  property bool labelShown: true
  // {style, segments, width}: the display style, or null for a
  // plain label
  property var appearance: root.properties?.appearance ?? null

  // Its color field ("backgroundColor" unless a state names another, ""
  // for a color of its own), or the name of a color for its state (a
  // failure's "error") instead; dimmed (an off lock key, a paused timer);
  // pulsing between itself and its dimmed self (`pulse`)
  property string accentField: "backgroundColor"
  property string stateColorName: ""
  property bool muted: false
  property bool pulsing: false

  // A count over its icon's corner ({ text, field }: the color field its
  // fill reads in), a mark on its icon's other corner ({ icon, field }),
  // the color field its icon reads in ("": its colors'), and a spinner in
  // the icon's place while busy
  property var badge: null
  property var mark: null
  property string iconField: ""
  property bool busy: false

  // Segments: the ids it shows (a box of a widget drawn one box per item
  // shows its one), and their data: `segmentData` a function (key -> {
  // icon, text, minimumText, ratio, history, graphMin, graphMax, caption,
  // field, muted, hidden, small }, WidgetSegments)
  property var items: []
  readonly property var shownItems: root.ownBox ? root.items.filter(k => k === root.box) : root.items
  property var segmentData: null
  // Drawn as one item's box of its own (Boxes: One per item)
  readonly property bool ownBox: root.box !== ""

  // Its own content: a head (an icon, a short text or an item of its own)
  // and the content after it, its extent across (-1: a line)
  property string headIcon: ""
  property string headText: ""
  property Item headItem: null
  property Component ownContent: null
  property real ownAcross: -1

  // Clicks and wheel: a clickable one shows a pointer and does nothing
  // while hidden; filled while its hit area is hovered, with the bar's
  // "Fill on hover" (off for a widget whose parts fill instead:
  // Workspaces' cells); an outline in its shape while hovered
  property bool clickable: false
  property int acceptedButtons: Qt.LeftButton
  property bool scrollable: false
  property bool fillsOnHover: true
  property bool hoverOutline: false
  signal clicked(int button)
  signal scrolled(real steps)
  readonly property bool pressed: clickArea.pressed
  // The pointer is over it (an edge menu this opened stays open
  // meanwhile). One taking no clicks or scrolls has no click area: its
  // hit area's hover, else its own bounds'
  readonly property bool hovered: clickArea.enabled ? clickArea.containsMouse : root.hitArea ? root.hitArea.hovered : hover.hovered
  // The bar's inner side, where its tooltip opens
  readonly property int innerEdges: BarCells.innerEdges(barConfig)

  // News worth showing a hidden bar for (its host hands it to
  // BarRevealManager): fired on a change, never at startup
  signal attention
  // A level whose rise is news (a count, a severity), -1 while unknown:
  // set, the widget fires `attention` whenever it rises past the last
  // known one (an unknown level keeps the last; the first known one only
  // records it)
  property real attentionLevel: -1
  // While true, a rise is recorded but isn't news (do-not-disturb)
  property bool attentionMuted: false
  property real _attentionLast: -1
  onAttentionLevelChanged: {
    if (root.attentionLevel < 0)
      return;
    if (!root.attentionMuted && root._attentionLast >= 0 && root.attentionLevel > root._attentionLast)
      root.attention();
    root._attentionLast = root.attentionLevel;
  }
  Component.onCompleted: root._attentionLast = root.attentionLevel

  // Kept at the start of its drawn size while that catches up with a new
  // one, rather than centred in it: for a widget that grows and shrinks at
  // its end, whose start shouldn't drift meanwhile (Workspaces' strip)
  property bool pinStart: false
  // With a background, it lays its own parts out as segments of the bar's
  // run (Workspaces' cells with its Background off): its background draws
  // no box, its host keeps no cap room for it, and it's told its place in
  // the run (`runPlace`), from which its parts take their shapes
  // (BarCells.cellShape, cellRoom)
  property bool segmented: false
  readonly property bool isVertical: barConfig.vertical
  // Where a point `along` the bar from `item`'s start (an item inside it)
  // sits along the bar (0-1), or -1 without a gradient. Read when what
  // places the point changes: mapping isn't a binding.
  function barSpotOf(item: Item, along: real): real {
    if (root.barLength <= 0)
      return -1;
    const point = item.mapToItem(root, root.isVertical ? 0 : along, root.isVertical ? along : 0);
    return BarGradient.spot(root.isVertical ? point.y : point.x, 0, root.barOffset, root.barLength);
  }

  // The colors it draws in (WidgetLook): `colors` as they are (muted and
  // pressed where it is), `drawnColors` with a pulse's mix (its
  // background's and what `paint` reads), `paint` the color of each of its
  // parts and the functions that read a color of its own on them
  readonly property var colors: look.colors
  readonly property var drawnColors: look.drawnColors
  readonly property var paint: look.paint
  // How its value is drawn: the display style of `appearance` as it can
  // draw it now (ValueGraphics.resolvedStyle), "label" with none
  readonly property string valueStyle: root.appearance ? ValueGraphics.resolvedStyle(root.appearance.style, root.isVertical, root.history !== null, root.ratio) : "label"
  // Its row's, in the widget's coordinates, and its smallest main-axis size
  // (down to its icon in a row; else the size it takes)
  readonly property alias iconRect: row.iconRect
  readonly property alias iconMiddle: row.iconMiddle
  readonly property real minimumSize: root._mode === "row" ? row.minimumSize : root.isVertical ? root.implicitHeight : root.implicitWidth
  // 0-1, how far it has pulsed toward its muted self (while `pulsing`)
  property real pulse: 0

  // What it draws, from the data it was given: "own" (its own content or
  // a head), "segments", "row" (an icon and a label, or a spinner) or
  // "none" (also while `hidden`). Read from data only, never from what it
  // draws.
  readonly property string _mode: root.hidden ? "none" : root.ownContent !== null || root.headItem !== null || root.headIcon !== "" || root.headText !== "" ? "own" : root.segmentData !== null && root.shownItems.length > 0 ? "segments" : root._rowShown ? "row" : "none"
  readonly property bool _rowShown: root.icon !== "" || root.iconSource !== "" || root.text !== "" || root.busy

  // Its sizing on the bar (BarWidgetHost): "content" (its implicit size) or
  // "fixed" (preferredSize, whatever it shows); an elastic type (x-elastic)
  // is capped at preferredSize (-1: none). A divider of its own (the group
  // draws none beside it: Separator, Spacer), and room taking its side's
  // free space (Spacer)
  property string sizePolicy: "content"
  property real preferredSize: -1
  property bool divides: false
  property bool fills: false

  // Whether its WidgetGroup draws a background under it
  property bool hasBackground: !root.hidden && root._mode !== "none"
  // Its content's extent across the bar (px), which its background's caps
  // keep clear of (BarWidgetHost.contentAcross): from config, never
  // measured. Its icon at the bar's font size, at its scale where its type
  // draws it larger (iconScale), or the graphic reaching further across (a
  // ring, a sparkline, stacked's two lines); its own content's; its
  // segments' (the furthest graphic of their styles).
  property real contentAcross: root._mode === "row" ? Math.max(root.barConfig.fontSize * Math.max(1, root.iconScale), graphic.across) : root._mode === "own" ? (root.ownAcross >= 0 ? root.ownAcross : root.barConfig.fontSize) : root._mode === "segments" ? ((segments.item as WidgetSegments)?.across ?? root.barConfig.fontSize) : root.barConfig.fontSize
  // A level (0-1) its WidgetGroup fills its background's shape to, along
  // the bar (up a vertical one), in backgroundLevelColor; -1 for none (the
  // pill style fills it to its value)
  property real backgroundLevel: root.valueStyle === "pill" && !root.hidden ? Math.min(1, root.ratio) : -1
  property color backgroundLevelColor: root.drawnColors.level
  // It shows an icon part and a label apart on a split bar, and where
  // (IconTextRow's splits, splitAt, splitPart, which its host reads), from
  // its row, its head or its segments; the parts after the first, each
  // from its own start divider ({ from: the middle of the gap before it,
  // at, part }, in its coordinates): its segments'
  property bool splits: root._mode === "own" ? head.splits : root._mode === "segments" ? ((segments.item as WidgetSegments)?.splits ?? false) : root._mode === "row" ? row.splits : false
  property real splitAt: root._mode === "own" ? head.splitAt : root._mode === "segments" ? ((segments.item as WidgetSegments)?.splitAt ?? -1) : root._mode === "row" ? row.splitAt : -1
  property rect splitPart: root._mode === "own" ? head.splitPart : root._mode === "segments" ? ((segments.item as WidgetSegments)?.splitPart ?? Qt.rect(0, 0, 0, 0)) : root._mode === "row" ? row.splitPart : Qt.rect(0, 0, 0, 0)
  property var innerSplits: root._mode === "segments" ? ((segments.item as WidgetSegments)?.innerSplits ?? []) : []
  // The room its row keeps for a graphic before its icon, or a spinner
  property real leadLength: root.busy ? (root.isVertical ? spinner.implicitHeight : spinner.implicitWidth) : graphic.drawn ? graphic.length : 0
  // The color its row's icon draws in: its icon field's, else its colors'
  property color _rowIconColor: root.iconField !== "" ? root.paint.field(root.iconField, "icon") : root.paint.icon

  // Its own content's place along it, centred with its head, and its length
  readonly property real _ownLength: root.isVertical ? ((own.item as Item)?.implicitHeight ?? 0) : ((own.item as Item)?.implicitWidth ?? 0)
  readonly property real _ownStart: Math.round(((root.isVertical ? root.height : root.width) - head.length - root._ownLength) / 2)

  implicitWidth: root._mode === "own" ? (root.isVertical ? root.barConfig.thickness : head.length + root._ownLength + root.barConfig.innerPadding * 2) : root._mode === "segments" ? ((segments.item as WidgetSegments)?.implicitWidth ?? 0) : row.implicitWidth
  implicitHeight: root._mode === "own" ? (root.isVertical ? head.length + root._ownLength + root.barConfig.innerPadding * 2 : root.barConfig.thickness) : root._mode === "segments" ? ((segments.item as WidgetSegments)?.implicitHeight ?? 0) : row.implicitHeight

  WidgetLook {
    id: look
    barConfig: root.barConfig
    properties: root.properties
    accentField: root.accentField
    stateColorName: root.stateColorName
    muted: root.muted
    pressed: root.pressed
    pulsing: root.pulsing
    pulse: root.pulse
    splits: root.splits
    level: root.backgroundLevel >= 0
    length: root.isVertical ? root.height : root.width
    hovered: root.fillsOnHover && (root.hitArea?.hovered ?? false)
  }

  // A row: an icon and a label (or a graphic or a spinner in the icon's
  // place), the bar's size and spacing
  IconTextRow {
    id: row
    anchors.fill: parent
    hidden: root.hidden || root._mode !== "row"
    padding: root.barConfig.innerPadding
    crossSize: root.barConfig.thickness
    isVertical: root.isVertical
    fontSize: root.barConfig.fontSize
    // The icon's gap to its label (6 px at the default inner spacing of 4)
    spacing: root.barConfig.iconGap
    iconSpacing: root.barConfig.innerGap
    splitRoom: root.barConfig.splitRoom
    icon: root.icon
    iconSource: root.iconSource
    text: root.text
    textFormat: root.textFormat
    minimumText: root.minimumText
    iconScale: root.iconScale
    textScale: root.textScale
    showText: root.showText
    showIcon: root.showIcon && !root.busy
    leadLength: root.leadLength
    leadAfterIcon: graphic.afterIcon
    textColor: root.paint.text
    iconColor: root._rowIconColor
    glides: !root.pulsing
  }

  // Its display style's graphic in the row's lead slot: in the colors of
  // its icon for this bar's style (the state's on a tint, outline or plain
  // bar, what reads on it when it's the fill)
  ValueGraphic {
    id: graphic
    parent: row.lead
    anchors.fill: parent
    visible: !root.busy
    style: root.valueStyle
    ratio: Math.max(0, Math.min(1, root.ratio))
    history: root.history ?? []
    graphMin: root.graphMin
    graphMax: root.graphMax
    text: root.styleText
    subtext: root.subtext
    textFormat: root.textFormat
    minimumText: root.minimumText
    segmentCount: root.appearance?.segments ?? 5
    preferredLength: root.appearance?.width ?? 0
    vertical: root.isVertical
    crossSize: root.barConfig.thickness
    room: ValueGraphics.boxRoom(root.barConfig.thickness, root.barConfig.look.shape)
    fontSize: root.barConfig.fontSize
    middle: row.iconMiddle
    paint: root.paint.graphic
  }

  // While busy, a spinner stands in for the icon
  SpinningIcon {
    id: spinner
    parent: row.lead
    anchors.centerIn: parent
    visible: root.busy
    text: "progress_activity"
    textColor: root.paint.icon
    textSize: root.barConfig.fontSize * root.iconScale
    spinning: root.busy && !root.hidden
  }

  // Its own content's head, then the content, centred as a whole across
  WidgetHead {
    id: head
    visible: root._mode === "own" && shown
    barConfig: root.barConfig
    start: root._ownStart
    icon: root.headIcon
    text: root.headText
    ownHead: root.headItem
    hasLabel: root.ownContent !== null
    iconColor: root.paint.icon
    textColor: root.paint.headText
    glides: !root.pulsing
  }

  Loader {
    id: own
    active: root._mode === "own"
    sourceComponent: root.ownContent
    x: root.isVertical ? Math.round((root.width - width) / 2) : root._ownStart + head.length
    y: root.isVertical ? root._ownStart + head.length : Math.round((root.height - height) / 2)
  }

  // Several values, each its own row
  Loader {
    id: segments
    anchors.fill: parent
    active: root._mode === "segments"
    sourceComponent: WidgetSegments {
      barConfig: root.barConfig
      keys: root.shownItems
      dataOf: root.segmentData
      paint: root.paint
      appearance: root.appearance
      isVertical: root.isVertical
    }
  }

  // On the icon's top-right corner, which on a narrow bar reaches past
  // the widget's box; a ring on a fill. None while the icon isn't shown.
  CountBadge {
    readonly property var _colors: root.badge ? BarWidgetStyle.badge(root.barConfig.palette, root.drawnColors, look.fieldColor(root.badge.field)) : null
    shown: root.badge !== null && root.badge.text !== "" && !root.hidden && root.iconRect.width > 0
    x: Math.round(root.iconRect.x + root.iconRect.width - width / 2)
    y: 1
    text: root.badge?.text ?? ""
    color: _colors?.fill ?? "transparent"
    textColor: _colors?.text ?? "transparent"
    ringColor: _colors?.ring ?? "transparent"
    // The bar's own text size, not the Interface scale
    textSize: Math.round(root.barConfig.fontSize * 0.7)
  }

  // On the icon's bottom-right corner (wherever the label and style put
  // the icon). None while the icon isn't shown.
  StyledIcon {
    visible: opacity > 0
    opacity: root.mark !== null && root.iconRect.width > 0 ? 1 : 0
    x: Math.round(root.iconRect.x + root.iconRect.width - width * 0.6)
    y: Math.round(root.iconRect.y + root.iconRect.height - height * 0.8)
    text: root.mark?.icon ?? ""
    fill: 1
    textSize: Math.round(root.barConfig.fontSize * 0.65)
    textColor: root.mark ? root.paint.field(root.mark.field, "mark") : root.paint.icon

    Glide on opacity {}
  }

  // Pulsing: a slow swing toward its muted self and back, still when it stops
  SequentialAnimation {
    running: root.pulsing && !root.hidden && Appearance.animations
    loops: Animation.Infinite
    onRunningChanged: {
      if (!running)
        root.pulse = 0;
    }

    PropertyAnimation {
      target: root
      property: "pulse"
      from: 0
      to: 1
      duration: Appearance.animSlow * 5
      easing.type: Easing.InOutQuad
    }

    PropertyAnimation {
      target: root
      property: "pulse"
      from: 1
      to: 0
      duration: Appearance.animSlow * 5
      easing.type: Easing.InOutQuad
    }
  }

  HoverHandler {
    id: hover
    enabled: !clickArea.enabled && !root.hitArea
  }

  MouseArea {
    id: clickArea
    parent: root.hitArea ?? root
    anchors.fill: parent
    containmentMask: root.hitArea?.mask ?? null
    enabled: (root.clickable || root.scrollable) && !root.hidden
    hoverEnabled: true
    cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: root.clickable ? root.acceptedButtons : Qt.NoButton
    onClicked: mouse => root.clicked(mouse.button)
    onWheel: wheel => {
      if (root.scrollable)
        root.scrolled(wheel.angleDelta.y / 120);
      else
        wheel.accepted = false;
    }
  }
}
