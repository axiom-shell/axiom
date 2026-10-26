pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.session
import qs.services.ui
import qs.components.reusable
import qs.components.forms
import qs.components.content.base

// i18n: keys from the schema (titles, descriptions)
// Layouts editor, left: the overlay pages, the desktop, the lock screen
// and the edge menus, then what's selected: a page's name and icon and
// what opens it, a menu's settings in groups (from the schema's EdgeMenu
// definition, its Opening group led by how to try and open it), the
// desktop's (led by which monitor's layout is edited), or the lock
// screen's (led by its preview), and anything that blocks saving
Item {
  id: root

  required property var dragLayer

  // What's being edited (Layouts): a page (`view`), a `menu` or a screen
  // layout (`screenTarget`: the desktop's, the lock screen's or the login
  // screen's ScreenLayoutTarget); the others are null
  required property var view
  required property var menu
  required property var screenTarget
  readonly property var screenLayout: root.screenTarget?.layout ?? null
  readonly property bool isDesktop: OverlayManager.editTarget === "desktop"
  // A monitor of the desktop's (not all monitors or the primary one)
  readonly property bool isDesktopMonitor: root.isDesktop && DesktopManager.isMonitorTarget(DesktopManager.selectedTarget)
  readonly property bool isCustom: root.view?.type === "Custom"
  readonly property var problems: OverlayManager.problems.concat(OverlayManager.menus.problems, DesktopManager.editor.problems, LockManager.editor.problems, GreeterManager.editor.problems)

  // StyledTextEntry writes each keystroke back to its `text`, which drops
  // any binding on it, so the name is pushed in rather than bound: on every
  // draft change unless it's being typed, always when another page is
  // selected. Only typing renames (textEdited), never a name pushed in.
  function syncName(force) {
    if (force || !nameEntry.input.activeFocus)
      nameEntry.text = OverlayManager.selectedView()?.name ?? "";
  }
  Connections {
    target: OverlayManager
    function onSelectedViewIndexChanged() {
      root.syncName(true);
    }
    function onLocalViewsChanged() {
      root.syncName(false);
    }
  }
  Component.onCompleted: root.syncName(true)

  // Group titles: I18n.tr("General") I18n.tr("Opening") I18n.tr("Placement")
  // I18n.tr("Style") I18n.tr("Closing") I18n.tr("Advanced") I18n.tr("Other")
  // I18n.tr("Grid") I18n.tr("Background")
  TitledCard {
    title: I18n.tr("Layouts")
    scrollKey: "Layouts"
    showActions: false

    PagesSection {
      Layout.fillWidth: true
      dragLayer: root.dragLayer
    }

    MenusSection {
      Layout.fillWidth: true
      dragLayer: root.dragLayer
    }

    StyledSeparator {
      Layout.fillWidth: true
      Layout.topMargin: Widget.spacing
      opacity: 0.3
    }

    // A Custom page
    FieldGroup {
      visible: root.isCustom
      Layout.topMargin: Widget.spacing
      title: I18n.tr("Page")
      description: I18n.tr("Its name and icon show in the page navigator.")

      StyledTextEntry {
        id: nameEntry
        Layout.fillWidth: true
        placeholderText: I18n.tr("Page name")
        onTextEdited: OverlayManager.renameView(OverlayManager.selectedViewIndex, nameEntry.text)
      }

      SchemaPropertiesForm {
        Layout.fillWidth: true
        propertiesSchema: ({
            "icon": OverlayConfig.customViewSchema.icon,
            "fineGrid": OverlayConfig.customViewSchema.layout.properties.grid.properties.fine
          })
        order: ["icon", "fineGrid"]
        // fineGrid stands for layout.grid.fine (updateViewField rescales the
        // modules with it)
        values: Object.assign({}, root.view ?? {}, {
          "fineGrid": root.view?.layout?.grid?.fine ?? false
        })
        onEdited: (path, value) => OverlayManager.updateViewField(OverlayManager.selectedViewIndex, path[0], value)
      }

      SettingsLink {
        Layout.fillWidth: true
        setting: "Overlay.navigator"
      }
    }

    // A tool page
    FieldGroup {
      visible: root.view !== null && !root.isCustom
      Layout.topMargin: Widget.spacing
      title: I18n.tr("Tool page")
      description: I18n.tr("A page of its own, with no layout to edit. Tools show as icons after your pages in the navigator.")

      SchemaSwitch {
        label: I18n.tr("Show in the navigator")
        checked: root.view?.visible !== false
        onToggled: newValue => OverlayManager.setViewVisible(OverlayManager.selectedViewIndex, newValue)
      }

      // Goes to it (only while it's shown)
      SettingsLink {
        Layout.fillWidth: true
        page: root.view?.type ?? ""
      }
    }

    // How a page opens besides the navigator
    FieldGroup {
      visible: root.view !== null
      Layout.topMargin: Widget.spacing
      title: I18n.tr("Opening")
      description: I18n.tr("A bar button or keybind that opens the overlay on this page.")

      OpenerButtons {
        saved: OverlayManager.isSaved(root.view)
        unsavedHint: I18n.tr("Name and save the page to add a bar button or keybind for it.")
        onBarButtonRequested: barIndex => OverlayManager.addBarButton(barIndex, "right")
        onKeybindRequested: OverlayManager.addKeybind()
      }
    }

    // An edge menu. A ColumnLayout's Repeater re-runs its model on every
    // draft edit: the condition keeps the model the same while one is
    // selected
    Repeater {
      model: root.menu !== null ? EdgeMenusConfig.fieldGroups : []

      delegate: FieldGroup {
        id: group
        required property var modelData
        Layout.topMargin: Widget.spacing
        title: I18n.tr(group.modelData.title)

        Loader {
          Layout.fillWidth: true
          active: group.modelData.title === "Opening"
          visible: active
          sourceComponent: MenuOpening {
            menu: root.menu
          }
        }

        SchemaPropertiesForm {
          Layout.fillWidth: true
          propertiesSchema: group.modelData.schema
          order: group.modelData.keys
          // The whole menu, so x-showIf sees keys from other groups
          values: root.menu ?? ({})
          onEdited: (path, value) => OverlayManager.menus.updateMenuField(path[0], value)
        }
      }
    }

    // The desktop: which layout is edited (all monitors, the primary one,
    // a monitor), whether it shows, and a monitor's own layout added or
    // taken away
    FieldGroup {
      visible: root.isDesktop
      Layout.topMargin: Widget.spacing
      title: I18n.tr("Desktop")
      description: root.screenTarget?.description ?? ""

      StyledComboEntry {
        Layout.fillWidth: true
        icon: "monitor"
        options: DesktopManager.targets.map(target => ({
              "value": target.key,
              "label": I18n.tr("{0} — {1}", target.label, target.status)
            }))
        value: DesktopManager.selectedTarget
        onPicked: value => DesktopManager.selectTarget(value)
      }

      SchemaSwitch {
        visible: root.screenLayout !== null
        label: root.isDesktopMonitor ? I18n.tr("Show on this monitor") : I18n.tr("Show on the desktop")
        description: root.isDesktopMonitor ? I18n.tr("Off leaves this monitor's desktop empty.") : ""
        checked: root.screenLayout?.enabled ?? false
        onToggled: newValue => DesktopManager.setEnabled(newValue)
      }

      StyledTextButton {
        visible: root.isDesktopMonitor && root.screenLayout === null
        iconText: "add"
        text: I18n.tr("Give it its own layout")
        onClicked: DesktopManager.createForTarget()
      }

      StyledTextButton {
        visible: root.isDesktopMonitor && root.screenLayout !== null
        iconText: "delete"
        text: I18n.tr("Remove its own layout")
        onClicked: DesktopManager.removeTarget()
      }
    }

    // A screen layout (`screenTarget`): Show on screen where it has one,
    // then its fields. As for the menu, the condition keeps the model the
    // same while it's selected
    FieldGroup {
      visible: root.screenLayout !== null && root.screenTarget.canPreview
      Layout.topMargin: Widget.spacing
      title: root.screenTarget?.title ?? ""
      description: root.screenTarget?.description ?? ""

      StyledTextButton {
        iconText: "visibility"
        text: I18n.tr("Show on screen")
        onClicked: root.screenTarget.screenEditor.startPreview()
      }
    }

    Repeater {
      model: root.screenLayout !== null ? root.screenTarget.fieldGroups : []

      delegate: FieldGroup {
        id: screenGroup
        required property var modelData
        Layout.topMargin: Widget.spacing
        title: I18n.tr(screenGroup.modelData.title)

        SchemaPropertiesForm {
          Layout.fillWidth: true
          propertiesSchema: screenGroup.modelData.schema
          order: screenGroup.modelData.keys
          values: root.screenLayout ?? ({})
          onEdited: (path, value) => root.screenTarget.screenEditor.updateLayoutField(path[0], value)
        }
      }
    }

    FieldGroup {
      visible: root.problems.length > 0
      Layout.topMargin: Widget.spacing
      title: I18n.tr("Can't save yet")

      IssueList {
        issues: root.problems.map(text => ({
              "level": "error",
              "text": text
            }))
      }
    }
  }
}
