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

  width: parent?.width ?? 0
  spacing: Widget.spacing * 2

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

        Surface {
          id: tile
          required property int index
          readonly property var template: CustomWidgetData.galleryPresets[tile.index]
          // The template as a definition (texts in the user's language,
          // defaults filled), and its first sample resolved
          readonly property var definition: ConfigManager.withDefaults(Object.assign({
            "id": "template"
          }, root.editor.translated(tile.template)), "CustomWidget")
          readonly property var sample: Object.values(tile.template.samples ?? ({}))[0] ?? ({})
          readonly property var fields: CustomWidgetsManager.resolveFor(tile.definition, tile.sample)
          readonly property var size: CustomWidgetData.designSize(CustomWidgetData.allElements(tile.definition.module), tile.definition.module.size)
          readonly property real zoom: CustomWidgetData.fitZoom(tile.size, root.card, preview.width, preview.width * 0.6)

          width: tiles.tileWidth
          implicitHeight: column.implicitHeight + Widget.padding * 2
          tone: "surface"

          activeFocusOnTab: true
          Keys.onReturnPressed: root.editor.addTemplate(tile.template)
          Keys.onEnterPressed: root.editor.addTemplate(tile.template)
          Keys.onSpacePressed: root.editor.addTemplate(tile.template)

          StateLayer {
            hovered: area.containsMouse
            pressed: area.pressed
          }

          FocusRing {
            shown: tile.activeFocus
          }

          ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Widget.padding
            spacing: Widget.spacing / 2

            Item {
              id: preview
              Layout.fillWidth: true
              implicitHeight: preview.width * 0.6

              // A module card on the overlay's page colour, as on a page
              Surface {
                anchors.centerIn: parent
                implicitWidth: GridPlacement.span(tile.size[0], root.card) * tile.zoom
                implicitHeight: GridPlacement.span(tile.size[1], root.card) * tile.zoom
                tone: "page"
                clip: true

                Item {
                  width: parent.width / tile.zoom
                  height: parent.height / tile.zoom
                  scale: tile.zoom
                  readonly property real contentZoom: scale
                  transformOrigin: Item.TopLeft

                  CustomLayout {
                    anchors.fill: parent
                    anchors.margins: Widget.cardPadding
                    definition: tile.definition
                    fields: tile.fields
                    actionsEnabled: false
                    viewIndex: CustomWidgetData.pickView(tile.definition.module, tile.fields).index
                  }
                }
              }
            }
            StyledLabel {
              Layout.fillWidth: true
              text: I18n.tr(tile.template.name)
              overflow: "line"
            }
            StyledText {
              Layout.fillWidth: true
              text: I18n.tr(tile.template.description ?? "")
              role: "caption"
              tone: "muted"
              overflow: "wrap"
            }
          }

          MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.editor.addTemplate(tile.template)
          }
        }
      }
    }
  }
}
