pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods

// Base for a bar widget with a display style (docs/dev/bar/display-styles.md):
// label, icon, ring, fill, pill, segments, sparkline, ticker or stacked, from
// its `appearance` (WidgetBase's appearance part, a custom widget's
// `bar`). The widget gives its value as `ratio`, its history, its text and
// subtext; a style it can't draw right now (no value yet, no history)
// draws as the nearest one it can.
BarIconWidget {
  id: root

  // {style, segments, width, colorText} (the base's, WidgetLook's)
  appearance: properties.appearance
  // Its value, 0-1, for ring, fill, segments and pill; below 0 while it
  // has none (those draw as a label then)
  property real ratio: -1
  // Oldest first, for the sparkline, between graphMin and graphMax; null
  // when it keeps none (the sparkline draws as a fill)
  property var history: null
  property real graphMin: 0
  property real graphMax: 1
  // The ticker's text and stacked's first line, and stacked's second
  property string styleText: root.text
  property string subtext: ""
  // Whether its label shows beside a graphic (its own "show the value"
  // setting): ticker and stacked are the label, icon has none
  property bool labelShown: true
  // The colour of its state, for "Colour the text by state" (the base's
  // stateColor, hasState: whether it has one right now)
  stateColor: root.accentColor

  readonly property string style: ValueGraphics.resolvedStyle(root.appearance.style, root.isVertical, root.history !== null, root.ratio)
  // Its icon's or label's line, or its graphic where that reaches further
  // across (a ring, a sparkline, stacked's two lines)
  contentAcross: Math.max(root.barConfig.fontSize * Math.max(1, root.iconScale), graphic.across)

  showText: root.labelShown && !["icon", "ticker", "stacked"].includes(root.style)
  leadLength: graphic.drawn ? graphic.length : 0
  leadAfterIcon: graphic.afterIcon

  // The pill: its background's shape filled to the value (WidgetGroup
  // draws it, so it takes the bar's caps and radius)
  backgroundLevel: root.style === "pill" && !root.hidden ? Math.min(1, root.ratio) : -1
  backgroundLevelColor: BarWidgetStyle.levelColor(root.colors)

  // Graphics draw in the icon's colour for this bar's style: the state's
  // on a tint, outline or plain bar, what reads on it when it's the fill
  ValueGraphic {
    id: graphic
    parent: root.lead
    anchors.fill: parent
    style: root.style
    ratio: Math.max(0, Math.min(1, root.ratio))
    history: root.history ?? []
    graphMin: root.graphMin
    graphMax: root.graphMax
    text: root.styleText
    subtext: root.subtext
    textFormat: root.textFormat
    minimumText: root.minimumText
    segmentCount: root.appearance.segments
    preferredLength: root.appearance.width
    vertical: root.isVertical
    crossSize: root.crossSize
    room: ValueGraphics.boxRoom(root.crossSize, root.barConfig.look.shape)
    fontSize: root.fontSize
    middle: root.iconMiddle
    color: root.colors.icon
    textColor: root.contentColors.text
  }
}
