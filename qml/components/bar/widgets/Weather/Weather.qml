pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.apps
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Current conditions (from WeatherManager, for the Weather settings' place,
// in its own `units`). Hovering opens a 5-day forecast, or says why there's
// no weather.
// Stacked: the temperature over the condition.
BarWidget {
  id: root

  // Re-acquiring replaces the old request
  readonly property var weatherRequest: ({
      "location": "",
      "units": root.properties.units
    })
  onWeatherRequestChanged: WeatherManager.acquire(root, weatherRequest)
  Component.onCompleted: WeatherManager.acquire(root, weatherRequest)
  Component.onDestruction: WeatherManager.release(root)

  readonly property var weatherState: WeatherManager.stateFor(root.weatherRequest)
  readonly property string weatherError: root.weatherState?.error ?? ""
  readonly property var current: root.weatherState?.weather?.current ?? null
  readonly property var condition: WeatherManager.conditionOf(root.weatherState?.weather ?? null)

  icon: condition?.icon ?? (root.weatherError ? "cloud_off" : "cloud")
  text: current ? `${Math.round(current.temperature_2m)}°` + (properties.showCondition ? ` ${condition.label}` : "") : "…"

  styleText: current ? `${Math.round(current.temperature_2m)}°` : "…"
  subtext: current ? condition.label : ""

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "WeatherForecast"
    extraData: ({
        "units": root.properties.units
      })
    active: MenusConfig.opensOwnPopout(root.properties) && (root.weatherState?.weather ?? null) !== null
  }

  // With no weather, why, on the bar's inner side
  BarToolTip {
    widget: root
    shown: root.weatherError !== ""
    text: I18n.tr("Couldn't load the weather: {0}", root.weatherError)
  }
}
