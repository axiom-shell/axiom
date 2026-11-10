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
// Bar editor, beside the board: the selected widget's options and sizing
// (as the running bars report it) and the library of widget types to drag
// onto the bar, side by side (inspector about 55%), or one over the other
// when the room is taller than wide
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

  // One over the other when the room is taller than wide
  readonly property bool stacked: root.height > root.width
  readonly property real _gap: OverlayConfig.cardSpacing
  // The inspector's length along the split (about 55%); the library has
  // the rest past the gap
  readonly property real _inspectorLength: Math.round(((root.stacked ? root.height : root.width) - root._gap) * 0.55)
  readonly property real _libraryLength: (root.stacked ? root.height : root.width) - root._gap - root._inspectorLength

  // Each card fills its box (Card)
  Item {
    width: root.stacked ? root.width : root._inspectorLength
    height: root.stacked ? root._inspectorLength : root.height

    Card {
      color: Theme.background
      border.color: Theme.border
    }

    Item {
      anchors.fill: parent
      anchors.margins: Widget.padding

      KeyedLoader {
        anchors.fill: parent
        key: root.selectionKey
        sourceComponent: editor
      }

      // Nothing selected
      ColumnLayout {
        anchors.fill: parent
        visible: root.selectionKey === ""
        spacing: Widget.spacing

        InspectorHeader {
          icon: "touch_app"
          filled: false
          title: I18n.tr("No widget selected")
          subtitle: I18n.tr("Click a widget in a section to edit it, right-click it for more.")
        }

        Item {
          Layout.fillHeight: true
        }
      }
    }
  }

  Item {
    x: root.stacked ? 0 : root.width - width
    y: root.stacked ? root.height - height : 0
    width: root.stacked ? root.width : root._libraryLength
    height: root.stacked ? root._libraryLength : root.height

    Card {
      color: Theme.background
      border.color: Theme.border
    }

    Loader {
      anchors.fill: parent
      anchors.margins: Widget.padding
      sourceComponent: library
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
      readonly property var typeInfo: root.dragLayer.typeInfo(editorRoot.widget.type)
      readonly property var propertiesSchema: editorRoot.typeInfo?.propertiesSchema ?? ({})
      readonly property var propertiesOrder: editorRoot.typeInfo?.propertiesOrder ?? []
      // It shrinks when crowded (`x-elastic`), so it takes a minimum and
      // maximum length
      readonly property bool elastic: editorRoot.typeInfo?.elastic ?? false

      anchors.fill: parent
      spacing: Widget.spacing

      InspectorHeader {
        icon: root.dragLayer.icon(editorRoot.widget.type)
        title: root.dragLayer.widgetLabel(editorRoot.widget)
        subtitle: {
          const parts = [I18n.tr("{0} section, position {1}", root.dragLayer.zoneLabel(editorRoot.zone), editorRoot.index + 1)];
          if (editorRoot.hidden)
            parts.push(I18n.tr("hidden on the bar"));
          else if (root.crowdedOn.length > 0)
            parts.push(I18n.tr("no room for it on {0}", root.crowdedOn.join(", ")));
          return parts.join(" · ");
        }
        showsLinks: opensLink.available || typeLinks.shows
        // What it opens, then where its feature is set (the type's `x-link`)
        links: [
          SettingsLink {
            id: opensLink
            widget: editorRoot.widget
          },
          FieldLinks {
            id: typeLinks
            links: editorRoot.typeInfo?.link
          }
        ]

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

        // Where every bar's widget look is set (the bar's own, if it takes
        // one, is in the bar's Style groups)
        SquareIconButton {
          readonly property SettingsLink link: SettingsLink {
            setting: "Bars.style"
          }

          visible: link.available
          iconText: "palette"
          tooltipText: link.label
          onClicked: link.follow()
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

        // Options, then sizing, each the inspector's full width
        ColumnLayout {
          width: scroll.availableWidth
          spacing: Widget.spacing * 2

          ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Widget.spacing

            OptionsGroup {
              propertiesSchema: editorRoot.propertiesSchema
              order: editorRoot.propertiesOrder
              numberMode: "stepper"
              pairs: true
              values: editorRoot.widget.properties ?? ({})
              context: BarsConfig.lookContext(BarManager.selectedBar())
              emptyText: I18n.tr("This widget has no options")
              changedAt: path => BarManager.widgetPropertyChanged(editorRoot.zone, editorRoot.index, path[0])
              // An edge menu picker (its popout's menu, a Button's click
              // menu) can open a new menu, made and saved at once
              fieldAction: (path, schema) => schema?.["x-options"] === "edgeMenus" ? {
                  "text": I18n.tr("New menu…"),
                  "icon": "add",
                  "run": () => OverlayManager.newMenuFor(editorRoot.zone, editorRoot.index, path)
                } : null
              onEdited: (path, value) => BarManager.updateWidgetProperty(editorRoot.zone, editorRoot.index, path[0], value)
              onDiscardAt: path => BarManager.discardWidgetProperty(editorRoot.zone, editorRoot.index, path[0])
            }
          }

          FieldGroup {
            Layout.fillWidth: true
            title: I18n.tr(BarsConfig.widgetLayoutSchema.title)
            description: root.sizingText(root.measure)

            Repeater {
              // A fixed model: one built from the widget would be rebuilt
              // by every edit, dropping a field mid-step. The minimum and
              // maximum only for an elastic widget.
              model: ["maxSize", "minSize", "priority"]

              delegate: LayoutOverrideField {
                required property string modelData
                key: modelData
                visible: editorRoot.elastic || modelData === "priority"
                // An override starts at what the bar uses now, a size
                // without its insets (which maxSize and minSize don't count)
                initial: {
                  if (modelData === "priority")
                    return root.measure?.priority ?? BarManager.priorityOf(editorRoot.widget);
                  if (!root.measure)
                    return modelData === "maxSize" ? 100 : 0;
                  return Math.max(0, root.measure[modelData === "maxSize" ? "preferred" : "minimum"] - root.measure.insets);
                }
                fieldSchema: BarsConfig.widgetLayoutSchema.properties?.[modelData] ?? ({})
                value: editorRoot.widget.layout?.[modelData]
                onEdited: value => BarManager.updateWidgetLayout(editorRoot.zone, editorRoot.index, modelData, value)
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
        text: I18n.tr("Drag a widget onto a section, or click one to add it to the {0} section.", root.dragLayer.zoneLabel(BarManager.lastZone))
        opacity: 0.6
        textSize: Appearance.fontSizeBy(-2)
        wrapMode: Text.WordWrap
      }

      TypeLibrary {
        id: widgetLibrary
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: Widget.spacing / 2
        types: BarsConfig.libraryWidgetTypes
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
