pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config
import qs.services.core
import qs.services.compositor
import qs.services.apps
import qs.components.reusable

/**
 * Settings page, Maintenance › Community setups (the section's `x-card`,
 * wide): the gallery of setups shared at axiom-shell/community-setups.
 * The catalog is downloaded when this card is first shown (never before),
 * with each setup's thumbnail. Search and tag chips narrow the grid; a
 * tile opens its details (the full screenshot, what it needs, its
 * wallpaper's license) with Apply, which asks for a second click, saves
 * the current setup as "before-<id>" and takes the look only. The
 * catalog's text is someone else's, so it shows as plain text (`about` as
 * Markdown CommunityCatalog made inert) and only web links open.
 */
FieldGroup {
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
  onSelectedChanged: {
    root.armed = "";
    useWallpaper.checked = false;
    if (root.selected !== "")
      CommunitySetupsManager.fetchScreenshot(root.selected);
  }

  headerExtras: StyledTextButton {
    visible: CommunitySetupsManager.enabled
    enabled: !CommunitySetupsManager.loading
    Layout.preferredHeight: Widget.height
    iconText: "refresh"
    text: I18n.tr(CommunitySetupsManager.loading ? "Loading…" : "Refresh")
    onClicked: CommunitySetupsManager.refresh()
  }

  // A picture cut to the inner radius, a glyph while it loads
  component Picture: ClippingRectangle {
    id: picture
    property string source
    property int sourceWidth: Widget.px(640)
    radius: Widget.radius
    color: Theme.backgroundHighlight

    StyledIcon {
      anchors.centerIn: parent
      visible: image.status !== Image.Ready
      text: "image"
      opacity: 0.4
      textSize: Appearance.fontSize * 2
    }

    Image {
      id: image
      anchors.fill: parent
      source: picture.source
      sourceSize.width: picture.sourceWidth
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
    }
  }

  ColumnLayout {
    visible: CommunitySetupsManager.enabled
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledTextEntry {
      Layout.fillWidth: true
      Layout.preferredHeight: Widget.height
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

        delegate: SegmentButton {
          required property string modelData
          text: modelData
          active: root.activeTags.includes(modelData)
          onClicked: root.activeTags = active ? root.activeTags.filter(tag => tag !== modelData) : root.activeTags.concat([modelData])
        }
      }
    }

    StyledText {
      visible: text !== ""
      text: CommunitySetupsManager.status || (CommunitySetupsManager.loading && !CommunitySetupsManager.loaded ? I18n.tr("Loading the community setups…") : CommunitySetupsManager.loaded && root.results.length === 0 ? (CommunitySetupsManager.setups.length === 0 ? I18n.tr("No setups have been shared yet.") : I18n.tr("No setups match.")) : "")
      opacity: 0.7
      textSize: Appearance.fontSizeBy(-1)
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    // The selected setup's details
    StyledContainer {
      id: details
      visible: root.detail !== null
      Layout.fillWidth: true
      implicitHeight: detailColumn.implicitHeight + Widget.padding * 2
      readonly property var setup: root.detail
      readonly property var missing: setup ? CommunitySetupsManager.missingFonts(setup) : []

      ColumnLayout {
        id: detailColumn
        anchors.fill: parent
        anchors.margins: Widget.padding
        spacing: Widget.spacing

        Picture {
          Layout.fillWidth: true
          Layout.preferredHeight: width * 9 / 16
          sourceWidth: Widget.px(1600)
          // The thumbnail until the full screenshot is downloaded
          source: details.setup ? (CommunitySetupsManager.screenshots[details.setup.id] ?? CommunitySetupsManager.thumbs[details.setup.id] ?? "") : ""
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
              text: details.setup?.title ?? ""
              textFormat: Text.PlainText
              font.bold: true
              textSize: Appearance.fontSizeBy(2)
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            StyledText {
              elide: Text.ElideRight
              text: I18n.tr("by {0}", details.setup?.author ?? "")
              textFormat: Text.PlainText
              opacity: 0.7
              Layout.fillWidth: true
            }
          }

          StyledTextButton {
            visible: (details.setup?.page ?? "") !== ""
            Layout.preferredHeight: Widget.height
            iconText: "open_in_new"
            text: I18n.tr("View on GitHub")
            onClicked: Qt.openUrlExternally(details.setup.page)
          }

          StyledTextButton {
            Layout.preferredHeight: Widget.height
            text: I18n.tr("Close")
            onClicked: root.selected = ""
          }
        }

        StyledText {
          text: details.setup?.description ?? ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        StyledText {
          visible: text !== ""
          text: details.setup?.about ?? ""
          textFormat: Text.MarkdownText
          opacity: 0.8
          wrapMode: Text.WordWrap
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
              color: Theme.success
              text: I18n.tr("Tested on {0}", CompositorManager.nameOf(modelData))
            }
          }

          StatusChip {
            shown: details.setup?.files.theme !== undefined
            color: Theme.accent
            text: I18n.tr("Brings its own palette")
          }

          StatusChip {
            shown: details.missing.length > 0
            color: Theme.warning
            text: I18n.tr("Font not installed: {0}", details.missing.join(", "))
          }

          StatusChip {
            shown: details.setup !== null && !details.setup.compatible
            color: Theme.error
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
              wrapMode: Text.WordWrap
              text: I18n.tr("Also use its wallpaper")
              Layout.fillWidth: true
            }

            StyledText {
              readonly property var wallpaper: details.setup?.wallpaper ?? null
              text: wallpaper ? I18n.tr("License: {0} · Source: {1}", wallpaper.license, wallpaper.source) + (wallpaper.credit ? " · " + wallpaper.credit : "") : ""
              textFormat: Text.PlainText
              opacity: 0.6
              textSize: Appearance.fontSizeBy(-2)
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledText {
            Layout.fillWidth: true
            text: CommunitySetupsManager.applying === details.setup?.id ? I18n.tr("Applying…") : root.armed === details.setup?.id ? I18n.tr("Your current setup is saved as \"{0}\" first.", "before-" + details.setup.id) : ""
            opacity: 0.7
            textSize: Appearance.fontSizeBy(-1)
            elide: Text.ElideRight
          }

          StyledTextButton {
            Layout.preferredHeight: Widget.height
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
    }

    TileFlow {
      id: grid
      Layout.fillWidth: true
      minTileWidth: Appearance.fontSize * 16

      Repeater {
        model: root.results

        delegate: StyledContainer {
          id: tile
          required property var modelData
          readonly property bool current: root.selected === modelData.id

          width: grid.tileWidth
          implicitHeight: tileColumn.implicitHeight + Widget.padding * 2
          borderWidth: 2
          borderColor: current ? Theme.accent : tileMouse.containsMouse ? Theme.border : "transparent"

          ColumnLayout {
            id: tileColumn
            anchors.fill: parent
            anchors.margins: Widget.padding
            spacing: Widget.spacing / 2

            Picture {
              Layout.fillWidth: true
              Layout.preferredHeight: width * 9 / 16
              source: CommunitySetupsManager.thumbs[tile.modelData.id] ?? ""
              opacity: tile.modelData.compatible ? 1 : 0.5
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Widget.spacing / 2

              StyledText {
                Layout.fillWidth: true
                text: tile.modelData.title
                textFormat: Text.PlainText
                font.bold: true
                elide: Text.ElideRight
              }

              StatusChip {
                shown: CommunitySetupsManager.applied === tile.modelData.id
                color: Theme.accent
                text: I18n.tr("Applied")
              }
            }

            StyledText {
              Layout.fillWidth: true
              text: tile.modelData.compatible ? I18n.tr("by {0}", tile.modelData.author) : I18n.tr("by {0} · needs a newer axiom", tile.modelData.author)
              textFormat: Text.PlainText
              opacity: 0.6
              textSize: Appearance.fontSizeBy(-2)
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selected = tile.current ? "" : tile.modelData.id
          }
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

      StyledText {
        Layout.fillWidth: true
        text: SavedConfigsManager.status
        opacity: 0.7
        textSize: Appearance.fontSizeBy(-1)
        elide: Text.ElideRight
      }

      StyledTextButton {
        Layout.preferredHeight: Widget.height
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
