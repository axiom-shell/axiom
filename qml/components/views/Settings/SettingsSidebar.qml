pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.content.base

// i18n: keys from the schema (category names, card titles)
// Settings page, left: search and the category list; the selected
// category also lists its cards, and clicking one scrolls the page to it.
// The selection and search text live in SettingsManager, so they survive
// the page reloading.
Item {
  id: root

  // SchemaLayout.categories()
  required property var categories
  // The category shown (the first one until one is picked)
  required property string selected
  // The selected category's shown cards (SettingsContent.shownGroups)
  required property var cards

  // One entry per card title: a section's hand-built card and its fields'
  // card share the section's title
  readonly property var cardLinks: root.cards.filter((card, i) => root.cards.findIndex(other => other.title === card.title) === i)

  TitledCard {
    title: I18n.tr("Settings")
    scrollKey: "Settings/sidebar"
    showActions: false
    contentSpacing: Widget.spacing / 2

    headerExtras: StyledTextEntry {
      id: search
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
      placeholderText: I18n.tr("Search settings")
      clearable: true
      Component.onCompleted: input.text = SettingsManager.query
      onTextChanged: SettingsManager.query = text

      // Cleared from outside, e.g. by picking a category
      Connections {
        target: SettingsManager
        function onQueryChanged() {
          if (search.input.text !== SettingsManager.query)
            search.input.text = SettingsManager.query;
        }
      }
    }

    Repeater {
      model: root.categories

      delegate: ColumnLayout {
        id: entry
        required property var modelData
        readonly property bool current: SettingsManager.query === "" && !SettingsManager.changedOnly && root.selected === entry.modelData.name
        Layout.fillWidth: true
        spacing: 0

        ListEntryRow {
          icon: entry.modelData.icon
          label: I18n.tr(entry.modelData.name)
          selected: entry.current
          changed: entry.modelData.sections.some(section => SettingsManager.hasChangesUnder(section))
          onClicked: {
            SettingsManager.query = "";
            SettingsManager.changedOnly = false;
            SettingsManager.category = entry.modelData.name;
          }
        }

        // Its cards, along a rule under the row, folding open on selection.
        // `held` keeps the links it opened with while it folds shut, as
        // `cardLinks` is already the next category's
        FoldingColumn {
          id: links
          property var held: []

          open: entry.current && root.cardLinks.length > 1
          Layout.fillWidth: true
          Layout.leftMargin: Widget.padding + Appearance.fontSize * 0.75
          topPadding: 2
          bottomPadding: Widget.spacing / 2
          spacing: 0

          Binding on held {
            when: links.open
            value: root.cardLinks
            restoreMode: Binding.RestoreNone
          }

          Repeater {
            model: links.shown ? links.held : []

            delegate: Item {
              id: link
              required property var modelData
              Layout.fillWidth: true
              implicitHeight: Appearance.fontSize * 2

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: linkArea.containsMouse ? 2 : 1
                color: linkArea.containsMouse ? Theme.accent : Theme.border
              }

              StyledText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Widget.padding
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr(link.modelData.title)
                textSize: Appearance.fontSizeBy(-1)
                textColor: linkArea.containsMouse ? Theme.accent : Theme.foreground
                opacity: linkArea.containsMouse ? 1 : 0.7
                elide: Text.ElideRight
              }

              MouseArea {
                id: linkArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SettingsManager.jumpTo(link.modelData.key)
              }
            }
          }
        }
      }
    }

    StyledSeparator {
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing / 2
      Layout.bottomMargin: Widget.spacing / 2
      separatorHeight: 1
      opacity: 0.3
    }

    // Every setting not at its default, from all categories
    ListEntryRow {
      id: changedEntry
      icon: "difference"
      label: I18n.tr("Changed from default")
      selected: SettingsManager.query === "" && SettingsManager.changedOnly
      onClicked: SettingsManager.showChanged()

      badges: StyledText {
        text: SettingsManager.nonDefaultPaths.length
        textColor: changedEntry.ink
        textSize: Appearance.fontSizeBy(-2)
        opacity: 0.7
      }
    }

    StyledText {
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing
      text: SettingsManager.changedCount > 0 ? I18n.tr("{0} unsaved changes", SettingsManager.changedCount) : I18n.tr("Changes apply as you make them. Save keeps them.")
      textColor: SettingsManager.changedCount > 0 ? Theme.accent : Theme.foreground
      opacity: SettingsManager.changedCount > 0 ? 1 : 0.6
      textSize: Appearance.fontSizeBy(-2)
      wrapMode: Text.WordWrap
    }
  }
}
