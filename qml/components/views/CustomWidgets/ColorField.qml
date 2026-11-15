pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// One colour of a custom widget element or of the bar (Colors, Bar tab >
// Status color), set in one place: a dropdown of the theme's colours, each
// row painted in its colour (Auto or None first, Custom… last, which opens
// a hex field), then "Color by state": a switch that turns on rules, each
// "when the key is / isn't / above / below a value, this colour", the first
// that holds winning and the colour above the fallback. The rules are kept
// while it is off. `write(path, value)` writes `path` (a list of keys
// beside this colour's own: [key] or [statesKey, "rules"]) into the owner's
// object (the element's options, the bar). `first` marks the top row of its
// group (Utils.firstFormRow's job, as for every InspectorRow).
// The names and the Auto or None label are runtime keys:
// I18n.tr("Auto") I18n.tr("None") I18n.tr("Accent") I18n.tr("Accent 2")
// I18n.tr("Success") I18n.tr("Warning") I18n.tr("Error") I18n.tr("Info")
// I18n.tr("Red") I18n.tr("Orange") I18n.tr("Yellow") I18n.tr("Green")
// I18n.tr("Cyan") I18n.tr("Blue") I18n.tr("Magenta") I18n.tr("Text")
// I18n.tr("Muted") I18n.tr("Background") I18n.tr("Custom…")
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor

  // The colour square drawn at the left inside a colour dropdown (the
  // dropdown's `input.leftPadding` makes room); each sets its `color`
  // qmllint disable Quick.layout-positioning
  component SwatchSquare: Rectangle {
    anchors.left: parent.left
    anchors.leftMargin: Widget.padding
    anchors.top: parent.top
    anchors.topMargin: (Widget.height - Style.iconSm) / 2
    width: Style.iconSm
    height: Style.iconSm
    radius: Style.radiusInner
    border.width: Style.hairline
    border.color: Style.borderStrong
  }
  // qmllint enable Quick.layout-positioning
  // The title and description of the colour, as its schema has them
  property string label: ""
  property string description: ""
  // The colour's name ("" Auto or None), its "Color by state" object
  // (CustomColorStates: `statesValue`) and their keys beside each other
  property string key: ""
  property string statesKey: ""
  property string value: ""
  property var statesValue: ({})
  // What "" means: "Auto" or "None" (the schema's x-emptyLabel)
  property string emptyLabel: "Auto"
  // The keys a rule can read (KeyField.keys)
  property var keys: []
  property bool first: false
  property var write: (path, value) => {}

  readonly property bool isHex: root.value.charAt(0) === "#"
  // Custom… was picked and no hex is typed yet
  property bool customPicked: false
  readonly property bool custom: root.isHex || root.customPicked
  readonly property bool statesOn: root.statesValue?.enabled ?? false
  readonly property var rules: root.statesValue?.rules ?? []
  readonly property string stateKey: root.statesValue?.key ?? ""

  // The theme's colours: value -> label, in the order they are offered
  readonly property var names: [
    {
      "value": "accent",
      "label": I18n.tr("Accent")
    },
    {
      "value": "accentAlt",
      "label": I18n.tr("Accent 2")
    },
    {
      "value": "success",
      "label": I18n.tr("Success")
    },
    {
      "value": "warning",
      "label": I18n.tr("Warning")
    },
    {
      "value": "error",
      "label": I18n.tr("Error")
    },
    {
      "value": "info",
      "label": I18n.tr("Info")
    },
    {
      "value": "red" // style-exempt: a theme colour name
      ,
      "label": I18n.tr("Red")
    },
    {
      "value": "orange" // style-exempt: a theme colour name
      ,
      "label": I18n.tr("Orange")
    },
    {
      "value": "yellow" // style-exempt: a theme colour name
      ,
      "label": I18n.tr("Yellow")
    },
    {
      "value": "green" // style-exempt: a theme colour name
      ,
      "label": I18n.tr("Green")
    },
    {
      "value": "cyan" // style-exempt: a theme colour name
      ,
      "label": I18n.tr("Cyan")
    },
    {
      "value": "blue" // style-exempt: a theme colour name
      ,
      "label": I18n.tr("Blue")
    },
    {
      "value": "magenta" // style-exempt: a theme colour name
      ,
      "label": I18n.tr("Magenta")
    },
    {
      "value": "foreground",
      "label": I18n.tr("Text")
    },
    {
      "value": "foregroundInactive",
      "label": I18n.tr("Muted")
    },
    {
      "value": "background",
      "label": I18n.tr("Background")
    }
  ].map(name => root.swatched(name.value, name.label))

  // One row of the dropdown: painted in the colour it names, its label in
  // the ink that reads on it, picked once per option here
  function swatched(value, label) {
    return {
      "value": value,
      "label": label,
      "swatch": value,
      "swatchInk": String(Tone.bestOn(Style.resolve(value))) // style-exempt: a swatch row shows the colour it names, its ink is picked once per option, here
    };
  }

  // The dropdown's rows: the theme's colours, a stored name that isn't one
  // (a base0X) under its own name, and, first, Auto / None, last Custom…
  function entries(current, withEmpty, withCustom) {
    const listed = root.names.some(name => name.value === current);
    return (withEmpty ? [
        {
          "value": "",
          "label": I18n.tr(root.emptyLabel)
        }
      ] : []).concat(current === "" || current.charAt(0) === "#" || listed ? [] : [root.swatched(current, current)], root.names, withCustom ? [
      {
        "value": "__custom",
        "label": I18n.tr("Custom…")
      }
    ] : []);
  }

  // A rule's colour with another field changed
  function setRule(index, patch) {
    root.write([root.statesKey, "rules"], root.rules.map((rule, i) => i === index ? Object.assign({}, rule, patch) : rule));
  }

  // The switch: on with no rules makes one, "is" the first state seen when
  // the key is `state`, in the error colour. Off keeps the rules
  function setEnabled(on) {
    const seen = root.editor.seenStates[0] ?? "";
    const rule = {
      "test": "is",
      "value": root.stateKey === "state" ? seen : "",
      "color": "error"
    };
    root.write([root.statesKey], Object.assign({}, root.statesValue, {
      "enabled": on,
      "rules": on && root.rules.length === 0 ? [rule] : root.rules
    }));
  }

  spacing: 0
  Layout.fillWidth: true

  onValueChanged: if (!root.isHex)
    root.customPicked = false

  InspectorRow {
    first: root.first
    label: root.label
    description: root.description

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledComboEntry {
        id: combo
        Layout.fillWidth: true
        // Custom… shows while a hex is the colour or has been asked for
        value: root.custom ? "__custom" : root.value
        options: root.entries(root.value, true, true)
        // Room for the colour square drawn in the field
        input.leftPadding: Style.iconSm * 1.6
        onPicked: value => {
          root.customPicked = value === "__custom";
          if (value !== "__custom")
            root.write([root.key], value);
        }

        SwatchSquare {
          // Auto and None show an empty square
          color: Style.resolve(root.custom && !root.isHex ? "" : root.value)
        }
      }
    }

    StyledTextEntry {
      id: hex
      visible: root.custom
      Layout.fillWidth: true
      input.font.family: "monospace"
      placeholderText: I18n.tr("e.g. {0}", "#ff8800") // style-exempt: an example
      onTextEdited: {
        if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(hex.text))
          root.write([root.key], hex.text);
      }
      Binding {
        target: hex
        property: "text"
        value: root.isHex ? root.value : ""
        when: !hex.input.activeFocus
        restoreMode: Binding.RestoreNone
      }
    }

    StyledText {
      visible: root.custom
      Layout.fillWidth: true
      text: I18n.tr("Doesn't follow the theme")
      role: "caption"
      tone: "muted"
      overflow: "wrap"
    }
  }

  FormRow {
    id: switchRow
    tinted: false
    bodyHeight: stateSwitch.implicitHeight

    SchemaSwitch {
      id: stateSwitch
      width: parent.width
      label: I18n.tr("Color by state")
      description: I18n.tr("Pick the color from a value in the output.")
      checked: root.statesOn
      onToggled: on => root.setEnabled(on)
    }
  }

  InspectorRow {
    indented: true
    shown: root.statesOn
    label: I18n.tr("Key")
    description: I18n.tr("Empty: what the element shows.")

    KeyField {
      Layout.fillWidth: true
      keys: root.keys
      value: root.stateKey
      onPicked: value => root.write([root.statesKey, "key"], value)
    }
  }

  FormRow {
    indented: true
    shown: root.statesOn
    tinted: false
    bodyHeight: rulesColumn.implicitHeight

    ColumnLayout {
      id: rulesColumn
      width: parent.width
      spacing: Widget.spacing

      // By count, over the saved rules (config, never live values)
      Repeater {
        model: root.rules.length

        ColumnLayout {
          id: rule
          required property int index
          readonly property var item: root.rules[rule.index] ?? ({})
          Layout.fillWidth: true
          Layout.bottomMargin: Widget.spacing
          spacing: Widget.spacing / 2

          RowLayout {
            Layout.fillWidth: true
            spacing: Widget.spacing

            StyledComboEntry {
              Layout.preferredWidth: Widget.px(88)
              Layout.minimumWidth: 0
              value: rule.item.test ?? "is"
              options: root.editor.ruleTests
              onPicked: value => root.setRule(rule.index, {
                  "test": value
                })
            }

            StyledTextEntry {
              id: valueEntry
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              placeholderText: root.stateKey === "state" && root.editor.seenStates.length > 0 ? I18n.tr("e.g. {0}", root.editor.seenStates[0]) : I18n.tr("Value")
              onTextEdited: root.setRule(rule.index, {
                "value": valueEntry.text
              })
              Binding {
                target: valueEntry
                property: "text"
                value: rule.item.value ?? ""
                when: !valueEntry.input.activeFocus
                restoreMode: Binding.RestoreNone
              }
            }

            FlatIconButton {
              iconText: "close"
              tooltipText: I18n.tr("Remove this rule")
              onClicked: root.write([root.statesKey, "rules"], root.rules.filter((r, i) => i !== rule.index))
            }
          }

          StyledComboEntry {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            value: rule.item.color ?? ""
            options: root.entries(rule.item.color ?? "", false, false)
            input.leftPadding: Style.iconSm * 1.6
            onPicked: value => root.setRule(rule.index, {
                "color": value
              })

            SwatchSquare {
              color: Style.resolve(rule.item.color ?? "")
            }
          }
        }
      }

      StyledTextButton {
        implicitHeight: Widget.height
        kind: "text"
        iconText: "add"
        text: I18n.tr("Add a rule")
        enabled: root.rules.length < 16
        onClicked: root.write([root.statesKey, "rules"], root.rules.concat([
          {
            "test": "is",
            "value": "",
            "color": "error"
          }
        ]))
      }

      StyledText {
        Layout.fillWidth: true
        text: I18n.tr("Otherwise: the color above.")
        role: "caption"
        tone: "muted"
        overflow: "wrap"
      }
    }
  }
}
