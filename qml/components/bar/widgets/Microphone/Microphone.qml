pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.components.bar.widgets.base

// Default input. The icon follows mute and the device type (headset,
// webcam); the background shows when an app is recording from the mic.
// See AudioLevelWidget.
AudioLevelWidget {
  node: AudioManager.defaultSource
  mode: "input"
  hidden: properties.hideWhenIdle && !AudioManager.micInUse && !muted
  icon: AudioManager.inputIcon(AudioManager.deviceKind(node), muted)
  accentField: muted ? "mutedColor" : AudioManager.micInUse ? "activeColor" : "backgroundColor"
}
