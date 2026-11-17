pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.ui
import qs.components.reusable
import qs.components.forms

// An edge menu's Opening section: try it on screen, what opens
// it besides hovering its edge (links to each, SettingsLink), and buttons that
// add a bar button or a keybind for it
ColumnLayout {
  id: root

  required property var menu
  readonly property bool previewingThis: !!root.menu && OverlayManager.menus.previewing !== "" && OverlayManager.menus.previewing === root.menu.id
  readonly property var references: OverlayManager.menus.references(root.menu?.id ?? "")
  // A free menu has no edge to hover: shown beside a menu opening it from
  // a Submenu module, else on its own (MenuEditor.canPreview)
  readonly property bool free: MenusConfig.isFree(root.menu)
  readonly property bool besideParent: root.free && OverlayManager.menus.submenuParentOf(root.menu?.id ?? "") !== null

  Layout.fillWidth: true
  spacing: Widget.spacing

  // One row while both buttons fit at their widest, else one under the other
  // (decided from implicit widths only, as SchemaToggle's `stacked` is)
  GridLayout {
    id: buttons
    Layout.fillWidth: true
    // Its two-column least width must not hold the pane open: below it, it stacks
    Layout.minimumWidth: 0
    columnSpacing: Widget.spacing
    rowSpacing: Widget.spacing
    columns: buttons.width > 0 && previewButton.implicitWidth + othersButton.implicitWidth + buttons.columnSpacing > buttons.width ? 1 : 2

    StyledTextButton {
      id: previewButton
      Layout.fillWidth: true
      enabled: OverlayManager.menus.canPreview(root.menu)
      kind: root.previewingThis ? "primary" : "tonal"
      iconText: root.previewingThis ? "visibility_off" : "visibility"
      text: root.previewingThis ? I18n.tr("Hide from screen") : I18n.tr("Show on screen")
      textPadding: Widget.smallPadding
      onClicked: OverlayManager.menus.togglePreviewing()
    }

    StyledTextButton {
      id: othersButton
      Layout.fillWidth: true
      kind: OverlayManager.menus.showingOthers ? "primary" : "tonal"
      iconText: "layers"
      text: OverlayManager.menus.showingOthers ? I18n.tr("Hide other menus") : I18n.tr("Show other menus")
      textPadding: Widget.smallPadding
      onClicked: OverlayManager.menus.toggleShowingOthers()
    }
  }

  StyledText {
    Layout.fillWidth: true
    overflow: "wrap"
    text: {
      if (root.besideParent)
        return I18n.tr("Holds it open beside the menu it opens from while you edit it, showing unsaved changes.");
      if (root.free)
        return OverlayManager.menus.canPreview(root.menu) ? I18n.tr("Holds it open where a keybind opens it while you edit it, showing unsaved changes.") : I18n.tr("Enable the menu to show it.");
      return OverlayManager.menus.canPreview(root.menu) ? I18n.tr("Holds the menu open on its screen while you edit it, showing unsaved changes.") : I18n.tr("Enable the menu to show it.");
    }
    role: "caption"
    tone: "muted"
  }

  SectionHeading {
    Layout.topMargin: Widget.spacing / 2
    title: I18n.tr("Also opened by")
  }

  // Each goes to it: the bar editor, the keybind editor or the menu
  Repeater {
    model: root.references.length

    SettingsLink {
      id: reference
      required property int index
      readonly property var ref: root.references[reference.index] ?? ({})
      Layout.fillWidth: true
      icon: reference.ref.kind === "bind" ? "keyboard" : reference.ref.kind === "submenu" ? "menu_open" : "toolbar"
      text: reference.ref.label ?? ""
      run: () => OverlayManager.menus.goToReference(reference.ref)
    }
  }

  StyledText {
    id: nothingYet
    visible: root.references.length === 0
    Layout.fillWidth: true
    overflow: "wrap"
    readonly property bool opensAnyway: !root.free && (root.menu?.open?.onHover ?? false)
    text: root.free ? I18n.tr("Nothing yet: add a bar button or keybind, make it a bar widget's popout, or pick it in a menu's Submenu module.") : nothingYet.opensAnyway ? I18n.tr("Nothing else yet: it opens when the pointer rests on its edge.") : I18n.tr("Nothing yet: turn on Open on hover, or add a bar button or keybind.")
    role: "caption"
    tone: nothingYet.opensAnyway ? "muted" : "warning"
  }

  OpenerButtons {
    saved: OverlayManager.menus.isSaved(root.menu)
    unsavedHint: I18n.tr("Save the menu to add a bar button or keybind for it.")
    onBarButtonRequested: barIndex => OverlayManager.menus.addBarButton(barIndex, "right")
    onKeybindRequested: OverlayManager.menus.addKeybind()
  }
}
