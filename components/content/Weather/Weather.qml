pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable
import qs.services.apps
import qs.components.content.parts
import qs.components.content.base

// Current weather, plus the next hours and days where they fit (the days
// beside it in wide slots), centred as one block; compact, the figure (in
// a row along a strip). Same source as the bar widget: the Weather
// settings' location and units.
Card {
  id: root

  readonly property var source: WeatherManager.source
  Component.onCompleted: WeatherManager.acquire(root)
  Component.onDestruction: WeatherManager.release(root)

  readonly property var current: root.source.current
  readonly property var daily: root.source.weather?.daily ?? null
  // What each section needs (px), and what fits in the room inside
  readonly property real currentHeight: Appearance.fontSize * 6
  readonly property real hourlyHeight: Appearance.fontSize * 4.2
  readonly property real dailyHeight: Appearance.fontSize * 1.5 * 7
  readonly property real sectionGap: Widget.spacing * 3
  // Wide slots put the days beside the current weather
  readonly property bool sideBySide: !root.compact && root.innerWidth >= Appearance.fontSize * 36 && root.innerHeight >= root.dailyHeight
  readonly property bool showDaily: !root.compact && (root.sideBySide || root.innerHeight >= root.currentHeight + root.sectionGap + root.dailyHeight)
  readonly property bool showHourly: !root.compact && root.innerWidth >= Appearance.fontSize * 12 && root.innerHeight >= (root.sideBySide ? Math.max(root.currentHeight, root.dailyHeight) : root.currentHeight + (root.showDaily ? root.sectionGap + root.dailyHeight : 0)) + root.sectionGap + root.hourlyHeight
  // Room to spare: a bigger hero and airier days
  readonly property bool roomy: root.innerHeight >= Appearance.fontSize * 30
  // The current weather stacked and centred (tall, narrow and side by side
  // slots), else icon beside the figures
  readonly property bool stacked: !root.compact && (root.shape === "vertical" || root.sideBySide)
  readonly property real heroScale: root.roomy ? 1.5 : 1
  // Most a gap between sections grows; what's left centres the whole block
  readonly property real maxGap: root.pad * 2

  fullMinWidth: Appearance.fontSize * 9
  fullMinHeight: Appearance.fontSize * 6
  // The week's range, which each day's bar is drawn against
  readonly property real weekMin: root.daily ? Math.min(...root.daily.temperature_2m_min) : 0
  readonly property real weekMax: root.daily ? Math.max(...root.daily.temperature_2m_max) : 1

  EmptyState {
    anchors.centerIn: parent
    visible: !root.current
    maxWidth: root.innerWidth
    availableHeight: root.innerHeight
    icon: "cloud"
    text: I18n.tr("Loading weather…")
  }

  // Compact: the condition and temperature
  // (until it's loaded, a cloud)
  compactContent: CompactFigure {
    icon: root.current ? (root.source.condition?.icon ?? "") : "cloud"
    value: root.current ? `${Math.round(root.current.temperature_2m)}°` : ""
    label: root.source.condition?.label ?? ""
  }

  // A flexible gap between sections, up to maxGap
  component Gap: Item {
    Layout.fillHeight: true
    Layout.maximumHeight: root.maxGap
    Layout.minimumHeight: Widget.spacing * 1.5
  }

  // Now, as in the bar's forecast popout: the place, then the icon beside
  // (or over, when stacked) the temperature, condition and details
  component Current: ColumnLayout {
    spacing: Widget.spacing
    StyledText {
      visible: (root.source.place?.name ?? "") !== ""
      Layout.fillWidth: true
      horizontalAlignment: root.stacked ? Text.AlignHCenter : Text.AlignLeft
      elide: Text.ElideRight
      text: root.source.place?.name ?? ""
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
        value: root.source.condition?.icon ?? ""
        delegate: StyledIcon {
          required property var value
          text: value
          textSize: Appearance.fontSize * (root.stacked ? 4 * root.heroScale : 3)
        }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        StyledText {
          Layout.fillWidth: true
          horizontalAlignment: root.stacked ? Text.AlignHCenter : Text.AlignLeft
          text: root.current ? `${Math.round(root.current.temperature_2m)}${root.source.unitSymbol}` : ""
          textSize: Appearance.fontSize * (root.stacked ? 2.4 * root.heroScale : 2)
          font.bold: true
        }
        StyledText {
          Layout.fillWidth: true
          horizontalAlignment: root.stacked ? Text.AlignHCenter : Text.AlignLeft
          elide: Text.ElideRight
          text: root.source.condition?.label ?? ""
        }
        StyledText {
          Layout.fillWidth: true
          horizontalAlignment: root.stacked ? Text.AlignHCenter : Text.AlignLeft
          elide: Text.ElideRight
          text: root.source.details
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-2)
        }
      }
    }
  }

  // The next days: name, icon, low, the day's range against the week's
  // (where there's room), high
  component DailyList: ColumnLayout {
    id: list
    readonly property bool bars: list.width >= Appearance.fontSize * 15
    spacing: root.roomy ? Widget.spacing * 1.5 : Widget.spacing / 2
    Repeater {
      model: root.showDaily ? (root.daily?.time?.length ?? 0) : 0
      RowLayout {
        id: day
        required property int index
        readonly property real low: root.daily.temperature_2m_min[index]
        readonly property real high: root.daily.temperature_2m_max[index]
        Layout.fillWidth: true
        spacing: Widget.spacing * 1.5
        StyledText {
          Layout.preferredWidth: Appearance.fontSize * 3.5
          text: root.source.dayLabel(day.index)
        }
        StyledIcon {
          Layout.preferredWidth: Appearance.fontSize * 1.5
          horizontalAlignment: Text.AlignHCenter
          text: root.source.conditionFor(root.daily.weather_code[day.index], 1).icon
        }
        Item {
          Layout.fillWidth: true
        }
        StyledText {
          Layout.preferredWidth: Appearance.fontSize * 2.2
          horizontalAlignment: Text.AlignRight
          text: `${Math.round(day.low)}°`
          opacity: 0.6
        }
        Rectangle {
          visible: list.bars
          Layout.preferredWidth: list.width * 0.35
          Layout.preferredHeight: Widget.px(4)
          radius: 2
          color: Theme.backgroundAlt
          Rectangle {
            readonly property real span: Math.max(1, root.weekMax - root.weekMin)
            x: parent.width * (day.low - root.weekMin) / span
            width: Math.max(parent.height, parent.width * (day.high - day.low) / span)
            height: parent.height
            radius: 2
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop {
                position: 0
                color: Theme.info
              }
              GradientStop {
                position: 1
                color: Theme.warning
              }
            }
          }
        }
        StyledText {
          Layout.preferredWidth: Appearance.fontSize * 2.2
          horizontalAlignment: Text.AlignRight
          text: `${Math.round(day.high)}°`
          font.bold: true
        }
      }
    }
  }

  // The sections, centred as one block with gaps of at most maxGap
  ColumnLayout {
    visible: root.current !== null
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: 0

    Item {
      Layout.fillHeight: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: root.pad * 2
      Current {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignVCenter
      }
      DailyList {
        visible: root.sideBySide
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignVCenter
      }
    }

    Gap {
      visible: hours.visible || days.visible
    }
    StyledSeparator {
      separatorColor: Theme.accent
      visible: hours.visible || days.visible
      Layout.fillWidth: true
    }
    Gap {
      visible: hours.visible
    }

    // Next hours, evenly spread
    Row {
      id: hours
      visible: root.showHourly
      Layout.fillWidth: true
      readonly property int count: root.showHourly ? Math.max(0, Math.min(12, Math.floor(root.innerWidth / (Appearance.fontSize * 3.5)))) : 0

      Repeater {
        model: hours.count
        Column {
          required property int index
          readonly property var hourly: root.source.weather?.hourly
          width: hours.width / Math.max(1, hours.count)
          spacing: 2
          StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.hourly ? I18n.formatDate(new Date(parent.hourly.time[parent.index]), "HH") : ""
            textColor: Theme.foregroundAlt
            textSize: Appearance.fontSizeBy(-2)
          }
          StyledIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.hourly ? root.source.conditionFor(parent.hourly.weather_code[parent.index], parent.hourly.is_day[parent.index]).icon : ""
            textSize: Appearance.fontSize * 1.4
          }
          StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.hourly ? `${Math.round(parent.hourly.temperature_2m[parent.index])}°` : ""
            textSize: Appearance.fontSizeBy(-1)
          }
        }
      }
    }

    Gap {
      visible: days.visible
    }

    DailyList {
      id: days
      visible: root.showDaily && !root.sideBySide
      Layout.fillWidth: true
    }

    Item {
      Layout.fillHeight: true
    }
  }
}
