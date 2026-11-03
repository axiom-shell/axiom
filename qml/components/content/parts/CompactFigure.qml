pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// What a compact card shows: an icon, one big value and a small label,
// fitted to the box it fills (fill the card inside its `pad`; a Panel's
// compactContent is filled for it). A wide box puts the icon beside the
// value and label, otherwise they stack. As room runs out the label goes,
// then the icon (when there's a value), and the value shrinks to fit;
// sizes come from the room, not scaling, so icons stay sharp.
Item {
  id: root

  property string icon: ""
  property string value: ""
  property string unit: ""
  property string label: ""
  property color iconColor: Theme.accent
  property color valueColor: Theme.foreground

  readonly property bool wide: root.width > root.height * 1.6
  readonly property real gap: Widget.spacing / 2

  readonly property bool _hasIcon: root.icon !== ""
  readonly property bool _hasValue: root.value !== ""
  readonly property bool _hasLabel: root.label !== ""
  // At full size; the line heights from the fonts
  readonly property real _iconFull: Appearance.fontSize * 1.8
  readonly property real _valueFull: Appearance.fontSize * 1.8
  readonly property real _valueLine: valueMetrics.height
  readonly property real _labelLine: labelMetrics.height

  // A label needs a line beside or under the value, and some width
  readonly property bool showLabel: root._hasLabel && root.width >= Appearance.fontSize * 3 && (root.wide ? root.height >= root._labelLine * 2 : root.height >= (root._hasValue ? root._valueLine * 0.7 : root._iconFull * 0.8) + root._labelLine + (root._hasIcon && root._hasValue ? root._iconFull * 0.8 + root.gap : 0))
  // The icon goes before the value does
  readonly property bool showIcon: root._hasIcon && (!root._hasValue || (root.wide ? root.width >= root.height * 2.4 : root.height >= root._iconFull * 0.8 + root.gap + root._valueLine * 0.7 + (root.showLabel ? root._labelLine : 0)))

  // Room left for the value (and, without one, the icon)
  readonly property real _labelRoom: root.showLabel ? root._labelLine : 0
  readonly property real _iconSize: !root.showIcon ? 0 : root.wide ? Math.min(root.height * 0.7, Appearance.fontSize * 2.6) : root._hasValue ? Math.min(root._iconFull, root.height * 0.3) : Math.max(Widget.px(8), Math.min(root.width * 0.6, (root.height - root._labelRoom - root.gap) * 0.8, Appearance.fontSize * 3))
  readonly property real _textWidth: root.wide && root.showIcon ? root.width - root._iconSize - Widget.spacing : root.width
  readonly property real _valueRoomH: root.wide ? root.height - root._labelRoom : root.height - root._labelRoom - (root.showIcon ? root._iconSize * 1.15 + root.gap : 0)
  readonly property real _unitWidth: root.unit !== "" ? unitMetrics.advanceWidth + 2 : 0
  readonly property real valueSize: Math.max(Widget.px(6), Math.min(root._valueFull, root._valueFull * root._valueRoomH / Math.max(1, root._valueLine), root._valueFull * (root._textWidth - root._unitWidth) / Math.max(1, valueWidth.advanceWidth)))

  FontMetrics {
    id: valueMetrics
    font.family: Appearance.fontFamily
    font.pixelSize: root._valueFull
    font.bold: true
  }
  TextMetrics {
    id: valueWidth
    text: root.value
    font: valueMetrics.font
  }
  TextMetrics {
    id: unitMetrics
    text: root.unit
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSize
  }
  FontMetrics {
    id: labelMetrics
    font.family: Appearance.fontFamily
    font.pixelSize: Appearance.fontSizeBy(-2)
  }

  GridLayout {
    anchors.centerIn: parent
    width: Math.min(implicitWidth, root.width)
    columns: root.wide ? 2 : 1
    columnSpacing: Widget.spacing
    rowSpacing: root.gap

    StyledIcon {
      visible: root.showIcon
      Layout.alignment: Qt.AlignCenter
      text: root.icon
      textColor: root.iconColor
      textSize: root._iconSize
    }

    ColumnLayout {
      visible: root._hasValue || root.showLabel
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignCenter
      spacing: 0

      FigureValue {
        visible: root._hasValue
        Layout.alignment: root.wide && root.showIcon ? Qt.AlignLeft : Qt.AlignHCenter
        value: root.value
        unit: root.unit
        valueColor: root.valueColor
        valueSize: root.valueSize
      }

      StyledText {
        visible: root.showLabel
        Layout.fillWidth: true
        Layout.maximumWidth: root._textWidth
        horizontalAlignment: root.wide && root.showIcon ? Text.AlignLeft : Text.AlignHCenter
        elide: Text.ElideRight
        text: root.label
        textSize: Appearance.fontSizeBy(-2)
        opacity: 0.6
      }
    }
  }
}
