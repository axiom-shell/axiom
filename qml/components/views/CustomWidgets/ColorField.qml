pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// One colour of a custom widget element or of the bar (Colors, Bar tab >
// Status color), set in one place, as form rows: a dropdown of the theme's
// colours laid out as a schema colour field (FieldRow's `shortControl`),
// each row painted in its colour (Auto or None first, Custom… then By state…
// last: Custom opens a hex field, By state… turns on rules). With By state…
// picked the row shows the Key the rules read, the rules, each
// "when the key is / isn't / above / below a value, this colour", the first
// that holds winning, and an Otherwise row, the fallback colour. Picking a
// colour again turns the rules off and keeps them. `write(path, value)` writes `path` (a list of keys
// beside this colour's own: [key] or [statesKey, "rules"]) into the owner's
// object (the element's options, the bar). Its top row
// draws no divider when the column is the top of its FormColumn.
// The names and the Auto or None label are runtime keys:
// I18n.tr("Auto") I18n.tr("None") I18n.tr("Accent") I18n.tr("Accent 2")
// I18n.tr("Success") I18n.tr("Warning") I18n.tr("Error") I18n.tr("Info")
// I18n.tr("Red") I18n.tr("Orange") I18n.tr("Yellow") I18n.tr("Green")
// I18n.tr("Cyan") I18n.tr("Blue") I18n.tr("Magenta") I18n.tr("Text")
// I18n.tr("Muted") I18n.tr("Background") I18n.tr("Custom…") I18n.tr("By state…")
FormColumn {
  id: root

  joins: true

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
  // (withCustom) and By state… (withStates). Without Custom… a hex shows as
  // its own swatched row
  function entries(current, withEmpty, withCustom, withStates) {
    const listed = root.names.some(name => name.value === current);
    const own = current !== "" && !listed && (current.charAt(0) !== "#" || !withCustom);
    return (withEmpty ? [
        {
          "value": "",
          "label": I18n.tr(root.emptyLabel)
        }
      ] : []).concat(own ? [root.swatched(current, current)] : [], root.names, withCustom ? [
      {
        "value": "__custom",
        "label": I18n.tr("Custom…")
      }
    ] : [], withStates ? [
      {
        "value": "__states",
        "label": I18n.tr("By state…")
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

  FieldRow {
    label: root.label
    description: root.description
    shortControl: true
    activates: combo
    belowShown: root.custom && !root.statesOn

    StyledComboEntry {
      id: combo
      Layout.fillWidth: true
      // By state… shows while the rules are on, else Custom… while a hex is
      // the colour or has been asked for
      value: root.statesOn ? "__states" : root.custom ? "__custom" : root.value
      options: root.entries(root.value, true, true, true)
      // Room for the colour square drawn in the field
      input.leftPadding: Style.iconSm * 1.6
      onPicked: value => {
        if (value === "__states") {
          root.setEnabled(true);
          return;
        }
        if (root.statesOn)
          root.setEnabled(false);
        root.customPicked = value === "__custom";
        if (value !== "__custom")
          root.write([root.key], value);
      }

      SwatchSquare {
        // Auto, None and By state… show an empty square
        color: Style.resolve(root.statesOn || (root.custom && !root.isHex) ? "" : root.value)
      }
    }

    below: [
      CommitEntry {
        id: hex
        visible: root.custom
        Layout.fillWidth: true
        live: true
        value: root.isHex ? root.value : ""
        input.font.family: "monospace"
        placeholderText: I18n.tr("e.g. {0}", "#ff8800") // style-exempt: an example
        onEdited: text => {
          if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(text))
            root.write([root.key], text);
        }
      },
      StyledText {
        visible: root.custom
        Layout.fillWidth: true
        text: I18n.tr("Doesn't follow the theme")
        role: "caption"
        tone: "muted"
        overflow: "wrap"
      }
    ]
  }

  FieldRow {
    level: 1
    shown: root.statesOn
    label: I18n.tr("Key")
    description: I18n.tr("Empty: what the element shows.")
    shortControl: true
    activates: keyField

    KeyField {
      id: keyField
      Layout.fillWidth: true
      keys: root.keys
      value: root.stateKey
      onPicked: value => root.write([root.statesKey, "key"], value)
    }
  }

  FormRow {
    level: 1
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

            CommitEntry {
              Layout.fillWidth: true
              Layout.minimumWidth: 0
              live: true
              value: rule.item.value ?? ""
              placeholderText: root.stateKey === "state" && root.editor.seenStates.length > 0 ? I18n.tr("e.g. {0}", root.editor.seenStates[0]) : I18n.tr("Value")
              onEdited: text => root.setRule(rule.index, {
                  "value": text
                })
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

      // What no rule matches: the colour the row has
      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledLabel {
          text: I18n.tr("Otherwise")
        }

        StyledComboEntry {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          value: root.value
          options: root.entries(root.value, true, false, false)
          input.leftPadding: Style.iconSm * 1.6
          onPicked: value => root.write([root.key], value)

          SwatchSquare {
            color: Style.resolve(root.value)
          }
        }
      }
    }
  }
}
