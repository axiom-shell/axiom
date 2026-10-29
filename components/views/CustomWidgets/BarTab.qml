pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.ui
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.forms

// i18n: keys from the schema (titles, descriptions)
// Custom widgets page, Bar tab: the widget as it's drawn on a bar across
// and on one down the side (the real bar widget, on the first bar's
// look), then its bar style, its text (Waybar's format, icons and
// states) and its actions.
ColumnLayout {
  id: root

  required property var grid
  readonly property var editor: CustomWidgetsManager.editor
  readonly property var definition: root.editor.selected
  readonly property var schema: ConfigManager.configSchema.definitions.CustomWidget.properties
  // The bar the previews take their look from, and that turned on its side
  readonly property var barConfig: ScreenEdgeManager.bars[0] ?? null
  readonly property var verticalBar: root.barConfig ? Object.assign({}, root.barConfig, {
    "vertical": true
  }) : null
  // The widget's own settings in a bar, with this definition
  readonly property var widgetProperties: ConfigManager.withDefaults({
    "id": "preview",
    "type": "CustomWidget",
    "properties": {
      "definition": root.editor.selectedId,
      "popout": {
        "enabled": false
      }
    }
  }, "BarWidget").properties

  width: parent?.width ?? 0
  spacing: Widget.spacing * 2

  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("Preview")

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing * 3

      BarPreview {
        barConfig: root.barConfig
      }
      BarPreview {
        barConfig: root.verticalBar
      }
      Item {
        Layout.fillWidth: true
      }
    }
  }

  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("On the bar")

    SchemaPropertiesForm {
      Layout.fillWidth: true
      propertiesSchema: root.schema.bar.properties
      order: ["style", "icon", "segments", "width", "colorText", "popout"]
      values: root.definition?.bar ?? ({})
      onEdited: (path, value) => root.editor.set(["bar"].concat(path), value)
    }
  }

  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("Text")

    SchemaPropertiesForm {
      Layout.fillWidth: true
      propertiesSchema: Utils.pick(root.schema, order)
      order: ["format", "maxLength", "escape", "hideEmpty", "tooltip"]
      values: root.definition ?? ({})
      onEdited: (path, value) => root.editor.set(path, value)
    }

    JsonField {
      label: I18n.tr("Icons")
      description: I18n.tr("Waybar's format-icons, as {icon} in the format: a list picked by percentage [\"a\", \"b\"], or by alt {\"playing\": \"a\", \"default\": \"b\"}.")
      key: "formatIcons"
    }
    JsonField {
      label: I18n.tr("State colours")
      description: I18n.tr("A class or state → a theme colour, {\"charging\": \"success\"}. ok, warning and critical are already known.")
      key: "states"
    }
  }

  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("Actions")
    description: I18n.tr("Run by clicks and scrolls on the bar widget, as Waybar's on-click.")

    SchemaPropertiesForm {
      Layout.fillWidth: true
      propertiesSchema: root.schema.actions.properties
      values: root.definition?.actions ?? ({})
      onEdited: (path, value) => root.editor.set(["actions"].concat(path), value)
    }
  }

  // The bar widget itself, on a strip of the bar's background
  component BarPreview: Rectangle {
    id: preview
    property var barConfig: null
    readonly property bool vertical: preview.barConfig?.vertical ?? false
    implicitWidth: preview.vertical ? (preview.barConfig?.widgetSize ?? 0) + Widget.padding * 2 : Math.max(Appearance.fontSize * 10, ((widget.item as Item)?.implicitWidth ?? 0) + Widget.padding * 2)
    implicitHeight: preview.vertical ? Math.max(Appearance.fontSize * 8, ((widget.item as Item)?.implicitHeight ?? 0) + Widget.padding * 2) : (preview.barConfig?.widgetSize ?? 0) + Widget.padding * 2
    radius: Appearance.borderRadius
    color: Theme.background
    border.color: Theme.border
    border.width: Appearance.borderWidth

    Loader {
      id: widget
      anchors.centerIn: parent
      active: preview.barConfig !== null && root.editor.selectedId !== ""
      Component.onCompleted: widget.setSource(Qt.resolvedUrl("../../bar/widgets/CustomWidget/CustomWidget.qml"), {
        "barConfig": Qt.binding(() => preview.barConfig),
        "properties": Qt.binding(() => root.widgetProperties),
        "panel": null,
        "screen": null
      })
    }
  }

  // A JSON value of the definition, typed: written once it parses
  component JsonField: ColumnLayout {
    id: json
    property string label
    property string description
    property string key
    property bool bad: false
    Layout.fillWidth: true
    spacing: Widget.spacing / 2

    StyledText {
      text: json.label
    }
    StyledTextArea {
      id: area
      Layout.fillWidth: true
      expandable: true
      input.font.family: "monospace"
      onTextEdited: {
        try {
          const value = JSON.parse(area.text.trim() || "{}");
          json.bad = false;
          root.editor.set(json.key, value);
        } catch (e) {
          json.bad = true;
        }
      }
      Component.onCompleted: area.text = JSON.stringify(root.definition?.[json.key] ?? {})
    }
    StyledText {
      Layout.fillWidth: true
      text: json.bad ? I18n.tr("Not valid JSON yet.") : json.description
      textColor: json.bad ? Theme.warning : Theme.foreground
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
      opacity: json.bad ? 1 : 0.6
    }
  }
}
