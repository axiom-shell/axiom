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
import qs.components.views.Settings

// Bar editor, left: the bars, then the selected bar's settings under four
// tabs (Layout, Surface, Style, Behaviour): its own groups, generated
// from the schema's Bar definition, and its style (the Bar style block,
// BarStyle's groups, each shared or its own). Only the shown tab's groups
// are built.
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

    // The bar's style (the tab's style sections, BarsConfig.editorTabs'
    // `styles`): the Bar style block over its look, each section shared
    // (Bars.style, on the settings page's Bar style card) until the bar
    // takes its own
    StreamedLoader {
      Layout.fillWidth: true
      label: "bar style block"
      wanted: root.hasBar && root._tab.styles.length > 0

      sourceComponent: FieldGroup {
        title: I18n.tr("Bar style")

        BarStyleBlock {
          id: block
          // The bar's look, its shadow as its object again (lookOf
          // flattens it)
          readonly property var look: BarsConfig.lookOf(root.bar ?? ({}), BarManager.localStyle)

          sections: root._tab.styles
          bar: root.bar
          values: Object.keys(block.schema?.properties ?? {}).reduce((values, key) => {
            values[key] = key === "shadow" ? {
              "enabled": block.look.shadow,
              "color": block.look.shadowColor,
              "size": block.look.shadowSize
            } : block.look[key];
            return values;
          }, {})
          owned: BarsConfig.styleGroups.reduce((owned, group) => {
            owned[group.title] = BarManager.ownsStyle(BarManager.selectedBarIndex, group.keys);
            return owned;
          }, {})
          // Owned, but not every key: some still follow the shared style
          partlyOwned: BarsConfig.styleGroups.reduce((partly, group) => {
            partly[group.title] = block.owned[group.title] === true && !BarManager.ownsAllStyle(BarManager.selectedBarIndex, group.keys);
            return partly;
          }, {})
          // A field's path: [key], or the shadow's ["shadow", part]
          changedAt: path => BarManager.styleFieldChanged(path[0], path[1])
          onEdited: (path, value) => {
            if (path[0] !== "shadow") {
              BarManager.updateStyleField(path[0], value);
              return;
            }
            // Only the parts edited: the rest stay inherited
            for (const part in value)
              if (!Utils.deepEqual(value[part], block.values.shadow[part]))
                BarManager.updateStyleField("shadow", value[part], part);
          }
          onDiscardAt: path => BarManager.discardStyleField(path[0], path[1])
          onOwnToggled: (group, value) => BarManager.setStyleOwned(BarsConfig.styleGroups.find(entry => entry.title === group)?.keys ?? [], value)
          // (Its keys already set keep their values)
          onOwnAllRequested: group => BarManager.setStyleOwned(BarsConfig.styleGroups.find(entry => entry.title === group)?.keys ?? [], true)
        }
      }
    }
  }
}
