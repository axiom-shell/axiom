pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.session
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Caffeine (IdleManager): the IdleInhibitor widget's popout, or an overlay
// card. A switch for on until turned off; off, a CountdownTimer (as the
// one-off timer's) to keep awake for a set time: a typed duration or one
// of the `presets`, then the time left, pause, more time and reset (which
// turns it off). On with no timer it says so, with turn off and set a
// timer. Compact, the time left or on/off.
// properties (card): { presets }
Panel {
  id: root

  // Popout: filled from the anchor's extraData, the widget's presets
  property var presets: []
  readonly property var shownPresets: root.embedded ? root.properties.presets ?? [] : root.presets
  // On with no timer: picking one (set a timer) shows the presets again
  property bool pickingTimer: false
  readonly property bool untilOff: IdleManager.caffeine && !IdleManager.caffeineTimed && !root.pickingTimer

  spacing: Widget.spacing
  wantsKeyboardFocus: true
  implicitWidth: Math.max(Appearance.fontSize * 20, body.implicitWidth + margins * 2)
  fullMinWidth: Appearance.fontSize * 10
  fullMinHeight: Appearance.fontSize * 9

  Component.onCompleted: IdleManager.acquire(root, 1000)
  Component.onDestruction: IdleManager.release(root)

  // A timer started or caffeine gone off ends the picking
  Connections {
    target: IdleManager
    function onCaffeineTimedChanged() {
      root.pickingTimer = false;
    }
    function onCaffeineChanged() {
      root.pickingTimer = false;
    }
  }

  compactContent: CompactFigure {
    icon: IdleManager.caffeine ? "coffee" : "bedtime"
    iconColor: IdleManager.caffeine ? Theme.accent : Theme.foregroundAlt
    value: IdleManager.caffeineTimed ? IdleManager.caffeineText : IdleManager.caffeine ? I18n.tr("On") : I18n.tr("Off")
    label: I18n.tr("Caffeine")
  }

  ModuleHeader {
    icon: IdleManager.caffeine ? "coffee" : "bedtime"
    iconColor: IdleManager.caffeine ? Theme.accent : Theme.foregroundAlt
    title: I18n.tr("Caffeine")

    StyledSwitch {
      checked: IdleManager.caffeine
      onToggled: IdleManager.setCaffeine(checked)
    }
  }

  // On until turned off
  Loader {
    active: root.untilOff
    visible: active
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    Layout.preferredHeight: root.embedded ? 0 : -1
    sourceComponent: Item {
      implicitWidth: awake.implicitWidth
      implicitHeight: awake.implicitHeight

      ColumnLayout {
        id: awake
        // A short card loses the figure and the line under the title first
        readonly property bool showFigure: !root.embedded || parent.height >= Appearance.fontSize * 9
        anchors.centerIn: parent
        width: parent.width
        spacing: Widget.spacing

        StyledIcon {
          visible: awake.showFigure
          Layout.alignment: Qt.AlignHCenter
          text: "coffee"
          textColor: Theme.accent
          // Larger in a roomy card
          textSize: root.embedded ? Math.max(Appearance.fontSize * 3.2, Math.min(Appearance.fontSize * 6, awake.parent.height * 0.3)) : Appearance.fontSize * 3.2
        }
        StyledText {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: I18n.tr("Awake until turned off")
          font.bold: true
        }
        StyledText {
          visible: awake.showFigure
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: I18n.tr("The screen won't lock or turn off while you're away.")
          textSize: Appearance.fontSizeBy(-1)
          textColor: Theme.foregroundAlt
        }
        RowLayout {
          Layout.alignment: Qt.AlignHCenter
          Layout.topMargin: Widget.spacing / 2
          spacing: Widget.spacing / 2

          StyledTextButton {
            implicitHeight: Widget.height - Widget.px(4)
            iconText: "power_settings_new"
            text: I18n.tr("Turn off")
            onClicked: IdleManager.setCaffeine(false)
          }
          StyledTextButton {
            implicitHeight: Widget.height - Widget.px(4)
            iconText: "timer"
            text: I18n.tr("Set a timer")
            onClicked: root.pickingTimer = true
          }
        }
      }
    }
  }

  // Off, timed, or picking a timer
  CountdownTimer {
    visible: !root.untilOff
    timer: IdleManager.caffeineTimer
    presets: root.shownPresets
    text: IdleManager.caffeineText
    progress: IdleManager.caffeineProgress
    label: I18n.tr("Awake")
    fill: root.embedded
    idleIcon: IdleManager.caffeine ? "coffee" : "bedtime"
    placeholderText: I18n.tr("30m, 1h30m, 90s…")
    moreTime: 15 * 60000
    moreTimeText: I18n.tr("15 more minutes")
    resetText: I18n.tr("Turn off")
    onStarted: text => IdleManager.startCaffeineText(text)
    onToggled: IdleManager.toggleCaffeineTimer()
    onReset: IdleManager.setCaffeine(false)
    onExtended: ms => IdleManager.addCaffeineTime(ms)
  }

  StyledTextButton {
    visible: root.pickingTimer
    Layout.alignment: Qt.AlignHCenter
    implicitHeight: Widget.height - Widget.px(4)
    iconText: "arrow_back"
    text: I18n.tr("Keep on with no timer")
    onClicked: root.pickingTimer = false
  }
}
