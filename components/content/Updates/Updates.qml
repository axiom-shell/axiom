pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable
import qs.components.content.base
import qs.components.content.parts

// Pending updates, repo and AUR listed separately (from UpdatesManager). As
// the Updates widget's popout (the widget acquires the manager), or an
// overlay card, which acquires it with its own settings and says so where
// this distribution's updates can't be checked (UpdatesManager.supported).
// properties (card): { interval (ms) }; the AUR helper is UpdatesConfig's
Panel {
  id: root

  // [{ name, from, to }]
  property var repoPackages: UpdatesManager.repoPackages
  property var aurPackages: UpdatesManager.aurPackages
  readonly property int total: repoPackages.length + aurPackages.length

  spacing: Widget.padding
  // A wide card puts the repositories and the AUR side by side
  readonly property int sectionCount: (root.repoPackages.length > 0 ? 1 : 0) + (root.aurPackages.length > 0 ? 1 : 0)
  readonly property bool sideBySide: root.embedded && root.sectionCount > 1 && root.innerWidth >= Appearance.fontSize * 44
  // A section's width in a card, from the card rather than the layout (a
  // section sizing its rows by its own width makes the layout recurse); a
  // popout sizes to its rows
  readonly property real sectionWidth: root.sideBySide ? (root.innerWidth - root.pad) / 2 : root.innerWidth
  // One package row, and as many as fit under the header and each
  // section's title and "+n more" line (a popout lists 15)
  readonly property real rowLine: Appearance.fontSize * 1.45
  readonly property int maxRows: {
    if (!root.embedded)
      return 15;
    const stacked = root.sideBySide ? 1 : Math.max(1, root.sectionCount);
    const room = root.innerHeight - Appearance.fontSize * 2 - root.spacing * (stacked + 1) - stacked * root.rowLine * 2;
    return Math.max(1, Math.floor(room / stacked / root.rowLine));
  }

  fullMinWidth: Appearance.fontSize * 10
  fullMinHeight: Appearance.fontSize * 6

  function register() {
    if (!root.embedded)
      return;
    UpdatesManager.acquire(root, {
      "interval": root.properties.interval,
      "aurHelper": UpdatesConfig.activeAurHelper
    });
  }
  onPropertiesChanged: register()
  onEmbeddedChanged: register()
  Component.onCompleted: register()
  Component.onDestruction: UpdatesManager.release(root)

  compactContent: CompactFigure {
    icon: "update"
    iconColor: root.total > 0 ? Theme.accent : Theme.foregroundAlt
    value: !UpdatesManager.supported ? "–" : UpdatesManager.checking && root.total === 0 ? "…" : String(root.total)
    label: I18n.tr("updates")
  }

  implicitWidth: Math.max(Widget.px(320), body.implicitWidth + margins * 2)

  component Section: ColumnLayout {
    id: section
    required property string title
    required property var packages

    // Narrow, only the new version
    readonly property bool narrow: root.embedded && root.sectionWidth < Appearance.fontSize * 25
    // A sliver, just the names (an elided version says nothing)
    readonly property bool namesOnly: root.embedded && root.sectionWidth < Appearance.fontSize * 12

    visible: packages.length > 0
    spacing: 2
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop

    StyledText {
      text: `${section.title} (${section.packages.length})`
      font.bold: true
      textColor: Theme.accent
    }

    Repeater {
      model: section.packages.slice(0, root.maxRows)

      RowLayout {
        id: row
        required property var modelData
        Layout.fillWidth: true
        spacing: Widget.padding

        StyledText {
          text: row.modelData.name
          Layout.fillWidth: true
          Layout.minimumWidth: Appearance.fontSize * 4
          elide: Text.ElideRight
        }
        StyledText {
          visible: !section.namesOnly
          Layout.maximumWidth: root.embedded ? root.sectionWidth * 0.45 : Number.POSITIVE_INFINITY
          elide: Text.ElideLeft
          // dnf doesn't say the installed version
          text: section.narrow || row.modelData.from === "" ? row.modelData.to : `${row.modelData.from} → ${row.modelData.to}`
          textColor: Theme.foregroundAlt
          textSize: Appearance.fontSizeBy(-2)
        }
      }
    }

    StyledText {
      visible: section.packages.length > root.maxRows
      text: I18n.tr("+{0} more", section.packages.length - root.maxRows)
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-2)
    }
  }

  ModuleHeader {
    visible: root.embedded
    icon: "update"
    title: !UpdatesManager.supported ? I18n.tr("Updates") : root.total > 0 ? I18n.tr("{0} updates", root.total) : I18n.tr("Up to date")
    StyledText {
      visible: UpdatesManager.checking
      text: I18n.tr("checking…")
      textSize: Appearance.fontSizeBy(-2)
      opacity: 0.6
    }
  }

  GridLayout {
    Layout.fillWidth: true
    columns: root.sideBySide ? 2 : 1
    columnSpacing: root.pad
    rowSpacing: root.spacing

    Section {
      title: I18n.tr("Repositories")
      packages: root.repoPackages
    }

    Section {
      title: I18n.tr("AUR")
      packages: root.aurPackages
    }
  }

  StyledText {
    visible: !root.embedded && root.total === 0
    text: I18n.tr("System is up to date")
    textColor: Theme.foregroundAlt
  }

  // A card: the empty state centred, and the lists kept at the top
  Item {
    visible: root.embedded
    Layout.fillWidth: true
    Layout.fillHeight: true
    EmptyState {
      visible: root.total === 0
      anchors.centerIn: parent
      maxWidth: parent.width
      availableHeight: parent.height
      icon: UpdatesManager.supported ? "check" : "block"
      text: !UpdatesManager.supported ? I18n.tr("axiom can't check for updates on this distribution.") : UpdatesManager.checking ? I18n.tr("checking…") : I18n.tr("System is up to date")
    }
  }
}
