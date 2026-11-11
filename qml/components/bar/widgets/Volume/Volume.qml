pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.components.bar.widgets.base

// Default output volume. The icon follows mute, level and the device type
// (headphones, headset, Bluetooth, HDMI). See AudioLevelWidget.
AudioLevelWidget {
  node: AudioManager.defaultSink
  mode: "output"
  icon: AudioManager.outputIcon(AudioManager.deviceKind(node), deviceMuted, level)
  accentField: deviceMuted ? "mutedColor" : "backgroundColor"
}
