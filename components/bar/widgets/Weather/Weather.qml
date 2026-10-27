pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Current conditions (from WeatherManager, for the Weather settings). Hovering opens a 5-day forecast.
BarIconWidget {
  id: root

  Component.onCompleted: WeatherManager.acquire(root)
  Component.onDestruction: WeatherManager.release(root)

  readonly property var current: WeatherManager.current
  readonly property var condition: WeatherManager.condition

  icon: condition?.icon ?? "cloud"
  text: current ? `${Math.round(current.temperature_2m)}°` + (properties.showCondition ? ` ${condition.label}` : "") : "…"

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "WeatherForecast"
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && WeatherManager.weather !== null
  }
}
