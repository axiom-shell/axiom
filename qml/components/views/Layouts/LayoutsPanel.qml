pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.session
import qs.services.ui
import qs.components.reusable
import qs.components.content.base
import qs.components.forms
import qs.components.views.base

// Layouts editor, left: the overlay pages, the tools, the menus and the
// screens (desktop, lock screen, login screen) pinned above (scrolling
// inside past PinnedList's share of the pane), each a section that folds
// (open or closed kept across restarts, EditsManager.layoutSectionOpen), then
// what's selected: a page's name and icon and what opens it, a menu's
// settings in groups (from the schema's Menu definition, led by how to try
// and open it), the desktop's (led by which monitor's layout is edited), or
// the lock screen's (led by its preview); anything that blocks saving is the
// pane's footer
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
  readonly property var problems: OverlayManager.layoutsProblems

  // A tool page selected from outside opens the Tools section (closing it
  // by hand still works: it only opens on a new selection), and that open is
  // kept like any other
  function revealTool() {
    if (OverlayManager.editTarget === "page" && OverlayConfig.isTool(OverlayManager.selectedView()?.type ?? ""))
      EditsManager.setLayoutSectionOpen("tools", true);
  }
  Connections {
    target: OverlayManager
    function onSelectedViewIndexChanged() {
      // Another page selected shows its name even while the entry is
      // focused (CommitEntry only takes a pushed name while unfocused)
      nameEntry.text = OverlayManager.selectedView()?.name ?? "";
      root.revealTool();
    }
    function onEditTargetChanged() {
      root.revealTool();
    }
  }
  Component.onCompleted: root.revealTool()

  // Group titles (the Menu definition's `x-group`s and the screen layouts'):
  // I18n.tr("General") I18n.tr("Placement") I18n.tr("Size") I18n.tr("Look")
  // I18n.tr("Style") I18n.tr("Behaviour") I18n.tr("Motion") I18n.tr("Closing")
  // I18n.tr("Other") I18n.tr("Grid") I18n.tr("Background")
  // Two boxes a card gap apart, as the bar editor's inspector and library:
  // the lists with the page's title above, and the selection's cards below
  ColumnLayout {
    anchors.fill: parent
    spacing: OverlayConfig.cardSpacing

    Surface {
      id: listsBox
      Layout.fillWidth: true
      Layout.preferredHeight: listsColumn.implicitHeight + Widget.padding * 2
      tone: "surface"
      clip: true

      ColumnLayout {
        id: listsColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Widget.padding
        spacing: 0

        CardHeader {
          title: I18n.tr("Layouts")
          icon: "dashboard_customize"
          showActions: false
        }

        StyledSeparator {
          Layout.fillWidth: true
          Layout.topMargin: Widget.spacing / 2
          Layout.bottomMargin: Widget.spacing / 2
        }

        PinnedList {
          Layout.fillWidth: true
          shareOf: root

          PagesSection {
            Layout.fillWidth: true
            dragLayer: root.dragLayer
          }

          MenusSection {
            Layout.fillWidth: true
            dragLayer: root.dragLayer
          }

          ListSection {
            Layout.fillWidth: true
            Layout.topMargin: Widget.spacing
            title: I18n.tr("Screens")
            count: 1 + (OverlayManager.lockscreenEditable ? 1 : 0) + (OverlayManager.greeterEditable ? 1 : 0)
            hint: I18n.tr("The desktop, lock screen and login screen.")
            collapsible: true
            open: EditsManager.layoutSectionOpen("screens")
            onToggled: EditsManager.setLayoutSectionOpen("screens", !open)

            // Not dragged: these aren't the navigator's pages
            ListEntryRow {
              Layout.fillWidth: true
              icon: "desktop_windows"
              label: I18n.tr("Desktop")
              selected: OverlayManager.editTarget === "desktop"
              changed: DesktopManager.editor.isDirty
              onClicked: OverlayManager.editDesktop()
            }

            ListEntryRow {
              visible: OverlayManager.lockscreenEditable
              Layout.fillWidth: true
              icon: "lock"
              label: I18n.tr("Lock screen")
              selected: OverlayManager.editTarget === "lockscreen"
              changed: LockManager.editor.isDirty
              onClicked: OverlayManager.editLockscreen()
            }

            // Once it's set up (Settings → Login screen)
            ListEntryRow {
              visible: OverlayManager.greeterEditable
              Layout.fillWidth: true
              icon: "login"
              label: I18n.tr("Login screen")
              selected: OverlayManager.editTarget === "greeter"
              changed: GreeterManager.editor.isDirty
              onClicked: OverlayManager.editGreeter()
            }
          }
        }
      }
    }

    Surface {
      Layout.fillWidth: true
      Layout.fillHeight: true
      tone: "surface"
      clip: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Widget.padding
        spacing: Widget.spacing

        CardScroll {
          id: editorScroll
          Layout.fillWidth: true
          Layout.fillHeight: true

          ScrollMemory {
            flickable: editorScroll.flickable as Flickable
            key: "Layouts"
          }

          // A Custom page
          FieldGroup {
            visible: root.isCustom
            title: I18n.tr("Page")
            description: I18n.tr("Its name and icon show in the page navigator.")

            // Only typing renames (live), never a name pushed in
            FormRow {
              bodyHeight: nameEntry.implicitHeight

              CommitEntry {
                id: nameEntry
                width: parent.width
                live: true
                value: OverlayManager.selectedView()?.name ?? ""
                placeholderText: I18n.tr("Page name")
                onEdited: text => OverlayManager.renameView(OverlayManager.selectedViewIndex, text)
              }
            }

            SchemaPropertiesForm {
              Layout.fillWidth: true
              // Under the name row
              follows: true
              propertiesSchema: ({
                  "icon": OverlayConfig.customViewSchema.icon,
                  "fineGrid": OverlayConfig.customViewSchema.layout.properties.grid.properties.fine,
                  "sizing": OverlayConfig.customViewSchema.sizing
                })
              order: ["icon", "fineGrid", "sizing"]
              // fineGrid stands for layout.grid.fine (updateViewField rescales the
              // modules with it)
              values: Object.assign({}, root.view ?? {}, {
                "fineGrid": root.view?.layout?.grid?.fine ?? false
              })
              onEdited: (path, value) => OverlayManager.updateViewField(OverlayManager.selectedViewIndex, path[0], value)
            }

            SettingsLink {
              Layout.fillWidth: true
              Layout.topMargin: Style.space2
              setting: "Overlay.navigator"
            }
          }

          // A tool page
          FieldGroup {
            visible: root.view !== null && !root.isCustom
            title: I18n.tr("Tool page")
            description: I18n.tr("A page of its own, with no layout to edit. Tools show as icons after your pages in the navigator.")

            SwitchRow {
              label: I18n.tr("Show in the navigator")
              checked: root.view?.visible !== false
              onToggled: newValue => OverlayManager.setViewVisible(OverlayManager.selectedViewIndex, newValue)
            }

            // How big it draws: its Content size zooms the whole page
            SchemaPropertiesForm {
              Layout.fillWidth: true
              // Under the switch
              follows: true
              propertiesSchema: root.view !== null && !root.isCustom ? ({
                  "sizing": OverlayConfig.viewSchema(root.view.type).sizing
                }) : ({})
              order: ["sizing"]
              values: root.view ?? ({})
              onEdited: (path, value) => OverlayManager.updateViewField(OverlayManager.selectedViewIndex, path[0], value)
            }

            // Goes to it (only while it's shown)
            SettingsLink {
              Layout.fillWidth: true
              Layout.topMargin: Style.space2
              page: root.view?.type ?? ""
            }
          }

          // How a page opens besides the navigator
          FieldGroup {
            visible: root.view !== null
            title: I18n.tr("Opening")
            description: I18n.tr("A bar button or keybind that opens the overlay on this page.")

            OpenerButtons {
              saved: OverlayManager.isSaved(root.view)
              unsavedHint: I18n.tr("Name and save the page to add a bar button or keybind for it.")
              onBarButtonRequested: barIndex => OverlayManager.addBarButton(barIndex, "right")
              onKeybindRequested: OverlayManager.addKeybind()
            }
          }

          // An edge menu's opening: try it on screen, what opens it, a bar button
          // or keybind that does (open.onHover is among the Behaviour fields)
          FieldGroup {
            visible: root.menu !== null
            title: I18n.tr("Opening")

            MenuOpening {
              menu: root.menu
            }
          }

          // An edge menu. A ColumnLayout's Repeater re-runs its model on every
          // draft edit: the condition keeps the model the same while one is
          // selected
          Repeater {
            model: root.menu !== null ? MenusConfig.fieldGroups : []

            delegate: FieldGroup {
              id: group
              required property var modelData
              title: I18n.tr(group.modelData.title)

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
            title: I18n.tr("Desktop")
            description: root.screenTarget?.description ?? ""

            FormRow {
              bodyHeight: targetCombo.implicitHeight

              StyledComboEntry {
                id: targetCombo
                width: parent.width
                icon: "monitor"
                options: DesktopManager.targets.map(target => ({
                      "value": target.key,
                      "label": I18n.tr("{0} — {1}", target.label, target.status)
                    }))
                value: DesktopManager.selectedTarget
                onPicked: value => DesktopManager.selectTarget(value)
              }
            }

            SwitchRow {
              shown: root.screenLayout !== null
              label: root.isDesktopMonitor ? I18n.tr("Show on this monitor") : I18n.tr("Show on the desktop")
              description: root.isDesktopMonitor ? I18n.tr("Off leaves this monitor's desktop empty.") : ""
              checked: root.screenLayout?.enabled ?? false
              onToggled: newValue => DesktopManager.setEnabled(newValue)
            }

            StyledTextButton {
              visible: root.isDesktopMonitor && root.screenLayout === null
              Layout.topMargin: Style.space2
              iconText: "add"
              text: I18n.tr("Give it its own layout")
              onClicked: DesktopManager.createForTarget()
            }

            StyledTextButton {
              visible: root.isDesktopMonitor && root.screenLayout !== null
              Layout.topMargin: Style.space2
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
        }

        FieldGroup {
          visible: root.problems.length > 0
          title: I18n.tr("Can't save yet")
          // A blocker stays visible
          foldable: false

          IssueList {
            issues: root.problems.map(text => ({
                  "level": "error",
                  "text": text
                }))
          }
        }
      }
    }
  }
}
