pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable

// The weather now (a WeatherManager.stateFor result): the place, then the condition's icon
// beside (or over, `stacked`) the temperature, condition and details. The
// Weather card's, and its popout's (WeatherForecast, the condition on the
// temperature's line: `labelInline`).
ColumnLayout {
  id: root

  // A WeatherManager.stateFor result, which carries its resolved units
  property var weatherState: null
  property bool showDetails: true
  property bool stacked: false
  property bool labelInline: false
  property real iconSize: Math.round(Style.typeBody * 3) // fitted: the hero glyph beside the temperature
  property real temperatureSize: Math.round(Style.typeBody * 2) // fitted: the temperature

  readonly property var _current: root.weatherState?.weather?.current ?? null
  readonly property var _condition: WeatherManager.conditionOf(root.weatherState?.weather ?? null)
  readonly property string _unit: Utils.temperatureSymbol(root.weatherState?.units ?? "celsius")
  readonly property int _align: root.stacked ? Text.AlignHCenter : Text.AlignLeft

  spacing: Widget.spacing

  StyledText {
    visible: (root.weatherState?.place?.name ?? "") !== ""
    Layout.fillWidth: true
    horizontalAlignment: root._align
    overflow: "line"
    text: root.weatherState?.place?.name ?? ""
    tone: "accent"
  }
  GridLayout {
    Layout.fillWidth: true
    columns: root.stacked ? 1 : 2
    columnSpacing: Widget.padding * 1.5
    rowSpacing: Widget.spacing
    // The current condition, cross-fading as it changes
    CrossFade {
      Layout.alignment: root.stacked ? Qt.AlignHCenter : Qt.AlignVCenter
      value: root._condition?.icon ?? ""
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
        text: root._current ? `${Math.round(root._current.temperature_2m)}${root._unit}` + (root.labelInline ? `  ${root._condition?.label ?? ""}` : "") : ""
        textSize: root.temperatureSize
        font.weight: Style.roleDisplay.weight
      }
      StyledText {
        visible: !root.labelInline
        Layout.fillWidth: true
        horizontalAlignment: root._align
        overflow: "line"
        text: root._condition?.label ?? ""
      }
      StyledText {
        visible: root.showDetails
        Layout.fillWidth: true
        horizontalAlignment: root._align
        role: "caption"
        overflow: "line"
        text: WeatherManager.detailsOf(root.weatherState?.weather ?? null)
      }
    }
  }
}
