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
import qs.components.views.base
import qs.components.bar.look

// Custom widgets page, Bar tab: one banner across the page holding the
// widget as it's drawn on a bar across and on one down the side (the real
// bar widget, on the first bar's look) and a caption, then its bar style, its text (Waybar's format, icons and
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
  // The widget's own settings in a bar, with this definition, its Auto
  // colours picked as that bar picks a lone widget's
  readonly property var widgetProperties: {
    const widget = ConfigManager.withDefaults({
      "id": "preview",
      "type": "CustomWidget",
      "properties": {
        "definition": root.editor.selectedId,
        "popout": {
          "enabled": false
        }
      }
    }, "BarWidget");
    if (!root.barConfig)
      return widget.properties;
    return BarsConfig.withAutoColors({
      "center": [widget]
    }, root.barConfig.look).center[0].properties;
  }

  width: parent?.width ?? 0
  spacing: Widget.spacing * 2

  // One banner across the page: the widget on a bar across and on one down
  // the side, and what it shows
  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("Preview")

    Rectangle {
      Layout.fillWidth: true
      radius: Appearance.borderRadius
      // Stands in for a bar's background at its default look: the page colour
      color: Style.surfacePage
      border.color: Style.borderSubtle
      border.width: Style.hairline
      implicitHeight: bannerRow.implicitHeight + Widget.padding * 2

      RowLayout {
        id: bannerRow
        anchors.fill: parent
        anchors.margins: Widget.padding
        spacing: Widget.spacing * 3

        BarPreview {
          Layout.alignment: Qt.AlignVCenter
          barConfig: root.barConfig
        }
        BarPreview {
          Layout.alignment: Qt.AlignVCenter
          barConfig: root.verticalBar
        }
        StyledText {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          role: "caption"
          tone: "muted"
          overflow: "wrap"
          text: I18n.tr("How it looks on the bar, with the last output.")
        }
      }
    }
  }

  // The other groups flow into columns, as a Settings card's rows do
  GroupColumns {
    Layout.fillWidth: true

    FieldGroup {
      Layout.fillWidth: true
      title: I18n.tr("On the bar")

      SchemaPropertiesForm {
        Layout.fillWidth: true
        propertiesSchema: root.schema.bar.properties
        order: ["style", "icon", "segments", "width", "popout"]
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
        editor: root.editor
        definition: root.definition
        label: I18n.tr("Icons")
        description: I18n.tr("Waybar's format-icons, as {icon} in the format: a list picked by percentage [\"a\", \"b\"], or by alt {\"playing\": \"a\", \"default\": \"b\"}.")
        path: "formatIcons"
      }
      JsonField {
        editor: root.editor
        definition: root.definition
        label: I18n.tr("State colours")
        description: I18n.tr("A class or state → a theme colour, {\"charging\": \"success\"}. ok, warning and critical are already known.")
        path: "states"
      }
    }

    FieldGroup {
      Layout.fillWidth: true
      title: I18n.tr("Actions")
      description: I18n.tr("Run by clicks and scrolls on the bar widget, as Waybar's on-click. A named action runs the action command (Script) instead of the command.")

      SchemaPropertiesForm {
        Layout.fillWidth: true
        propertiesSchema: root.schema.actions.properties
        values: root.definition?.actions ?? ({})
        onEdited: (path, value) => root.editor.set(["actions"].concat(path), value)
      }
    }
  }

  // The bar widget itself, standing on the banner, over the
  // background its WidgetGroup would draw (a lone widget's caps: the
  // bar's widget style and shape, the pill's fill)
  component BarPreview: Item {
    id: preview
    property var barConfig: null
    readonly property bool vertical: preview.barConfig?.vertical ?? false
    readonly property var item: widget.item
    readonly property var segment: preview.barConfig ? BarShapes.segment(preview.barConfig.look.shape, "separate", true, 0, 1, preview.barConfig.thickness, preview.item?.contentAcross) : null
    // The room its caps keep clear of its content (BarWidget's
    // contentAcross), as its BarWidgetHost adds
    readonly property real ends: preview.segment ? preview.segment.lead + preview.segment.trail : 0
    implicitWidth: preview.vertical ? (preview.barConfig?.thickness ?? 0) + Widget.padding * 2 : Math.max(Appearance.fontSize * 10, (preview.item?.implicitWidth ?? 0) + preview.ends + Widget.padding * 2)
    implicitHeight: preview.vertical ? Math.max(Appearance.fontSize * 8, (preview.item?.implicitHeight ?? 0) + preview.ends + Widget.padding * 2) : (preview.barConfig?.thickness ?? 0) + Widget.padding * 2

    Loader {
      anchors.centerIn: parent
      active: preview.item !== null && preview.segment !== null
      sourceComponent: WidgetBackground {
        width: preview.item.width + (preview.vertical ? 0 : preview.ends)
        height: preview.item.height + (preview.vertical ? preview.ends : 0)
        barConfig: preview.barConfig
        colors: preview.item.hasBackground ? preview.item.colors : null
        startCap: preview.segment.startCap
        endCap: preview.segment.endCap
        shownStart: preview.segment.shownStart
        backgroundLevel: preview.item.backgroundLevel
        backgroundLevelColor: preview.item.backgroundLevelColor
      }
    }

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
}
