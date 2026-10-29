pragma ComponentBehavior: Bound
import QtQuick

// Base for a bar widget with a display style (docs/dev/bar/display-styles.md):
// label, icon, ring, fill, pill, segments, sparkline, ticker or stacked, from
// its `appearance` (WidgetBase's appearance part, a custom widget's
// `bar`). The widget gives its value as `ratio`, its history, its text and
// subtext; a style it can't draw right now (no value yet, no history)
// draws as the nearest one it can.
BarIconWidget {
  id: root

  // {style, segments, width, colorText}
  property var appearance: properties.appearance
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
  // The colour of its state, for "Colour the text by state"; hasState:
  // whether it has one right now
  property color stateColor: root.accentColor
  property bool hasState: true

  readonly property string style: {
    let style = root.appearance.style;
    // Stacked draws its own two lines; on a vertical bar it's a label
    if (style === "stacked" && root.isVertical)
      return "label";
    if (style === "sparkline" && root.history === null)
      style = "fill";
    if (["ring", "fill", "segments", "pill"].includes(style) && root.ratio < 0)
      return "label";
    return style;
  }

  showText: root.labelShown && !["icon", "ticker", "stacked"].includes(root.style)
  leadLength: graphic.drawn ? graphic.length : 0
  leadAfterIcon: graphic.afterIcon

  // The pill: its background's shape filled to the value (WidgetGroup
  // draws it, so it takes the bar's caps and radius)
  backgroundLevel: root.style === "pill" && !root.hidden ? Math.min(1, root.ratio) : -1
  backgroundLevelColor: Qt.alpha(root.colors.icon, 0.35)

  // Colour the text by state only where it isn't the background already
  // (a filled widget's text must read on it)
  readonly property bool _textByState: root.appearance.colorText && root.hasState && root.colors.fill.a < 1
  foregroundColor: root._textByState ? root.stateColor : root.colors.text
  iconColor: root._textByState ? root.stateColor : root.colors.icon

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
    segmentCount: root.appearance.segments
    preferredLength: root.appearance.width
    vertical: root.isVertical
    crossSize: root.crossSize
    fontSize: root.fontSize
    color: root.colors.icon
    textColor: root.foregroundColor
  }
}
