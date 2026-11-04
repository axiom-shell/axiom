pragma ComponentBehavior: Bound
import QtQuick

// The sizing wrapper for bar modules (WidgetGroup draws their
// backgrounds). Its size is set by the bar (BarWidgetHost); subclasses
// report their natural size through implicitWidth/implicitHeight and fit
// their content inside whatever size they're actually given. Content
// never draws outside it.
Item {
  id: root

  property alias content: contentLoader.sourceComponent
  // Set from the bar's barConfig: its padding, and the thickness across
  // the bar (its thickness)
  property int padding: 0
  property bool isVertical: false
  property int crossSize: 0

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

  implicitWidth: isVertical ? root.crossSize : (contentLoader.item ? contentLoader.item.implicitWidth + padding * 2 : 0)
  implicitHeight: isVertical ? (contentLoader.item ? contentLoader.item.implicitHeight + padding * 2 : 0) : root.crossSize

  clip: true

  Loader {
    id: contentLoader
    anchors.centerIn: parent
  }
}
