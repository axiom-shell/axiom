pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable
import qs.components.content.parts

// A custom widget's List row, down the list: an ItemRow (an icon or a
// thumbnail, the text, its subtext and value) and, when the row has a
// `rowMax`, a LevelMeter of its value under it. The colours come from the
// list (a tone from the row's state, else its own defaults), so a row
// resolves none.
Item {
  id: root

  property string rowText: ""
  property string rowIcon: ""
  property string rowValue: ""
  property string rowSubtext: ""
  // A source url ("" none)
  property string rowImage: ""
  // The value as a number, and what it is out of (0: no meter)
  property real rowNumber: 0
  property real rowMax: 0
  property bool clickable: false
  property color iconTint: Style.textMuted
  property color meterFill: Style.toneFill("accent")

  signal activated

  implicitHeight: column.implicitHeight

  ColumnLayout {
    id: column
    width: parent.width
    spacing: 0

    ItemRow {
      icon: root.rowIcon
      image: root.rowImage
      title: root.rowText
      subtitle: root.rowSubtext
      detail: root.rowValue
      iconColor: root.iconTint
      clickable: root.clickable
      onActivated: root.activated()
    }

    LevelMeter {
      visible: root.rowMax > 0
      Layout.fillWidth: true
      Layout.leftMargin: Widget.spacing
      Layout.rightMargin: Widget.spacing
      Layout.preferredHeight: Widget.px(6)
      thickness: Widget.px(4)
      share: root.rowMax > 0 ? root.rowNumber / root.rowMax : 0
      fillColor: root.meterFill
    }
  }
}
