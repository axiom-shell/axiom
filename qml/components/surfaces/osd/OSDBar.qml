pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.system
import qs.components.reusable

// One OSD level bar, by its item's type (see an OSD's bars.items in the
// schema):
//   master:     the default output's volume
//   other:      the first playing stream no App bar matches
//   app:        the streams its apps match by name
//   microphone: the default input's volume
//   brightness: this screen's brightness (left out without a controller),
//               or with allMonitors every monitor's at once (their mean)
Loader {
  id: root

  // Its item in the OSD's bars.items, or OSDContent.noBar for none
  required property var entry
  required property string screenName
  // The OSD's own settings: bars run vertically, levels shown as numbers
  property bool vertical: true
  property bool showPercent: true

  // The bar's level changed through the user (not a device switch or a
  // stream appearing): the OSD opens if the entry's showOsd says so
  signal poked

  readonly property int orientation: root.vertical ? Qt.Vertical : Qt.Horizontal
  readonly property string type: entry.type
  readonly property bool isVolume: type === "master" || type === "other" || type === "app"
  // A brightness bar's monitors: every one with a controller, or this one
  readonly property bool allMonitors: type === "brightness" && entry.allMonitors === true
  readonly property var brightnessTargets: root.allMonitors ? BrightnessManager.names : [root.screenName]

  active: type !== "" && (type !== "brightness" || (root.allMonitors ? BrightnessManager.names.length > 0 : BrightnessManager.available(screenName)))
  visible: active
  sourceComponent: isVolume ? volumeBar : (type === "microphone" ? micBar : brightnessBar)

  Component {
    id: volumeBar

    PipewireVolumeBar {
      readonly property bool isMaster: root.type === "master"

      orientation: root.orientation
      showPercent: root.showPercent
      scrollStep: OSDConfig.scrollStep
      targetApps: root.type === "app" ? root.entry.apps : []
      otherApps: root.type === "other"
      excludedApps: root.type === "other" ? OSDConfig.excludedApps : []
      useSystemVolume: isMaster
      iconSource: root.entry.icon || (isMaster ? AudioManager.outputIcon(AudioManager.deviceKind(AudioManager.defaultSink), false, Math.max(AudioManager.volume, 0.01)) : "")

      onPoked: root.poked()
    }
  }

  Component {
    id: micBar

    StyledVolumeBar {
      // A change as the input device switches or binds is the device's
      function _levelChanged() {
        if (AudioManager.sourceSettled())
          root.poked();
      }

      orientation: root.orientation
      showPercent: root.showPercent
      scrollStep: OSDConfig.scrollStep
      volumeLevel: AudioManager.sourceVolume
      isMuted: AudioManager.sourceMuted
      enabled: AudioManager.defaultSource !== null
      iconSource: root.entry.icon || AudioManager.inputIcon(AudioManager.deviceKind(AudioManager.defaultSource), false)
      iconClickable: true
      iconTip: AudioManager.sourceMuted ? I18n.tr("Unmute") : I18n.tr("Mute")
      onVolumeChanged: newVolume => AudioManager.setSourceVolume(newVolume)
      onIconClicked: AudioManager.toggleSourceMute()
      onVolumeLevelChanged: _levelChanged()
      onIsMutedChanged: _levelChanged()
    }
  }

  Component {
    id: brightnessBar

    StyledVolumeBar {
      readonly property real level: root.allMonitors ? BrightnessManager.average(root.brightnessTargets) : BrightnessManager.valueFor(root.screenName)

      orientation: root.orientation
      showPercent: root.showPercent
      scrollStep: OSDConfig.scrollStep
      volumeLevel: level
      iconSource: root.entry.icon || BrightnessManager.icon(level)
      onVolumeChanged: newVolume => BrightnessManager.setMany(root.brightnessTargets, newVolume)

      Connections {
        target: BrightnessManager

        function onBrightnessChanged(name) {
          if (root.brightnessTargets.includes(name))
            root.poked();
        }
      }
    }
  }
}
