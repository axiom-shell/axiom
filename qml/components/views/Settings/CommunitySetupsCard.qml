pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.apps
import qs.components.reusable

/**
 * Settings page, System › Community setups (the section's `x-card`,
 * wide): the gallery of setups shared at axiom-shell/community-setups.
 * The catalog is downloaded when this card is first shown (never before),
 * with each setup's thumbnail. Search and tag chips narrow the grid; a
 * tile opens its details (the full screenshot, what it needs, its
 * wallpaper's license) with Apply, which asks for a second click, keeps
 * unsaved changes and takes the look only. The
 * catalog's text is someone else's, so it shows as plain text (`about` as
 * Markdown CommunityCatalog made inert) and only web links open.
 */
PageCard {
  id: root

  description: CommunitySetupsManager.enabled ? I18n.tr("Setups other people built with axiom. Applying one changes the look and layout only: keybinds, apps, commands, monitors and accounts stay yours, and your current setup is saved first.") : I18n.tr("Turn on Browse community setups below to see the gallery.")

  property string query: ""
  property var activeTags: []
  // The setup whose details show, "" for none
  property string selected: ""
  // Apply clicked once for this setup, waiting for the confirming click
  property string armed: ""

  readonly property var results: CommunitySetupsManager.loaded ? CommunitySetupsManager.search(root.query, root.activeTags) : []
  readonly property var detail: root.selected !== "" ? CommunitySetupsManager.setup(root.selected) : null

  Component.onCompleted: CommunitySetupsManager.open()
  // Turned on while shown: read the catalog then (open() does nothing while off)
  Connections {
    target: CommunitySetupsManager
    function onEnabledChanged() {
      CommunitySetupsManager.open();
    }
  }
  onSelectedChanged: {
    root.armed = "";
    useWallpaper.checked = false;
    if (root.selected !== "")
      CommunitySetupsManager.fetchScreenshot(root.selected);
  }

  headerExtras: StyledTextButton {
    visible: CommunitySetupsManager.enabled
    enabled: !CommunitySetupsManager.loading
    iconText: "refresh"
    text: I18n.tr(CommunitySetupsManager.loading ? "Loading…" : "Refresh")
    onClicked: CommunitySetupsManager.refresh()
  }

  ColumnLayout {
    visible: CommunitySetupsManager.enabled
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledTextEntry {
      Layout.fillWidth: true
      placeholderText: I18n.tr("Search by name, author, theme or tag")
      clearable: true
      onTextEdited: root.query = text
    }

    Flow {
      visible: CommunitySetupsManager.loaded && CommunitySetupsManager.setups.length > 0
      Layout.fillWidth: true
      spacing: Widget.spacing / 2

      Repeater {
        model: CommunitySetupsManager.loaded ? CommunitySetupsManager.tags() : []

        delegate: ToggleChip {
          required property string modelData
          text: modelData
          checked: root.activeTags.includes(modelData)
          onToggled: root.activeTags = checked ? root.activeTags.filter(tag => tag !== modelData) : root.activeTags.concat([modelData])
        }
      }
    }

    StyledText {
      visible: text !== ""
      text: CommunitySetupsManager.status || (CommunitySetupsManager.loading && !CommunitySetupsManager.loaded ? I18n.tr("Loading the community setups…") : CommunitySetupsManager.loaded && root.results.length === 0 ? (CommunitySetupsManager.setups.length === 0 ? I18n.tr("No setups have been shared yet.") : I18n.tr("No setups match.")) : "")
      tone: "muted"
      role: "caption"
      overflow: "wrap"
      Layout.fillWidth: true
    }

    // The selected setup's details
    ItemBox {
      id: details
      visible: root.detail !== null
      readonly property var setup: root.detail
      readonly property var missing: setup ? CommunitySetupsManager.missingFonts(setup) : []

      Thumbnail {
        Layout.fillWidth: true
        Layout.preferredHeight: width * 9 / 16
        decodeSize: Qt.size(Widget.px(1600), 0)
        placeholderIcon: "image"
        // The thumbnail until the full screenshot is downloaded
        source: details.setup ? (CommunitySetupsManager.screenshots[details.setup.id] ?? CommunitySetupsManager.thumbs[details.setup.id] ?? "") : ""
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          StyledLabel {
            text: details.setup?.title ?? ""
            textFormat: Text.PlainText
            role: "title"
            overflow: "line"
            Layout.fillWidth: true
          }

          StyledLabel {
            overflow: "line"
            text: I18n.tr("by {0}", details.setup?.author ?? "")
            textFormat: Text.PlainText
            tone: "muted"
            Layout.fillWidth: true
          }
        }

        StyledTextButton {
          visible: (details.setup?.page ?? "") !== ""
          iconText: "open_in_new"
          text: I18n.tr("View on GitHub")
          onClicked: Qt.openUrlExternally(details.setup.page)
        }

        StyledTextButton {
          text: I18n.tr("Close")
          onClicked: root.selected = ""
        }
      }

      StyledText {
        text: details.setup?.description ?? ""
        textFormat: Text.PlainText
        overflow: "wrap"
        Layout.fillWidth: true
      }

      StyledText {
        visible: text !== ""
        text: details.setup?.about ?? ""
        textFormat: Text.MarkdownText
        tone: "muted"
        overflow: "wrap"
        Layout.fillWidth: true
        onLinkActivated: link => {
          if (/^https?:\/\//.test(link))
            Qt.openUrlExternally(link);
        }
      }

      // What it was tried on and what it needs
      Flow {
        Layout.fillWidth: true
        spacing: Widget.spacing / 2

        Repeater {
          model: details.setup?.tested ?? []

          delegate: StatusChip {
            required property string modelData
            tone: "success"
            text: I18n.tr("Tested on {0}", CompositorManager.nameOf(modelData))
          }
        }

        StatusChip {
          shown: details.setup?.files.theme !== undefined
          tone: "accent"
          text: I18n.tr("Brings its own palette")
        }

        StatusChip {
          shown: details.missing.length > 0
          tone: "warning"
          text: I18n.tr("Font not installed: {0}", details.missing.join(", "))
        }

        StatusChip {
          shown: details.setup !== null && !details.setup.compatible
          tone: "error"
          text: I18n.tr("Needs a newer axiom")
        }
      }

      RowLayout {
        visible: (details.setup?.wallpaper ?? null) !== null
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledSwitch {
          id: useWallpaper
          checked: false
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          StyledText {
            overflow: "wrap"
            text: I18n.tr("Also use its wallpaper")
            Layout.fillWidth: true
          }

          StyledLabel {
            readonly property var wallpaper: details.setup?.wallpaper ?? null
            text: wallpaper ? I18n.tr("License: {0} · Source: {1}", wallpaper.license, wallpaper.source) + (wallpaper.credit ? " · " + wallpaper.credit : "") : ""
            textFormat: Text.PlainText
            tone: "muted"
            role: "caption"
            overflow: "line"
            Layout.fillWidth: true
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Widget.spacing

        StyledLabel {
          Layout.fillWidth: true
          text: CommunitySetupsManager.applying === details.setup?.id ? I18n.tr("Applying…") : root.armed === details.setup?.id ? SavedConfigsManager.keepHint("") : ""
          tone: "muted"
          role: "caption"
          overflow: "line"
        }

        StyledTextButton {
          enabled: (details.setup?.compatible ?? false) && CommunitySetupsManager.applying === ""
          text: I18n.tr(root.armed === details.setup?.id ? "Confirm" : "Apply")
          onClicked: {
            if (root.armed !== details.setup.id) {
              root.armed = details.setup.id;
              return;
            }
            root.armed = "";
            CommunitySetupsManager.apply(details.setup.id, useWallpaper.checked && details.setup.wallpaper !== null);
          }
        }
      }
    }

    // A tile's picture over its author, the Applied chip on the picture
    Component {
      id: tilePicture

      ColumnLayout {
        id: picture
        required property string source
        required property string author
        required property bool applied
        required property bool compatible
        spacing: 0

        Thumbnail {
          Layout.fillWidth: true
          Layout.fillHeight: true
          source: picture.source
          decodeSize: Qt.size(Widget.px(640), 0)
          placeholderIcon: "image"
          opacity: picture.compatible ? 1 : Style.opacityDisabled

          StatusChip {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Widget.smallPadding / 2
            shown: picture.applied
            tone: "accent"
            text: I18n.tr("Applied")
          }
        }

        StyledText {
          Layout.fillWidth: true
          text: picture.author
          textFormat: Text.PlainText
          tone: "muted"
          role: "caption"
          overflow: "line"
        }
      }
    }

    TileFlow {
      id: grid
      Layout.fillWidth: true
      minTileWidth: Appearance.fontSize * 16

      Repeater {
        model: root.results

        delegate: PreviewTile {
          id: tile
          required property var modelData

          width: grid.tileWidth
          title: tile.modelData.title
          selected: root.selected === tile.modelData.id
          previewHeight: (grid.tileWidth - Widget.smallPadding) * 9 / 16 + Widget.smallHeight
          preview: tilePicture
          previewProperties: ({
              "source": CommunitySetupsManager.thumbs[tile.modelData.id] ?? "",
              "author": tile.modelData.compatible ? I18n.tr("by {0}", tile.modelData.author) : I18n.tr("by {0} · needs a newer axiom", tile.modelData.author),
              "applied": CommunitySetupsManager.applied === tile.modelData.id,
              "compatible": tile.modelData.compatible
            })
          onClicked: root.selected = tile.selected ? "" : tile.modelData.id
        }
      }
    }

    SectionHeading {
      Layout.topMargin: Widget.spacing
      title: I18n.tr("Share yours")
      description: I18n.tr("Export your look (without your preferences, keybinds, apps or commands), then fill in the submission form that opens. Attach the exported file and a screenshot of your whole screen there.")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      StyledLabel {
        Layout.fillWidth: true
        text: SavedConfigsManager.status
        tone: "muted"
        role: "caption"
        overflow: "line"
      }

      StyledTextButton {
        iconText: "upload"
        text: I18n.tr("Export and submit…")
        onClicked: {
          SavedConfigsManager.exportConfig(false, false);
          Qt.openUrlExternally(CommunitySetupsManager.submitUrl(SavedConfigsManager.active));
        }
      }
    }
  }
}
