pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.apps
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts.custom

// Custom widgets page, the inspector pane while picking a template for an
// interactive card: each one drawn from its own sample (CustomWidgetData.
// galleryPresets have a sample per screen (all but Daily habits have no
// command), so they preview before any script exists). A click adds it and opens it on the Module tab, at its first
// screen.
ColumnLayout {
  id: root

  readonly property var editor: CustomWidgetsManager.editor
  // One grid unit's card in pixels the previews are fitted from
  readonly property real card: Widget.px(400)

  // A module card on the overlay's page colour, as on a page, at the size it
  // has there, scaled into the tile
  Component {
    id: modulePreview

    Item {
      id: sample
      required property var definition
      required property var fields
      required property var size

      ZoomFrame {
        anchors.fill: parent
        naturalWidth: GridPlacement.span(sample.size[0], root.card)
        naturalHeight: GridPlacement.span(sample.size[1], root.card)
        minZoom: 0.05

        Surface {
          anchors.fill: parent
          tone: "page"

          CustomLayout {
            anchors.fill: parent
            anchors.margins: Widget.cardPadding
            definition: sample.definition
            fields: sample.fields
            actionsEnabled: false
            viewIndex: CustomWidgetData.pickView(sample.definition.module, sample.fields).index
          }
        }
      }
    }
  }

  width: parent?.width ?? 0
  spacing: Style.cardGap

  FieldGroup {
    Layout.fillWidth: true
    title: I18n.tr("Interactive card")
    description: I18n.tr("Pick a look to start from. Each has a sample for each of its screens, so it shows before your script exists: point it at yours, and it comes alive.")
    headerExtras: StyledTextButton {
      implicitHeight: Widget.smallHeight
      iconText: "close"
      text: I18n.tr("Cancel")
      onClicked: root.editor.gallery = false
    }

    // By count over the shipped templates
    TileFlow {
      id: tiles
      Layout.fillWidth: true
      minTileWidth: Appearance.fontSize * 14

      Repeater {
        model: CustomWidgetData.galleryPresets.length

        // A template's tile, its description as the tile's caption
        PreviewTile {
          id: cell
          required property int index
          readonly property var template: CustomWidgetData.galleryPresets[cell.index]
          // The template as a definition (texts in the user's language,
          // defaults filled), and its first sample resolved
          readonly property var definition: ConfigManager.withDefaults(Object.assign({
            "id": "template"
          }, root.editor.translated(cell.template)), "CustomWidget")
          readonly property var sample: Object.values(cell.template.samples ?? ({}))[0] ?? ({})
          readonly property var fields: CustomWidgetsManager.resolveFor(cell.definition, cell.sample)
          readonly property var size: CustomWidgetData.designSize(CustomWidgetData.allElements(cell.definition.module), cell.definition.module.size)

          width: tiles.tileWidth
          title: I18n.tr(cell.template.name)
          caption: I18n.tr(cell.template.description ?? "")
          previewHeight: tiles.tileWidth * 0.6
          preview: modulePreview
          previewProperties: ({
              "definition": cell.definition,
              "fields": cell.fields,
              "size": cell.size
            })
          onClicked: root.editor.addTemplate(cell.template)
        }
      }
    }
  }
}
