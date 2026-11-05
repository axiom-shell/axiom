pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Current conditions and a 5-day forecast: the Weather widget's popout,
// from WeatherManager (the widget keeps it acquired).
Panel {
  id: root

  readonly property var daily: WeatherManager.weather?.daily ?? null

  spacing: Widget.padding

  implicitWidth: Math.max(Widget.px(300), body.implicitWidth + margins * 2)

  WeatherCurrent {
    Layout.fillWidth: true
    spacing: Widget.padding
    labelInline: true
    temperatureSize: Appearance.fontSize * 1.3
  }

  StyledSeparator {
    separatorColor: Theme.accent
    Layout.fillWidth: true
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.padding

    Repeater {
      model: root.daily?.time?.length ?? 0

      ColumnLayout {
        id: day
        required property int index
        Layout.fillWidth: true
        spacing: 2

        StyledText {
          Layout.alignment: Qt.AlignHCenter
          text: WeatherManager.dayLabel(day.index)
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-2)
        }
        StyledIcon {
          Layout.alignment: Qt.AlignHCenter
          text: WeatherManager.conditionFor(root.daily.weather_code[day.index], 1).icon
          textSize: Appearance.fontSize * 1.5
        }
        StyledText {
          Layout.alignment: Qt.AlignHCenter
          text: `${Math.round(root.daily.temperature_2m_max[day.index])}° / ${Math.round(root.daily.temperature_2m_min[day.index])}°`
          textSize: Appearance.fontSizeBy(-2)
        }
      }
    }
  }
}
