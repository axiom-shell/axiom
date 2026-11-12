pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Current conditions (from WeatherManager, for the Weather settings). Hovering opens a 5-day forecast,
// or says why there's no weather.
// Stacked: the temperature over the condition.
BarWidget {
  id: root

  Component.onCompleted: WeatherManager.acquire(root)
  Component.onDestruction: WeatherManager.release(root)

  readonly property var current: WeatherManager.current
  readonly property var condition: WeatherManager.condition

  icon: condition?.icon ?? (WeatherManager.error ? "cloud_off" : "cloud")
  text: current ? `${Math.round(current.temperature_2m)}°` + (properties.showCondition ? ` ${condition.label}` : "") : "…"

  styleText: current ? `${Math.round(current.temperature_2m)}°` : "…"
  subtext: current ? condition.label : ""

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "WeatherForecast"
    active: MenusConfig.opensOwnPopout(root.properties) && WeatherManager.weather !== null
  }

  // With no weather, why, on the bar's inner side
  BarToolTip {
    widget: root
    shown: WeatherManager.error !== ""
    text: I18n.tr("Couldn't load the weather: {0}", WeatherManager.error)
  }
}
