pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.forms
import qs.components.content.base

// i18n: keys from the schema (titles, descriptions, type labels)
// Bar editor: the selected widget's options and sizing (as the running
// bars report it), or with nothing selected, the library of widget types
// to drag onto the bar
Item {
  id: root

  required property var dragLayer

  readonly property var selection: BarManager.selectedWidget
  readonly property var widget: BarManager.selectedWidgetConfig()
  // A new form per widget (KeyedLoader)
  readonly property string selectionKey: root.widget ? [BarManager.selectedBarIndex, root.selection.zone, root.selection.index, root.widget.type].join(":") : ""
  // The selected bar's running copies, the screens where one hides the
  // widget for want of room, and how one sizes it (null when none shows it)
  readonly property var reports: BarManager.liveReports()
  readonly property var crowdedOn: root.reports.filter(report => (report.hidden[root.selection.zone] ?? []).includes(root.selection.index)).map(report => report.screen)
  readonly property var measure: root.reports.map(report => report.selected).find(m => m !== null) ?? null

  // How the widget sizes itself, from its policy (BarWidgetHost)
  function sizingText(measure) {
    if (!measure)
      return BarsConfig.widgetLayoutSchema.description ? I18n.tr(BarsConfig.widgetLayoutSchema.description) : "";
    if (measure.policy === "fixed")
      return I18n.tr("A fixed {0} px long.", measure.preferred);
    if (measure.policy === "elastic")
      return I18n.tr("Up to {0} px long, shrinking to {1} px when the bar is crowded; {2} px now.", measure.preferred, measure.minimum, measure.size);
    return I18n.tr("As long as its content: {0} px now.", measure.size);
  }

  Card {
    color: Theme.background
    border.color: Theme.border

    Item {
      anchors.fill: parent
      anchors.margins: Widget.padding

      KeyedLoader {
        anchors.fill: parent
        key: root.selectionKey
        sourceComponent: editor
      }

      Loader {
        anchors.fill: parent
        active: root.selectionKey === ""
        sourceComponent: library
      }
    }
  }

  Component {
    id: editor

    ColumnLayout {
      id: editorRoot

      readonly property string zone: root.selection.zone
      readonly property int index: root.selection.index
      readonly property var widget: root.widget ?? ({})
      readonly property bool hidden: editorRoot.widget.visible === false
      readonly property var propertiesSchema: root.dragLayer.typeInfo(editorRoot.widget.type)?.propertiesSchema ?? ({})
      readonly property var propertiesOrder: root.dragLayer.typeInfo(editorRoot.widget.type)?.propertiesOrder ?? []
      // A page or edge menu it opens, to edit in the layouts editor
      readonly property var opens: OverlayManager.openedBy(editorRoot.widget)

      anchors.fill: parent
      spacing: Widget.spacing

      InspectorHeader {
        icon: root.dragLayer.icon(editorRoot.widget.type)
        title: root.dragLayer.label(editorRoot.widget.type)
        subtitle: {
          const parts = [I18n.tr("{0} section, position {1}", root.dragLayer.zoneLabel(editorRoot.zone), editorRoot.index + 1)];
          if (editorRoot.hidden)
            parts.push(I18n.tr("hidden on the bar"));
          else if (root.crowdedOn.length > 0)
            parts.push(I18n.tr("no room for it on {0}", root.crowdedOn.join(", ")));
          return parts.join(" · ");
        }

        SquareIconButton {
          iconText: editorRoot.hidden ? "visibility_off" : "visibility"
          iconColor: editorRoot.hidden ? Theme.background : Theme.foreground
          backgroundColor: editorRoot.hidden ? Theme.accent : Theme.backgroundAlt
          tooltipText: I18n.tr(editorRoot.hidden ? "Hidden on the bar: click to show it" : "Hide it on the bar, keeping its settings")
          onClicked: BarManager.setWidgetVisible(editorRoot.zone, editorRoot.index, editorRoot.hidden)
        }

        SquareIconButton {
          iconText: "content_copy"
          tooltipText: I18n.tr("Duplicate")
          onClicked: BarManager.duplicateWidget(editorRoot.zone, editorRoot.index)
        }

        SquareIconButton {
          iconText: "delete"
          hoverColor: Theme.error
          tooltipText: I18n.tr("Remove")
          onClicked: BarManager.removeWidget(editorRoot.zone, editorRoot.index)
        }

        SquareIconButton {
          iconText: "close"
          tooltipText: I18n.tr("Close")
          onClicked: BarManager.clearSelection()
        }
      }

      ScrollView {
        id: scroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        contentWidth: availableWidth

        // Each widget keeps its place across the overlay closing
        property ScrollMemory memory: ScrollMemory {
          flickable: scroll.contentItem as Flickable
          key: "BarEditor/" + root.selectionKey
        }

        RowLayout {
          width: scroll.availableWidth
          spacing: Widget.spacing * 2

          ColumnLayout {
            Layout.preferredWidth: Widget.px(3)
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Widget.spacing

            StyledTextButton {
              visible: editorRoot.opens !== null
              iconText: "edit"
              text: I18n.tr("Edit {0} in Layouts", editorRoot.opens?.label ?? "")
              textPadding: Widget.smallPadding
              onClicked: OverlayManager.editOpenedBy(editorRoot.widget)
            }

            // Where its feature is set (the type's `x-link`)
            FieldLinks {
              Layout.fillWidth: true
              links: root.dragLayer.typeInfo(editorRoot.widget.type)?.link
            }

            OptionsGroup {
              propertiesSchema: editorRoot.propertiesSchema
              order: editorRoot.propertiesOrder
              numberMode: "stepper"
              pairs: true
              values: editorRoot.widget.properties ?? ({})
              context: BarsConfig.lookContext(BarManager.selectedBar())
              emptyText: I18n.tr("This widget has no options")
              onEdited: (path, value) => BarManager.updateWidgetProperty(editorRoot.zone, editorRoot.index, path[0], value)
            }
          }

          FieldGroup {
            Layout.preferredWidth: 2
            title: I18n.tr(BarsConfig.widgetLayoutSchema.title)
            description: root.sizingText(root.measure)

            Repeater {
              // An override starts at what the bar uses now (`measured`)
              model: [
                {
                  "key": "size",
                  "measured": "preferred",
                  "initial": 100
                },
                {
                  "key": "minSize",
                  "measured": "minimum",
                  "initial": 0
                },
                {
                  "key": "priority",
                  "measured": "priority",
                  "initial": 0
                }
              ]

              delegate: LayoutOverrideField {
                required property var modelData
                key: modelData.key
                initial: root.measure?.[modelData.measured] ?? modelData.initial
                fieldSchema: BarsConfig.widgetLayoutSchema.properties?.[modelData.key] ?? ({})
                value: editorRoot.widget.layout?.[modelData.key]
                onEdited: value => BarManager.updateWidgetLayout(editorRoot.zone, editorRoot.index, modelData.key, value)
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: library

    ColumnLayout {
      spacing: Widget.spacing

      CardHeader {
        title: I18n.tr("Widget library")
        showActions: false
      }

      StyledText {
        Layout.fillWidth: true
        text: I18n.tr("Drag a widget onto a section, or click one to add it to the {0} section. Click a widget in a section to edit it.", root.dragLayer.zoneLabel(BarManager.lastZone))
        opacity: 0.6
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.WordWrap
      }

      TypeLibrary {
        id: widgetLibrary
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: Widget.spacing / 2
        types: BarsConfig.availableWidgetTypes
        groups: OverlayConfig.libraryGroups
        grouped: EditsManager.libraryGrouped
        // Schema keys (labels, group names)
        labelOf: type => I18n.tr(type.label)
        headingOf: name => name ? I18n.tr(name) : I18n.tr("Other")
        minColumns: 2
        onGroupingChosen: grouped => EditsManager.setLibraryGrouped(grouped)

        delegate: WidgetChip {
          id: tile
          required property var modelData
          dragLayer: root.dragLayer
          implicitWidth: widgetLibrary.tileWidth
          type: tile.modelData.type
          payload: ({
              "kind": "add",
              "type": tile.modelData.type
            })
          onClicked: BarManager.addWidget(BarManager.lastZone, tile.modelData.type)
        }
      }
    }
  }
}
