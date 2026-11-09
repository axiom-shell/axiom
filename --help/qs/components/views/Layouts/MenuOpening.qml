pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable

// The top of an edge menu's Opening group: try it on screen, what opens
// it besides hovering its edge, and buttons that add a bar button or a
// keybind for it
ColumnLayout {
  id: root

  required property var menu
  readonly property bool previewingThis: !!root.menu && OverlayManager.menus.previewing !== "" && OverlayManager.menus.previewing === root.menu.id
  readonly property var references: OverlayManager.menus.references(root.menu?.id ?? "")
  // A submenu menu opens only from Submenu modules
  readonly property bool submenu: EdgeMenusConfig.isSubmenu(root.menu)

  Layout.fillWidth: true
  spacing: Widget.spacing

  RowLayout {
    Layout.fillWidth: true
    spacing: Widget.spacing

    StyledTextButton {
      Layout.fillWidth: true
      enabled: OverlayManager.menus.canPreview(root.menu)
      opacity: enabled ? 1 : 0.5
      iconText: root.previewingThis ? "visibility_off" : "visibility"
      text: root.previewingThis ? I18n.tr("Hide from screen") : I18n.tr("Show on screen")
      textPadding: Widget.smallPadding
      backgroundColor: root.previewingThis ? Theme.accent : Theme.backgroundHighlight
      textColor: root.previewingThis ? Theme.background : Theme.foreground
      onClicked: OverlayManager.menus.togglePreviewing()
    }

    StyledTextButton {
      Layout.fillWidth: true
      iconText: "layers"
      text: OverlayManager.menus.showingOthers ? I18n.tr("Hide other menus") : I18n.tr("Show other menus")
      textPadding: Widget.smallPadding
      backgroundColor: OverlayManager.menus.showingOthers ? Theme.accent : Theme.backgroundHighlight
      textColor: OverlayManager.menus.showingOthers ? Theme.background : Theme.foreground
      onClicked: OverlayManager.menus.toggleShowingOthers()
    }
  }

  StyledText {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    text: {
      if (root.submenu)
        return OverlayManager.menus.canPreview(root.menu) ? I18n.tr("Holds it open beside the menu it opens from while you edit it, showing unsaved changes.") : I18n.tr("Add a Submenu module opening it to an enabled floating menu to show it.");
      return OverlayManager.menus.canPreview(root.menu) ? I18n.tr("Holds the menu open on its screen while you edit it, showing unsaved changes.") : I18n.tr("Enable the menu to show it.");
    }
    textSize: Appearance.fontSizeBy(-2)
    opacity: 0.7
  }

  StyledText {
    Layout.topMargin: Widget.spacing / 2
    text: I18n.tr("Also opened by")
  }

  Repeater {
    model: root.references.length

    // Goes to it: the bar editor, the keybind editor or the menu
    Item {
      id: reference
      required property int index
      readonly property var ref: root.references[reference.index] ?? ({})
      Layout.fillWidth: true
      implicitHeight: referenceRow.implicitHeight

      RowLayout {
        id: referenceRow
        anchors.fill: parent
        spacing: Widget.spacing

        StyledIcon {
          text: reference.ref.kind === "bind" ? "keyboard" : reference.ref.kind === "submenu" ? "menu_open" : "toolbar"
          textColor: Theme.accent
        }
        StyledText {
          Layout.fillWidth: true
          text: reference.ref.label ?? ""
          font.underline: referenceArea.containsMouse
          elide: Text.ElideRight
        }
        StyledIcon {
          text: "arrow_forward"
          textColor: Theme.accent
          opacity: referenceArea.containsMouse ? 1 : 0.5
        }
      }

      MouseArea {
        id: referenceArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: OverlayManager.menus.goToReference(reference.ref)
      }
    }
  }

  StyledText {
    id: nothingYet
    visible: root.references.length === 0
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    readonly property bool opensAnyway: !root.submenu && (root.menu?.open?.onHover ?? false)
    text: root.submenu ? I18n.tr("Nothing yet: add a Submenu module to a floating menu and pick this one.") : nothingYet.opensAnyway ? I18n.tr("Nothing else yet: it opens when the pointer rests on its edge.") : I18n.tr("Nothing yet: turn on Open on hover, or add a bar button or keybind.")
    textSize: Appearance.fontSizeBy(-2)
    textColor: nothingYet.opensAnyway ? Theme.foreground : Theme.warning
    opacity: nothingYet.opensAnyway ? 0.7 : 1
  }

  OpenerButtons {
    visible: !root.submenu
    saved: OverlayManager.menus.isSaved(root.menu)
    unsavedHint: I18n.tr("Save the menu to add a bar button or keybind for it.")
    onBarButtonRequested: barIndex => OverlayManager.menus.addBarButton(barIndex, "right")
    onKeybindRequested: OverlayManager.menus.addKeybind()
  }
}
