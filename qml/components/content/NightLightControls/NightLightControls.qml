pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// The night light (NightLightManager): on or off, how warm (right is
// warmer) and how dim, and its schedule. The sliders save to the NightLight
// settings as they're let go; a switch turns the schedule on and off. A
// big card adds a round button in the light's own color (over the controls,
// or beside them when wide) that switches it. A short card is one row (with
// the warmth when it's wide); compact, a figure that toggles it on a click.
Card {
  id: root

  readonly property bool active: NightLightManager.active
  // Not installed (undefined while it's being looked for)
  readonly property bool missing: NightLightManager.tool === ""
  readonly property int minKelvin: NightLight.minTemperature
  readonly property int maxKelvin: NightLight.maxTemperature
  readonly property int minGamma: NightLight.minGamma
  readonly property int maxGamma: NightLight.maxGamma
  // While a slider is held, what it would save
  property int draggedKelvin: -1
  property int draggedGamma: -1
  readonly property int kelvin: root.draggedKelvin >= 0 ? root.draggedKelvin : NightLight.temperature
  readonly property int gamma: root.draggedGamma >= 0 ? root.draggedGamma : NightLight.gamma
  readonly property string status: root.missing ? I18n.tr("Needs wlsunset") : root.active ? I18n.tr("On · {0} K", root.kelvin) : I18n.tr("Off")

  // One row: the switch, and the warmth beside it when there's width
  readonly property bool strip: root.innerHeight < Appearance.fontSize * 6
  readonly property bool showGamma: root.properties.showGamma && !root.strip && root.innerHeight >= Appearance.fontSize * 11
  readonly property bool showSchedule: root.properties.showSchedule && !root.strip && root.innerHeight >= Appearance.fontSize * 8.5

  // The big button: beside the controls in a wide card, over them in a
  // tall one
  readonly property bool sideBySide: !root.strip && root.innerWidth >= Appearance.fontSize * 26 && root.innerWidth >= root.innerHeight * 1.6 && root.innerHeight >= Appearance.fontSize * 7
  readonly property bool showHero: !root.missing && (root.sideBySide || (!root.strip && root.innerHeight >= Appearance.fontSize * 15 && root.innerWidth >= Appearance.fontSize * 9))
  readonly property real heroSize: root.sideBySide ? Math.min(root.innerHeight, root.innerWidth * 0.35, Appearance.fontSize * 12) : Math.min(root.innerWidth * 0.6, root.innerHeight - controls.implicitHeight - Widget.spacing * 4, Appearance.fontSize * 14)
  readonly property color lightColor: ColorTemperature.color(root.kelvin)
  // What reads on the light's color: a dark or light tint of it
  readonly property color lightInk: Tone.mix(root.lightColor, Tone.bestOn(root.lightColor), 0.8)

  fullMinWidth: Appearance.fontSize * 9
  fullMinHeight: Appearance.fontSize * 2.4

  function kelvinAt(ratio) {
    return Math.round((root.maxKelvin - ratio * (root.maxKelvin - root.minKelvin)) / 100) * 100;
  }
  function gammaAt(ratio) {
    return Math.round(root.minGamma + ratio * (root.maxGamma - root.minGamma));
  }

  function saveKelvin(ratio) {
    SettingsManager.commitValues({
      "NightLight.temperature": root.kelvinAt(ratio)
    });
    root.draggedKelvin = -1;
  }
  function saveGamma(ratio) {
    SettingsManager.commitValues({
      "NightLight.gamma": root.gammaAt(ratio)
    });
    root.draggedGamma = -1;
  }

  compactContent: CompactFigure {
    icon: root.active ? "bedtime" : "bedtime_off"
    iconColor: root.active ? Style.accent : Style.textMuted
    value: root.active ? String(root.kelvin) : ""
    unit: root.active ? "K" : ""
    label: root.active ? I18n.tr("Night light") : I18n.tr("Night light off")
    clickable: !root.missing
    onClicked: ActionsManager.run("nightLight", {
      "fromScreen": true
    })
  }

  // A labelled slider: an icon, the track, the value
  component SettingSlider: RowLayout {
    id: setting
    required property string icon
    required property string valueText
    required property real ratio
    signal moved(real ratio)
    signal released(real ratio)

    Layout.fillWidth: true
    spacing: Widget.spacing
    opacity: root.missing ? Style.opacityDisabled : 1
    enabled: !root.missing

    StyledIcon {
      text: setting.icon
      size: "md"
      tone: "muted"
    }
    StyledSlider {
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.px(16)
      fillColor: root.active ? Style.accent : Style.textFaint
      value: setting.ratio
      onMoved: ratio => setting.moved(ratio)
      onReleased: ratio => setting.released(ratio)
    }
    StyledLabel {
      Layout.preferredWidth: Appearance.fontSize * 3.6
      horizontalAlignment: Text.AlignRight
      text: setting.valueText
      role: "caption"
      tone: "muted"
      font.features: {
        "tnum": 1
      }
    }
  }

  GridLayout {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: root.pad
    columns: root.sideBySide ? 2 : 1
    columnSpacing: root.pad * 1.5
    rowSpacing: Widget.spacing * 2

    // The light's color when on, an outline when off; click to switch
    Rectangle {
      id: hero
      visible: root.showHero
      Layout.alignment: Qt.AlignCenter
      Layout.preferredWidth: root.heroSize
      Layout.preferredHeight: root.heroSize
      radius: width / 2
      color: root.active ? root.lightColor : Style.surfaceHighest
      border.color: root.active ? root.lightColor : Style.borderSubtle
      border.width: Style.hairline

      StateLayer {
        hovered: heroHover.hovered
        pressed: heroTap.pressed
        onAccent: root.active
      }

      ColorGlide on color {}

      ColumnLayout {
        anchors.centerIn: parent
        spacing: 0
        StyledIcon {
          Layout.alignment: Qt.AlignHCenter
          text: root.active ? "bedtime" : "bedtime_off"
          textSize: hero.width * 0.32
          textColor: root.active ? root.lightInk : Style.inkHighest.muted
        }
        StyledText {
          Layout.alignment: Qt.AlignHCenter
          text: root.active ? I18n.tr("{0} K", root.kelvin) : I18n.tr("Off")
          textSize: Math.max(Style.typeCaption, hero.width * 0.11) // fitted: the hero
          textColor: root.active ? root.lightInk : Style.inkHighest.muted
          font.weight: Style.roleDisplay.weight
        }
      }

      HoverHandler {
        id: heroHover
        cursorShape: Qt.PointingHandCursor
      }
      TapHandler {
        id: heroTap
        onTapped: ActionsManager.run("nightLight", {
          "fromScreen": true
        })
      }
    }

    ColumnLayout {
      id: controls
      Layout.fillWidth: true
      Layout.alignment: root.sideBySide ? Qt.AlignVCenter : Qt.AlignCenter
      // Under the button, no wider than it reads well
      Layout.maximumWidth: root.showHero && !root.sideBySide ? Appearance.fontSize * 30 : Number.POSITIVE_INFINITY
      spacing: root.strip ? 0 : Widget.spacing

      // The light: what it is, and its switch
      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledIcon {
          visible: !root.showHero
          text: root.active ? "bedtime" : "bedtime_off"
          size: "md"
          tone: root.active ? "accent" : "muted"
        }
        ColumnLayout {
          Layout.fillWidth: !warmthInline.visible
          Layout.preferredWidth: warmthInline.visible ? Appearance.fontSize * 7 : -1
          spacing: 0
          StyledLabel {
            Layout.fillWidth: true
            text: I18n.tr("Night light")
            font.weight: Style.weightStrong
            overflow: "line"
          }
          StyledLabel {
            Layout.fillWidth: true
            text: root.status
            role: "caption"
            tone: root.missing ? "warning" : root.active ? "accent" : "muted"
            overflow: "line"
          }
        }
        // A wide strip: the warmth in the row
        SettingSlider {
          id: warmthInline
          visible: root.strip && root.innerWidth >= Appearance.fontSize * 24
          icon: "thermostat"
          valueText: I18n.tr("{0} K", root.kelvin)
          ratio: (root.maxKelvin - root.kelvin) / (root.maxKelvin - root.minKelvin)
          onMoved: ratio => root.draggedKelvin = root.kelvinAt(ratio)
          onReleased: ratio => root.saveKelvin(ratio)
        }
        StyledSwitch {
          enabled: !root.missing
          checked: root.active
          onToggled: ActionsManager.run("nightLight", {
            "call": checked ? "open" : "close",
            "fromScreen": true
          })
        }
      }

      SettingSlider {
        visible: !root.strip
        icon: "thermostat"
        valueText: I18n.tr("{0} K", root.kelvin)
        ratio: (root.maxKelvin - root.kelvin) / (root.maxKelvin - root.minKelvin)
        onMoved: ratio => root.draggedKelvin = root.kelvinAt(ratio)
        onReleased: ratio => root.saveKelvin(ratio)
      }

      SettingSlider {
        visible: root.showGamma
        icon: "brightness_6"
        valueText: root.gamma + "%"
        ratio: (root.gamma - root.minGamma) / (root.maxGamma - root.minGamma)
        onMoved: ratio => root.draggedGamma = root.gammaAt(ratio)
        onReleased: ratio => root.saveGamma(ratio)
      }

      // The schedule, and its switch
      RowLayout {
        visible: root.showSchedule
        Layout.fillWidth: true
        Layout.topMargin: Widget.spacing / 2
        spacing: Widget.spacing

        StyledIcon {
          text: "schedule"
          size: "md"
          tone: NightLight.schedule ? "accent" : "muted"
        }
        StyledLabel {
          Layout.fillWidth: true
          text: NightLight.schedule ? I18n.tr("On from {0} to {1}", NightLight.startAt, NightLight.endAt) : I18n.tr("No schedule")
          role: "caption"
          tone: "muted"
          overflow: "line"
        }
        StyledSwitch {
          scale: 0.8 // style-exempt: no text
          checked: NightLight.schedule
          onToggled: SettingsManager.commitValues({
            "NightLight.schedule": checked
          })
        }
      }
    }
  }
}
