pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.methods
import qs.components.forms
import qs.components.content.base

// i18n: keys from the schema (titles, descriptions, module labels)
// Layouts editor, below the canvas: the selected module's options, with
// its size beside them; a group selected together, its count and Remove;
// with nothing selected, the library of modules to add.
Item {
  id: root

  required property var dragLayer
  readonly property GridEditor editor: root.dragLayer.editor
  // Whether there are modules to edit (a Custom page or a menu)
  property bool editable: true
  // The subtitle with nothing selected, when not editable
  property string notEditableHint: ""
  readonly property int index: root.editor.selected
  readonly property var module: root.editor.selectedModule()
  readonly property string moduleType: root.module?.type ?? ""
  // A required module (x-required) stays: no Duplicate or Remove
  readonly property bool removable: root.module !== null && !OverlayConfig.isRequired(root.moduleType)
  readonly property var place: root.module?.place ?? null
  // Modules selected together (GridEditor.group)
  readonly property int groupCount: root.editor.group.length
  // A new form per module (KeyedLoader)
  readonly property string selectionKey: root.module ? [root.editor.scopeKey, root.index, root.moduleType].join(":") : ""

  Card {
    color: Theme.background
    border.color: Theme.border

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Widget.padding
      spacing: Widget.spacing

      InspectorHeader {
        icon: root.groupCount > 0 ? "select_all" : root.module ? root.dragLayer.moduleIcon(root.moduleType) : "extension"
        filled: root.module !== null || root.groupCount > 0
        title: root.groupCount > 0 ? I18n.tr("{0} modules", root.groupCount) : root.module ? root.dragLayer.moduleLabel(root.moduleType) : I18n.tr("Library")
        subtitle: root.groupCount > 0 ? I18n.tr("Drag one to move them all, or use the arrow keys") : root.place ? I18n.tr("{0} × {1} cards", GridPlacement.cards(root.place.w), GridPlacement.cards(root.place.h)) : root.editable ? I18n.tr("Click a module on the canvas to edit it, or drag a box to select several") : root.notEditableHint

        // Centre the selection across or down: on the screen, or among the
        // other modules (GridEditor.planCentre). Dimmed, but still saying
        // why, when it's centred already or can't be exactly
        Repeater {
          // I18n.tr("Centre horizontally") I18n.tr("Centre vertically")
          model: [
            {
              "axis": "x",
              "icon": "align_horizontal_center",
              "label": "Centre horizontally"
            },
            {
              "axis": "y",
              "icon": "align_vertical_center",
              "label": "Centre vertically"
            }
          ]

          SquareIconButton {
            id: centreButton
            required property var modelData
            readonly property var plan: root.editor.planCentre(centreButton.modelData.axis)
            readonly property bool can: centreButton.plan !== null && centreButton.plan.valid && !centreButton.plan.noop
            visible: centreButton.plan !== null
            opacity: centreButton.can ? 1 : 0.4
            iconText: centreButton.modelData.icon
            tooltipText: {
              if (!centreButton.plan)
                return "";
              if (centreButton.plan.offCentre)
                return I18n.tr("Can't be centred exactly: it would sit between grid units");
              if (centreButton.plan.noop)
                return I18n.tr("Centred");
              if (!centreButton.plan.valid)
                return I18n.tr("No room to centre it");
              return I18n.tr(centreButton.modelData.label);
            }
            onClicked: {
              if (centreButton.can)
                root.editor.centreSelection(centreButton.modelData.axis);
            }
          }
        }

        SquareIconButton {
          visible: root.removable
          iconText: "content_copy"
          tooltipText: I18n.tr("Duplicate")
          onClicked: root.editor.duplicateModule(root.index)
        }

        SquareIconButton {
          visible: root.removable
          iconText: "delete"
          hoverColor: Theme.error
          tooltipText: I18n.tr("Remove")
          onClicked: root.editor.removeModule(root.index)
        }

        SquareIconButton {
          visible: root.groupCount > 0
          iconText: "delete"
          hoverColor: Theme.error
          tooltipText: I18n.tr("Remove")
          onClicked: root.editor.removeSelection()
        }

        SquareIconButton {
          visible: root.module !== null || root.groupCount > 0
          iconText: "close"
          tooltipText: I18n.tr("Close")
          onClicked: root.editor.clearSelection()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Widget.spacing * 2

        // Left: the module's options, or the library
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredWidth: Widget.px(3)

          KeyedLoader {
            anchors.fill: parent
            key: root.selectionKey
            sourceComponent: options
          }

          // Streamed in after the page (StreamedLoader); kept once built
          StreamedLoader {
            anchors.fill: parent
            visible: root.selectionKey === "" && root.editable && root.groupCount === 0
            label: "module library"

            sourceComponent: ModuleLibrary {
              dragLayer: root.dragLayer
            }
          }
        }

        // Right: its size
        ScrollView {
          id: sizeScroll
          visible: root.module !== null
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredWidth: 2
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
          contentWidth: availableWidth

          FieldGroup {
            width: sizeScroll.availableWidth
            title: I18n.tr("Size")
            description: I18n.tr("In quarter cards. Drag an edge or corner on the canvas, or step it here.")

            Repeater {
              // I18n.tr("Width") I18n.tr("Height")
              model: [
                {
                  "label": "Width",
                  "axis": 0
                },
                {
                  "label": "Height",
                  "axis": 1
                }
              ]

              SchemaNumberField {
                id: sizeField
                required property var modelData
                readonly property bool across: sizeField.modelData.axis === 0
                // The size it can grow to before what it pushes would leave
                // the grid (or it reaches the most a module takes), keeping
                // the other side
                readonly property int grows: {
                  if (!root.place)
                    return 1;
                  let n = sizeField.currentConfigValue;
                  while (n < GridPlacement.maxSpan && root.editor.canResize(root.index, sizeField.across ? n + 1 : root.place.w, sizeField.across ? root.place.h : n + 1))
                    n++;
                  return n;
                }
                label: sizeField.modelData.label
                currentConfigValue: root.place ? (sizeField.across ? root.place.w : root.place.h) : 1
                minimum: 1
                maximum: sizeField.grows
                mode: "stepper"
                showCoarse: false
                // The field stays as the selection changes
                debounced: false
                onCommitted: value => root.editor.resizeModule(root.index, GridPlacement.resizeFrom(root.place, "se", sizeField.across ? value - root.place.w : 0, sizeField.across ? 0 : value - root.place.h))
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: options

    ScrollView {
      id: optionsScroll
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      contentWidth: availableWidth

      // Each module keeps its place across the overlay closing
      property ScrollMemory memory: ScrollMemory {
        flickable: optionsScroll.contentItem as Flickable
        key: "Layouts/" + root.selectionKey
      }

      ColumnLayout {
        width: optionsScroll.availableWidth
        spacing: Widget.spacing

        // Where its feature is set (the type's `x-link`)
        FieldLinks {
          Layout.fillWidth: true
          links: OverlayConfig.moduleInfo(root.moduleType)?.link
        }

        OptionsGroup {
          Layout.fillWidth: true
          propertiesSchema: OverlayConfig.moduleInfo(root.moduleType)?.propertiesSchema ?? ({})
          order: OverlayConfig.moduleInfo(root.moduleType)?.propertiesOrder ?? []
          values: root.module?.properties ?? ({})
          emptyText: I18n.tr("This module has no options")
          onEdited: (path, value) => root.editor.updateModuleProperty(root.index, path[0], value)
        }
      }
    }
  }
}
