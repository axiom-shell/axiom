pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services.compositor
import qs.services.ui
import qs.components.methods
import qs.components.reusable
import qs.components.forms
import qs.components.content.base

// i18n: keys from the schema (titles, descriptions)
// Bar editor, left: the bars, then the selected bar's settings under four
// tabs (Layout, Surface, Widgets, Behaviour): its own groups, generated
// from the schema's Bar definition, and its style's (BarStyle's groups),
// shared or its own. Only the shown tab's groups are built.
Item {
  id: root

  readonly property bool hasBar: root.bar !== null
  readonly property var bar: BarManager.selectedBar()
  // A style is copied (BarManager.copyStyle), from the selected bar
  readonly property bool copied: BarManager.copiedStyle !== null
  readonly property bool copiedHere: BarManager.copiedStyle?.index === BarManager.selectedBarIndex

  // The tabs (BarsConfig.editorTabs)
  readonly property var tabs: BarsConfig.editorTabs
  readonly property var _tab: root.tabs[BarManager.panelTab] ?? root.tabs[0]
  readonly property var _named: [].concat(...root.tabs.map(tab => tab.fields))
  readonly property var fieldGroups: BarsConfig.fieldGroups.filter(group => root._tab.fields.includes(group.title) || (root._tab === root.tabs[0] && !root._named.includes(group.title)))
  readonly property var styleGroups: BarsConfig.styleGroups.filter(group => root._tab.styles.includes(group.title))

  // Group titles: I18n.tr("Placement") I18n.tr("Size") I18n.tr("Surface")
  // I18n.tr("Behaviour") I18n.tr("Other") I18n.tr("Look") I18n.tr("Colors")
  // I18n.tr("Accents") I18n.tr("Shadow")
  TitledCard {
    title: I18n.tr("Bar Editor")
    scrollKey: "BarEditor"
    // Save and Discard here, above the bar list
    dirty: BarManager.isDirty
    onSave: BarManager.saveChanges()
    onReset: BarManager.resetChanges()

    headerExtras: ColumnLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      Repeater {
        model: BarManager.localConfig?.length ?? 0

        delegate: ListEntryRow {
          id: entry
          required property int index
          readonly property var entryBar: BarManager.localConfig[index] ?? ({})

          icon: Utils.edgeArrow(entry.entryBar.location)
          label: BarManager.barLabel(entry.index)
          selected: BarManager.selectedBarIndex === entry.index
          dimmed: entry.entryBar.enabled === false
          changed: BarManager.barChanged(entry.index)
          onClicked: BarManager.selectBar(entry.index)

          // One copy per monitor
          badges: StyledIcon {
            id: everyMonitor
            visible: entry.entryBar.screen.mode === "all"
            text: "desktop_windows"
            textColor: entry.ink
            opacity: 0.7

            HoverHandler {
              id: everyMonitorHover
            }
            LazyLoader {
              active: everyMonitorHover.hovered
              StyledToolTip {
                target: everyMonitor
                text: I18n.tr("On every monitor")
              }
            }
          }

          RowAction {
            row: entry
            iconText: "content_copy"
            tooltipText: I18n.tr("Copy this bar")
            onClicked: BarManager.duplicateBar(entry.index)
          }

          RowAction {
            row: entry
            visible: (BarManager.localConfig?.length ?? 0) > 1
            danger: true
            iconText: "close"
            tooltipText: I18n.tr("Remove this bar")
            onClicked: BarManager.removeBar(entry.index)
          }
        }
      }

      AddEntryButton {
        Layout.topMargin: Widget.spacing
        Layout.bottomMargin: Widget.spacing
        text: I18n.tr("New bar")
        onClicked: BarManager.addBar()
      }

      StyledTabBar {
        visible: root.hasBar
        Layout.fillWidth: true
        tabs: root.tabs.map(tab => tab.label)
        currentIndex: BarManager.panelTab
        onTabClicked: index => BarManager.selectPanelTab(index)
      }
    }

    // A ColumnLayout's Repeater re-runs its model on every draft edit:
    // `hasEntry` keeps the model the same while one is selected
    Repeater {
      model: root.hasBar ? root.fieldGroups : []

      // Each group streamed in (StreamedLoader) as the page opens
      delegate: StreamedLoader {
        id: groupLoader
        required property var modelData
        Layout.fillWidth: true
        label: `bar field group ${groupLoader.modelData.title}`

        sourceComponent: FieldGroup {
          id: group
          readonly property var modelData: groupLoader.modelData
          title: I18n.tr(group.modelData.title)

          // The Surface group carries the bar's look (BarManager.styleKeys:
          // its style and its Size and Surface settings) to other bars
          headerExtras: [
            SquareIconButton {
              visible: group.modelData.title === "Surface"
              iconText: "format_paint"
              iconColor: root.copiedHere ? Theme.background : Theme.foreground
              backgroundColor: root.copiedHere ? Theme.accent : Theme.backgroundAlt
              tooltipText: I18n.tr("Copy this bar's size and style")
              onClicked: BarManager.copyStyle(BarManager.selectedBarIndex)
            },
            SquareIconButton {
              visible: group.modelData.title === "Surface" && root.copied && !root.copiedHere
              iconText: "content_paste"
              tooltipText: I18n.tr("Paste the size and style of {0}", BarManager.barLabel(BarManager.copiedStyle?.index ?? 0))
              onClicked: BarManager.pasteStyle(BarManager.selectedBarIndex)
            },
            SquareIconButton {
              visible: group.modelData.title === "Surface" && root.copied
              iconText: "done_all"
              tooltipText: I18n.tr("Paste the size and style of {0} onto every bar", BarManager.barLabel(BarManager.copiedStyle?.index ?? 0))
              onClicked: BarManager.pasteStyleToAll()
            }
          ]

          SchemaPropertiesForm {
            Layout.fillWidth: true
            propertiesSchema: group.modelData.schema
            order: group.modelData.keys
            numberMode: "stepper"
            // The whole bar, so x-showIf sees keys from other groups, with
            // the look it takes from BarStyle where it doesn't override it
            values: BarsConfig.lookOf(root.bar ?? ({}))
            changedAt: path => BarManager.barFieldChanged(path[0])
            onEdited: (path, value) => BarManager.updateBarField(path[0], value)
            onDiscardAt: path => BarManager.discardBarField(path[0])
          }

          // How deep the size settings make the bar (its extent)
          StyledText {
            visible: "thickness" in group.modelData.schema
            text: I18n.tr("The bar is {0} px deep", Math.round(BarsConfig.enrichBarConfig(root.bar ?? ({}), CompositorManager.gapsOut, ScreenEdgeManager.floatGaps).extent))
            textColor: Theme.foreground
            opacity: 0.7
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }
      }
    }

    // The bar's style, by group: shared (Bars.style, on the settings
    // page's Look & Feel) until the bar takes its own
    Repeater {
      model: root.hasBar ? root.styleGroups : []

      delegate: StreamedLoader {
        id: styleLoader
        required property var modelData
        Layout.fillWidth: true
        label: `bar style group ${styleLoader.modelData.title}`

        sourceComponent: FieldGroup {
          id: styleGroup
          readonly property var modelData: styleLoader.modelData
          readonly property bool owned: BarManager.ownsStyle(BarManager.selectedBarIndex, styleGroup.modelData.keys)
          // The shadow is one object; the rest are the bar's flat look
          readonly property bool isShadow: styleGroup.modelData.keys.includes("shadow")
          readonly property var look: BarsConfig.lookOf(root.bar ?? ({}), BarManager.localStyle)
          title: I18n.tr(styleGroup.modelData.title)

          SchemaSwitch {
            label: I18n.tr("This bar's own")
            description: styleGroup.owned ? "" : I18n.tr("Shared with every bar.")
            checked: styleGroup.owned
            onToggled: value => BarManager.setStyleOwned(styleGroup.modelData.keys, value)
          }

          // Where the shared style is set: this group's card on the
          // settings page
          SettingsLink {
            id: sharedLink
            Layout.fillWidth: true
            setting: "Bars.style." + styleGroup.modelData.keys[0]
            text: I18n.tr("{0} in {1}", I18n.tr(styleGroup.modelData.title), I18n.tr(sharedLink.target?.category ?? ""))
          }

          SchemaPropertiesForm {
            visible: styleGroup.owned
            Layout.fillWidth: true
            propertiesSchema: styleGroup.isShadow ? styleGroup.modelData.schema.shadow.properties : styleGroup.modelData.schema
            order: styleGroup.isShadow ? Object.keys(styleGroup.modelData.schema.shadow.properties) : styleGroup.modelData.keys
            numberMode: "stepper"
            values: styleGroup.isShadow ? {
              "enabled": styleGroup.look.shadow,
              "color": styleGroup.look.shadowColor,
              "size": styleGroup.look.shadowSize
            } : styleGroup.look
            changedAt: path => styleGroup.isShadow ? BarManager.styleFieldChanged("shadow", path[0]) : BarManager.styleFieldChanged(path[0])
            onEdited: (path, value) => styleGroup.isShadow ? BarManager.updateStyleField("shadow", value, path[0]) : BarManager.updateStyleField(path[0], value)
            onDiscardAt: path => styleGroup.isShadow ? BarManager.discardStyleField("shadow", path[0]) : BarManager.discardStyleField(path[0])
          }
        }
      }
    }
  }
}
