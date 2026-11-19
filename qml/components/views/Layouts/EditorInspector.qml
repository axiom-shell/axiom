pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.methods
import qs.components.forms
import qs.components.views.base

// Layouts editor, below the canvas: the selected module's options, with
// its size beside them; a group selected together, its count and Remove;
// with nothing selected, the library of modules to add. An InspectorCard that
// doesn't scroll: its two panes scroll inside themselves.
Item {
  id: root

  required property var dragLayer
  readonly property GridEditor editor: root.dragLayer.editor
  // Whether there are modules to edit (a Custom page or a menu)
  property bool editable: true
  // The subtitle with nothing selected, when not editable
  property string notEditableHint: ""
  // The line under a module's Content size, given its own size (a % or
  // null): what it comes to on this surface (EditTarget.moduleSizingNote)
  property var moduleNote: contentSize => ""
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

  InspectorCard {
    anchors.fill: parent
    scrolls: false

    header: InspectorHeader {
      icon: root.groupCount > 0 ? "select_all" : root.module ? root.dragLayer.moduleIcon(root.moduleType) : "extension"
      filled: root.module !== null || root.groupCount > 0
      title: root.groupCount > 0 ? I18n.tr("{0} modules", root.groupCount) : root.module ? root.dragLayer.moduleLabel(root.moduleType) : I18n.tr("Library")
      // (With nothing selected the canvas's status line says what to do)
      subtitle: root.groupCount > 0 ? I18n.tr("Drag one to move them all, or use the arrow keys") : root.place ? I18n.tr("{0} × {1} cards", GridPlacement.cards(root.place.w), GridPlacement.cards(root.place.h)) : root.editable ? "" : root.notEditableHint
      canDuplicate: root.removable
      onDuplicate: root.editor.duplicateModule(root.index)
      canRemove: root.removable || root.groupCount > 0
      onRemove: {
        if (root.groupCount > 0)
          root.editor.removeSelection();
        else
          root.editor.removeModule(root.index);
      }
      closable: root.module !== null || root.groupCount > 0
      onClose: root.editor.clearSelection()

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
          opacity: centreButton.can ? 1 : Style.opacityDisabled
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
      CardScroll {
        id: sizeScroll
        visible: root.module !== null
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 2

        FieldGroup {
          Layout.fillWidth: true
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

            FormRow {
              id: sizeRow
              required property var modelData
              required property int index
              bodyHeight: sizeField.implicitHeight

              SchemaNumberField {
                id: sizeField
                width: parent.width
                readonly property var modelData: sizeRow.modelData
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

    CardScroll {
      id: optionsScroll
      anchors.fill: parent

      // Each module keeps its place across the overlay closing
      property ScrollMemory memory: ScrollMemory {
        flickable: optionsScroll.flickable as Flickable
        key: "Layouts/" + root.selectionKey
      }

      // Where its feature is set (the type's `x-link`)
      FieldLinks {
        Layout.fillWidth: true
        links: OverlayConfig.moduleInfo(root.moduleType)?.link
      }

      // Its own Content size, on top of its page's or menu's
      SchemaPropertiesForm {
        Layout.fillWidth: true
        visible: !!OverlayConfig.moduleInfo(root.moduleType)?.contentSize
        propertiesSchema: ({
            "contentSize": OverlayConfig.moduleInfo(root.moduleType)?.contentSize
          })
        order: ["contentSize"]
        values: root.module ?? ({})
        fieldNote: () => root.moduleNote(root.module?.contentSize ?? null)
        onEdited: (path, value) => root.editor.updateModuleField(root.index, path[0], value)
      }

      OptionsGroup {
        Layout.fillWidth: true
        propertiesSchema: OverlayConfig.moduleInfo(root.moduleType)?.propertiesSchema ?? ({})
        order: OverlayConfig.moduleInfo(root.moduleType)?.propertiesOrder ?? []
        values: root.module?.properties ?? ({})
        emptyText: I18n.tr("This module has no options")
        // A Submenu module's menu can be a new one, made here
        fieldAction: (path, schema) => root.moduleType === "Submenu" && path[0] === "menu" && OverlayManager.editTarget === "menu" ? {
            "text": I18n.tr("New submenu…"),
            "icon": "add",
            "run": () => OverlayManager.menus.addSubmenu(root.index)
          } : null
        onEdited: (path, value) => root.editor.updateModuleProperty(root.index, path[0], value)
      }
    }
  }
}
