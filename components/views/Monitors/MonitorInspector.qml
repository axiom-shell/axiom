pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.reusable
import qs.components.forms
import qs.components.methods

// The selected monitor's settings in the selected profile: on/off,
// primary, mode, scale, rotation, mirroring, position, and (folded) VRR,
// bit depth and color.
// Form labels, translated by the Schema* widgets: I18n.tr("Enabled")
// I18n.tr("Primary") I18n.tr("Resolution") I18n.tr("Refresh rate")
// I18n.tr("Scale") I18n.tr("Mirror") I18n.tr("Variable refresh rate")
// I18n.tr("10-bit color") I18n.tr("Color mode") I18n.tr("SDR brightness")
// I18n.tr("SDR saturation") I18n.tr("X") I18n.tr("Y")
ColumnLayout {
  id: root

  readonly property var rule: MonitorManager.selectedRule
  readonly property string output: rule?.output ?? ""
  readonly property var monitor: MonitorManager.monitorFor(rule)
  readonly property var mode: MonitorLayout.parseMode(rule?.mode)
  // The monitor's modes, or just the rule's own when it isn't connected
  readonly property var modes: {
    const list = MonitorLayout.parseModes(root.monitor?.availableModes ?? []);
    if (root.mode && !list.some(m => m.width === root.mode.width && m.height === root.mode.height))
      list.push({
        "width": root.mode.width,
        "height": root.mode.height,
        "rates": [root.mode.rate]
      });
    return list;
  }
  readonly property string resolution: root.mode ? `${root.mode.width}x${root.mode.height}` : "preferred"
  readonly property var rates: (root.modes.find(m => `${m.width}x${m.height}` === root.resolution)?.rates ?? []).map(rate => MonitorLayout.formatRate(rate))
  readonly property bool advancedOpen: MonitorManager.advancedOpen
  // An HDR color mode, where SDR content's brightness and saturation apply
  readonly property bool hdr: CompositorManager.supports.monitorColor === true && (root.rule?.cm === "hdr" || root.rule?.cm === "hdredid")

  function set(key, value) {
    MonitorManager.setField(root.output, key, value);
  }

  spacing: Widget.spacing * 2

  StyledText {
    visible: !root.rule
    text: I18n.tr("Select a monitor")
    opacity: 0.6
  }

  ColumnLayout {
    visible: !!root.rule
    Layout.fillWidth: true
    spacing: 2

    StyledText {
      text: MonitorManager.labelFor(root.rule)
      textSize: Appearance.fontSizeBy(2)
      font.bold: true
      Layout.fillWidth: true
      elide: Text.ElideRight
    }

    StyledText {
      text: root.monitor ? root.monitor.description : I18n.tr("Not connected")
      opacity: 0.7
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }
  }

  StyledTextButton {
    visible: !!root.rule && !root.monitor
    text: I18n.tr("Remove from this layout")
    iconText: "delete"
    implicitHeight: Widget.height
    onClicked: MonitorManager.forgetOutput(root.output)
  }

  RowLayout {
    visible: !!root.rule
    Layout.fillWidth: true
    spacing: Widget.spacing * 2

    SchemaSwitch {
      label: "Enabled"
      checked: !(root.rule?.disabled ?? false)
      onToggled: value => root.set("disabled", !value)
    }

    SchemaSwitch {
      visible: !!root.monitor
      label: "Primary"
      checked: !!root.monitor && root.monitor.name === General.primaryMonitor
      onToggled: value => MonitorManager.setPrimary(value ? root.monitor.name : "")
    }
  }

  // What the primary monitor decides
  SettingsLink {
    id: primaryLink
    visible: primaryLink.available && !!root.monitor
    Layout.fillWidth: true
    setting: "General.primaryMonitor"
  }

  // Everything else only applies to a monitor that's on. Each setting is
  // a FormRow, as in a schema form: a divider between them, and the ones
  // that come and go (a mirror's position, Advanced) fold open and shut
  ColumnLayout {
    visible: !!root.rule && !root.rule.disabled
    Layout.fillWidth: true
    spacing: 0

    FormRow {
      first: true
      bodyHeight: resolutionField.implicitHeight

      SchemaComboBox {
        id: resolutionField
        width: parent.width
        label: "Resolution"
        options: ["preferred"].concat(root.modes.map(m => `${m.width}x${m.height}`))
        optionLabels: ({
            "preferred": I18n.tr("Preferred")
          })
        currentValue: root.resolution
        onSelectionChanged: value => {
          const picked = root.modes.find(m => `${m.width}x${m.height}` === value);
          root.set("mode", picked ? MonitorLayout.formatMode(picked.width, picked.height, picked.rates[0]) : "preferred");
        }
      }
    }

    FormRow {
      shown: root.rates.length > 0
      bodyHeight: rateField.implicitHeight

      SchemaComboBox {
        id: rateField
        width: parent.width
        label: "Refresh rate"
        options: root.rates
        optionLabels: root.rates.reduce((labels, rate) => {
          labels[rate] = I18n.tr("{0} Hz", rate);
          return labels;
        }, {})
        currentValue: root.mode ? MonitorLayout.formatRate(root.mode.rate) : ""
        onSelectionChanged: value => root.set("mode", MonitorLayout.formatMode(root.mode.width, root.mode.height, Number(value)))
      }
    }

    FormRow {
      bodyHeight: scaleField.implicitHeight

      SchemaComboBox {
        id: scaleField
        readonly property var size: root.mode ?? (root.monitor ? {
            "width": root.monitor.width,
            "height": root.monitor.height
          } : null)
        readonly property var scales: size ? MonitorLayout.validScales(size.width, size.height, root.rule?.scale) : [root.rule?.scale ?? 1]
        width: parent.width
        label: "Scale"
        options: scales.map(scale => String(scale))
        optionLabels: scales.reduce((labels, scale) => {
          labels[String(scale)] = size ? I18n.tr("{0}% ({1}×{2})", Math.round(scale * 1000) / 10, Math.round(size.width / scale), Math.round(size.height / scale)) : I18n.tr("{0}%", Math.round(scale * 100));
          return labels;
        }, {})
        currentValue: String(root.rule?.scale ?? 1)
        onSelectionChanged: value => root.set("scale", Number(value))
      }
    }

    FormRow {
      bodyHeight: rotationRow.implicitHeight

      ColumnLayout {
        id: rotationRow
        width: parent.width
        spacing: Widget.spacing

        StyledText {
          text: I18n.tr("Rotation")
          font.weight: Font.Medium
        }

        RowLayout {
          spacing: Widget.spacing

          SegmentRow {
            Repeater {
              model: [0, 90, 180, 270]

              delegate: SegmentButton {
                required property int modelData
                required property int index
                readonly property bool selected: (root.rule?.transform ?? 0) % 4 === index
                implicitHeight: Widget.height
                text: `${modelData}°`
                active: selected
                Layout.fillWidth: false
                onClicked: root.set("transform", index + ((root.rule?.transform ?? 0) >= 4 ? 4 : 0))
              }
            }
          }

          Item {
            Layout.fillWidth: true
          }

          StyledText {
            text: I18n.tr("Flipped")
            font.weight: Font.Medium
          }

          StyledSwitch {
            checked: (root.rule?.transform ?? 0) >= 4
            onToggled: root.set("transform", (root.rule?.transform ?? 0) % 4 + (checked ? 4 : 0))
          }
        }
      }
    }

    FormRow {
      shown: CompositorManager.supports.monitorMirror === true && (mirrorField.targets.length > 0 || !!root.rule?.mirror)
      bodyHeight: mirrorField.implicitHeight

      SchemaComboBox {
        id: mirrorField
        readonly property var targets: MonitorManager.rules.filter(other => other.output !== root.output && !other.disabled && !other.mirror)
        width: parent.width
        label: "Mirror"
        options: [""].concat(targets.map(other => other.output))
        optionLabels: targets.reduce((labels, other) => {
          labels[other.output] = MonitorManager.labelFor(other);
          return labels;
        }, {
          "": I18n.tr("Off")
        })
        currentValue: root.rule?.mirror ?? ""
        onSelectionChanged: value => root.set("mirror", value)
      }
    }

    FormRow {
      shown: !root.rule?.mirror
      bodyHeight: xField.implicitHeight

      SchemaNumberField {
        id: xField
        width: parent.width
        label: "X"
        mode: "stepper"
        unit: "px"
        minimum: -32768
        maximum: 32768
        currentConfigValue: root.rule?.x ?? 0
        onCommitted: value => MonitorManager.move(root.output, value, root.rule.y)
      }
    }

    FormRow {
      shown: !root.rule?.mirror
      bodyHeight: yField.implicitHeight

      SchemaNumberField {
        id: yField
        width: parent.width
        label: "Y"
        mode: "stepper"
        unit: "px"
        minimum: -32768
        maximum: 32768
        currentConfigValue: root.rule?.y ?? 0
        onCommitted: value => MonitorManager.move(root.output, root.rule.x, value)
      }
    }

    // Advanced, folded
    FormRow {
      bodyHeight: advancedRow.implicitHeight

      MouseArea {
        width: parent.width
        height: advancedRow.implicitHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: MonitorManager.advancedOpen = !MonitorManager.advancedOpen

        RowLayout {
          id: advancedRow
          anchors.fill: parent
          spacing: Widget.spacing

          StyledIcon {
            text: root.advancedOpen ? "expand_more" : "chevron_right"
            textColor: Theme.accent
          }

          StyledText {
            text: I18n.tr("Advanced")
            font.bold: true
            Layout.fillWidth: true
          }
        }
      }
    }

    FormRow {
      shown: root.advancedOpen
      bodyHeight: vrrField.implicitHeight

      SchemaComboBox {
        id: vrrField
        width: parent.width
        label: "Variable refresh rate"
        options: ["0", "1", "2", "3"]
        optionLabels: ({
            "0": I18n.tr("Off"),
            "1": I18n.tr("On"),
            "2": I18n.tr("Fullscreen only"),
            "3": I18n.tr("Fullscreen games and video")
          })
        currentValue: String(root.rule?.vrr ?? 0)
        onSelectionChanged: value => root.set("vrr", Number(value))
      }
    }

    FormRow {
      shown: root.advancedOpen
      bodyHeight: bitDepthField.implicitHeight

      SchemaSwitch {
        id: bitDepthField
        width: parent.width
        label: "10-bit color"
        checked: root.rule?.bitdepth === 10
        onToggled: value => root.set("bitdepth", value ? 10 : 8)
      }
    }

    FormRow {
      shown: root.advancedOpen && CompositorManager.supports.monitorColor === true
      bodyHeight: colorModeField.implicitHeight

      SchemaComboBox {
        id: colorModeField
        width: parent.width
        label: "Color mode"
        options: ["auto", "srgb", "dcip3", "dp3", "adobe", "wide", "edid", "hdr", "hdredid"]
        optionLabels: ({
            "auto": I18n.tr("Automatic"),
            "srgb": "sRGB",
            "dcip3": "DCI-P3",
            "dp3": "Display P3",
            "adobe": "Adobe RGB",
            "wide": I18n.tr("Wide gamut (BT2020)"),
            "edid": I18n.tr("From the monitor (EDID)"),
            "hdr": "HDR",
            "hdredid": I18n.tr("HDR from the monitor (EDID)")
          })
        currentValue: root.rule?.cm ?? "auto"
        onSelectionChanged: value => root.set("cm", value)
      }
    }

    FormRow {
      shown: root.advancedOpen && root.hdr
      bodyHeight: sdrBrightnessField.implicitHeight

      SchemaNumberField {
        id: sdrBrightnessField
        width: parent.width
        label: "SDR brightness"
        unit: "%"
        minimum: 50
        maximum: 200
        currentConfigValue: Math.round((root.rule?.sdrBrightness ?? 1) * 100)
        onCommitted: value => root.set("sdrBrightness", value / 100)
      }
    }

    FormRow {
      shown: root.advancedOpen && root.hdr
      bodyHeight: sdrSaturationField.implicitHeight

      SchemaNumberField {
        id: sdrSaturationField
        width: parent.width
        label: "SDR saturation"
        unit: "%"
        minimum: 50
        maximum: 200
        currentConfigValue: Math.round((root.rule?.sdrSaturation ?? 1) * 100)
        onCommitted: value => root.set("sdrSaturation", value / 100)
      }
    }
  }
}
