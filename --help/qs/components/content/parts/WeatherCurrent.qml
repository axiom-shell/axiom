pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.reusable

// The weather now (WeatherManager): the place, then the condition's icon
// beside (or over, `stacked`) the temperature, condition and details. The
// Weather card's, and its popout's (WeatherForecast, the condition on the
// temperature's line: `labelInline`).
ColumnLayout {
  id: root

  property bool stacked: false
  property bool labelInline: false
  property real iconSize: Appearance.fontSize * 3
  property real temperatureSize: Appearance.fontSize * 2

  readonly property int _align: root.stacked ? Text.AlignHCenter : Text.AlignLeft

  spacing: Widget.spacing

  StyledText {
    visible: (WeatherManager.place?.name ?? "") !== ""
    Layout.fillWidth: true
    horizontalAlignment: root._align
    elide: Text.ElideRight
    text: WeatherManager.place?.name ?? ""
    font.bold: true
    textColor: Theme.accent
  }
  GridLayout {
    Layout.fillWidth: true
    columns: root.stacked ? 1 : 2
    columnSpacing: Widget.padding * 1.5
    rowSpacing: Widget.spacing
    // The current condition, cross-fading as it changes
    CrossFade {
      Layout.alignment: root.stacked ? Qt.AlignHCenter : Qt.AlignVCenter
      value: WeatherManager.condition?.icon ?? ""
      delegate: StyledIcon {
        required property var value
        text: value
        textSize: root.iconSize
      }
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 2
      StyledText {
        Layout.fillWidth: true
        horizontalAlignment: root._align
        text: WeatherManager.current ? `${Math.round(WeatherManager.current.temperature_2m)}${WeatherManager.unitSymbol}` + (root.labelInline ? `  ${WeatherManager.condition?.label ?? ""}` : "") : ""
        textSize: root.temperatureSize
        font.bold: true
      }
      StyledText {
        visible: !root.labelInline
        Layout.fillWidth: true
        horizontalAlignment: root._align
        elide: Text.ElideRight
        text: WeatherManager.condition?.label ?? ""
      }
      StyledText {
        Layout.fillWidth: true
        horizontalAlignment: root._align
        elide: Text.ElideRight
        text: WeatherManager.details
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
      }
    }
  }
}
