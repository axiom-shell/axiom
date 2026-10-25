pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.apps
import qs.components.reusable
import qs.components.content.base

// Current conditions and a 5-day forecast: the Weather widget's popout,
// from WeatherManager's source (the widget keeps it acquired).
Panel {
  id: root

  readonly property var source: WeatherManager.source
  readonly property var current: root.source?.current ?? null
  readonly property var condition: root.source?.condition ?? null
  readonly property var daily: root.source?.weather?.daily ?? null

  spacing: Widget.padding

  implicitWidth: Math.max(Widget.px(300), body.implicitWidth + margins * 2)

  StyledText {
    visible: text !== ""
    text: root.source?.place?.name ?? ""
    font.bold: true
    textColor: Theme.accent
  }

  RowLayout {
    spacing: Widget.padding * 1.5

    // The current condition, cross-fading as it changes
    CrossFade {
      value: root.condition?.icon ?? ""
      delegate: StyledIcon {
        required property var value
        text: value
        textSize: Appearance.fontSize * 3
      }
    }

    ColumnLayout {
      spacing: 2

      StyledText {
        text: root.current ? `${Math.round(root.current.temperature_2m)}${root.source.unitSymbol}  ${root.condition?.label ?? ""}` : ""
        textSize: Appearance.fontSize * 1.3
        font.bold: true
      }
      StyledText {
        text: root.source?.details ?? ""
        textColor: Theme.foregroundAlt
        textSize: Appearance.fontSizeBy(-2)
      }
    }
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
          text: root.source.dayLabel(day.index)
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-2)
        }
        StyledIcon {
          Layout.alignment: Qt.AlignHCenter
          text: root.source.conditionFor(root.daily.weather_code[day.index], 1).icon
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
