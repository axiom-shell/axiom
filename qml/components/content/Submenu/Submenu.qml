pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.content.base
import qs.components.hosts.popout

// A row that opens another menu (`menu`) beside the one it's in, in
// that menu's submenu (EdgePopout.submenu, content/Submenu/MenuSubmenu): on
// hover, or on a click with openOnHover off. In a submenu it replaces
// that submenu in place (one level deep). Only a menu placed on an edge
// has a submenu: elsewhere (a strip menu) the row is dimmed and inert.
// properties: { menu, label, icon, openOnHover }
Card {
  id: root

  readonly property string menuId: root.properties.menu
  readonly property var menu: root.menuId !== "" ? MenusConfig.menuById(root.menuId) : null
  // A menu that's gone, disabled, or this one (it'd open itself) opens
  // nothing
  readonly property bool opens: root.menu !== null && root.menu.enabled && root.menuId !== (root.host?.id ?? "") && anchor.popouts !== null
  // Empty shows none, as an empty icon does
  readonly property string label: root.properties.label
  readonly property bool isOpen: anchor.popoutOpen
  // Which way it opens, for the arrow
  readonly property bool toLeft: anchor.popouts?.openToLeft ?? false

  // The layouts editor showing the menu it opens (OverlayManager.menus
  // previewing a submenu): held open from here, as if hovered
  // (the first such row in the menu, if there are more; found by its
  // properties, which a module growing above it doesn't move: two rows
  // alike open it alike)
  readonly property bool previewed: root.menuId !== "" && OverlayManager.menus.previewing === root.menuId && OverlayManager.menus.previewParent !== "" && OverlayManager.menus.previewParent === (root.host?.id ?? "") && !root.host?.submenu && root._firstOpener
  readonly property bool _firstOpener: {
    const first = (MenusConfig.menuById(root.host?.id ?? "")?.layout?.modules ?? []).find(module => module?.type === "Submenu" && module.properties?.menu === root.menuId);
    return JSON.stringify(first?.properties ?? null) === JSON.stringify(root.properties);
  }
  onPreviewedChanged: {
    if (root.previewed)
      anchor.open();
  }
  Component.onCompleted: {
    if (root.previewed)
      Qt.callLater(anchor.open);
  }

  fullMinWidth: Widget.height * 3
  opacity: root.opens || root.menuId === "" ? 1 : Style.opacityDisabled

  Rectangle {
    anchors.fill: parent
    anchors.margins: root.bare ? 0 : Appearance.borderWidth
    radius: Style.radius
    color: root.isOpen ? Style.accentContainer : "transparent"

    StateLayer {
      hovered: area.containsMouse
      pressed: area.pressed
    }
  }

  // What the anchor reads as hovered: the row, or the editor holding it
  QtObject {
    id: hit
    readonly property bool hovered: area.containsMouse || root.previewed
  }

  PopoutAnchor {
    id: anchor
    hitArea: hit
    popoutName: "Submenu/MenuSubmenu"
    active: root.opens
    openOnHover: root.properties.openOnHover
    extraData: ({
        "menuId": root.menuId,
        "parentId": root.host?.id ?? ""
      })
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.opens ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (!root.opens)
        return;
      if (root.isOpen)
        anchor.popouts.hide();
      else
        anchor.open();
    }
  }

  // Wider than tall: a menu row, the arrow at the side it opens on
  readonly property bool stacked: root.shape !== "horizontal"
  readonly property color tint: root.isOpen ? Style.inkAccentContainer.text : Style.text

  RowLayout {
    visible: !root.stacked
    anchors.fill: parent
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    spacing: Widget.spacing
    layoutDirection: root.toLeft ? Qt.RightToLeft : Qt.LeftToRight

    StyledIcon {
      visible: root.properties.icon !== ""
      text: root.properties.icon
      textColor: root.tint
    }

    StyledLabel {
      Layout.fillWidth: true
      visible: !root.compact && root.label !== ""
      text: root.label
      overflow: "line"
      textColor: root.tint
      horizontalAlignment: root.toLeft ? Text.AlignRight : Text.AlignLeft
    }

    StyledIcon {
      Layout.alignment: Qt.AlignVCenter
      text: root.toLeft ? "chevron_left" : "chevron_right"
      textColor: root.isOpen ? root.tint : Style.textMuted
    }
  }

  // Square or taller (a tile): the icon over the label, sized to the slot,
  // the arrow under them; the label where there's room for it
  ColumnLayout {
    id: tile
    visible: root.stacked
    anchors.centerIn: parent
    width: root.innerWidth
    spacing: Widget.spacing / 2

    readonly property int iconSize: Math.round(Math.max(Style.typeBody * 1.2, Math.min(root.innerWidth * 0.5, root.innerHeight * 0.3, Style.typeBody * 3))) // fitted: the tile
    readonly property int labelSize: root.innerWidth < Widget.height * 2 ? Style.typeCaption : Style.typeBody
    // Icon, two lines of label and the arrow
    readonly property bool roomForLabel: root.innerHeight >= tile.iconSize + tile.labelSize * 3.2 + Style.typeBody * 1.5

    StyledIcon {
      Layout.alignment: Qt.AlignHCenter
      visible: root.properties.icon !== ""
      text: root.properties.icon
      textSize: tile.iconSize
      textColor: root.tint
    }

    StyledText {
      Layout.fillWidth: true
      // Wrapped to the slot, not as wide as it would like
      Layout.maximumWidth: root.innerWidth
      visible: tile.roomForLabel && root.label !== ""
      text: root.label
      textSize: tile.labelSize
      overflow: "wrap"
      maxLines: 2
      textColor: root.tint
      horizontalAlignment: Text.AlignHCenter
    }

    StyledIcon {
      Layout.alignment: Qt.AlignHCenter
      textSize: Math.round(Style.typeBody * 1.5) // fitted: the tile
      text: root.toLeft ? "chevron_left" : "chevron_right"
      textColor: root.isOpen ? root.tint : Style.textMuted
    }
  }
}
