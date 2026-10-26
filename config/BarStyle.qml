pragma Singleton
import QtQuick
import qs.services.core

// Reader for Bars.style: how every bar draws its widgets, accents and
// shadow, unless its own style sets a key (BarsConfig.lookOf). Previews of the
// Bars section show live (the bar editor's).
QtObject {
  // The style's values by key ({ fontSize, widgetRadius, widgetStyle, …,
  // shadow: { enabled, color, size } }), as a bar's own would be
  readonly property var values: (ConfigManager.previews.Bars ?? ConfigManager.config.Bars).style
  // The look surfaces draw their shadow in, the way a bar's look is
  // (BarsConfig.lookOf): the style with its shadow as flat shadow / shadowColor /
  // shadowSize
  readonly property var look: Object.assign({}, values, {
    "shadow": values.shadow.enabled,
    "shadowColor": values.shadow.color,
    "shadowSize": values.shadow.size
  })
  // Whether surfaces cast the shadow
  readonly property bool shadowed: values.shadow.enabled
}
