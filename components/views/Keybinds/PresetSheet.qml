pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.services.compositor
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts

// The Keybinds editor's presets, over the list: on the left the built-in
// ones and those saved from here (KeybindManager.editor.savedPresets), each group
// folding, and a field to save the binds as one; on the right what the
// chosen one would do bind by bind (KeybindManager.editor.presetPlan), each new
// or taken key with a checkbox (a taken key's bind pauses), and Apply for
// the checked ones. A saved preset replaces every bind instead, unless
// switched to Merge. Like any edit it waits for Save, and Undo takes it
// back; saving or removing a preset is saved at once.
Popup {
  id: root

  property string presetId: ""
  // Its plan, and the keys (BindKeys.keyId) checked
  property var plan: []
  property var chosen: []
  readonly property var preset: KeybindManager.editor.presets.find(p => p.id === root.presetId) ?? KeybindManager.editor.savedPresets.find(p => p.id === root.presetId) ?? null
  readonly property bool saved: root.preset?.saved === true
  // A saved preset: "replace" every bind, or "merge" it like a built-in one
  property string mode: "replace"
  readonly property bool merging: !root.saved || root.mode === "merge"
  // Groups folded, for the session
  property bool builtInFolded: false
  property bool savedFolded: false

  function choose(id) {
    root.presetId = id;
    root.plan = KeybindManager.editor.presetPlan(id);
    root.chosen = root.plan.filter(step => step.chosen).map(step => step.id);
    if (!nameField.input.activeFocus)
      nameField.input.text = root.preset?.saved ? root.preset.title : "";
  }

  function saveAs(name) {
    const id = KeybindManager.editor.savePreset(name);
    if (id === "")
      return;
    newName.input.text = "";
    root.mode = "replace";
    root.savedFolded = false;
    // The list follows the config
    Qt.callLater(() => root.choose(id));
  }

  function toggle(id) {
    root.chosen = root.chosen.includes(id) ? root.chosen.filter(c => c !== id) : root.chosen.concat([id]);
  }

  modal: true
  focus: true
  padding: Widget.padding
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  onAboutToShow: root.choose(root.presetId !== "" ? root.presetId : (KeybindManager.editor.presets[0]?.id ?? ""))

  // Solid, over a dimmed list: the page itself may be see-through
  background: DropdownSurface {
    color: Theme.background
  }

  Overlay.modal: Rectangle {
    color: Qt.alpha(Theme.background, 0.6)
  }

  contentItem: ColumnLayout {
    spacing: Widget.spacing * 1.5

    RowLayout {
      Layout.fillWidth: true

      SectionHeading {
        title: I18n.tr("Presets")
        description: I18n.tr("Sets of binds to start from. Pick what to add; keys already in use are left alone unless you tick them, which pauses the bind there.")
      }

      SquareIconButton {
        size: Widget.height
        iconText: "close"
        tooltipText: I18n.tr("Close")
        Layout.alignment: Qt.AlignTop
        onClicked: root.close()
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Widget.spacing * 2

      // The presets
      StyledScrollView {
        id: presetScroll
        Layout.preferredWidth: root.width * 0.32
        Layout.fillHeight: true
        contentPadding: 0

        ColumnLayout {
          width: presetScroll.availableWidth
          spacing: Widget.spacing

          FoldingSection {
            title: I18n.tr("Built-in")
            collapsed: root.builtInFolded
            bodySpacing: 2
            onToggled: root.builtInFolded = !root.builtInFolded

            Repeater {
              model: KeybindManager.editor.presets

              delegate: ListEntryRow {
                id: presetRow
                required property var modelData
                icon: presetRow.modelData.replaces ? "swap_horiz" : "playlist_add"
                label: presetRow.modelData.title
                selected: root.presetId === presetRow.modelData.id
                onClicked: root.choose(presetRow.modelData.id)

                badges: StyledText {
                  text: presetRow.modelData.binds.length
                  textColor: presetRow.ink
                  opacity: 0.6
                  textSize: Appearance.fontSizeBy(-2)
                }
              }
            }
          }

          StyledSeparator {
            Layout.fillWidth: true
            separatorHeight: 1
            opacity: 0.3
          }

          FoldingSection {
            title: I18n.tr("Saved") + "  " + KeybindManager.editor.savedPresets.length
            collapsed: root.savedFolded
            bodySpacing: 2
            onToggled: root.savedFolded = !root.savedFolded

            Repeater {
              model: KeybindManager.editor.savedPresets

              delegate: ListEntryRow {
                id: savedRow
                required property var modelData
                icon: "bookmark"
                label: savedRow.modelData.title
                selected: root.presetId === savedRow.modelData.id
                onClicked: root.choose(savedRow.modelData.id)

                badges: StyledText {
                  text: savedRow.modelData.binds.length
                  textColor: savedRow.ink
                  opacity: 0.6
                  textSize: Appearance.fontSizeBy(-2)
                }

                RowAction {
                  row: savedRow
                  danger: true
                  iconText: "delete"
                  tooltipText: I18n.tr("Remove this preset")
                  onClicked: {
                    if (root.presetId === savedRow.modelData.id)
                      root.choose(KeybindManager.editor.presets[0]?.id ?? "");
                    KeybindManager.editor.deletePreset(savedRow.modelData.id);
                  }
                }
              }
            }

            StyledText {
              visible: KeybindManager.editor.savedPresets.length === 0
              text: I18n.tr("Save your binds as they are to come back to them later.")
              opacity: 0.6
              wrapMode: Text.WordWrap
              textSize: Appearance.fontSizeBy(-1)
              Layout.fillWidth: true
            }

            // Saves the binds as the editor has them, unsaved edits too
            RowLayout {
              Layout.fillWidth: true
              Layout.topMargin: Widget.spacing
              spacing: Widget.spacing

              StyledTextEntry {
                id: newName
                Layout.fillWidth: true
                Layout.preferredHeight: Widget.height
                placeholderText: I18n.tr("Preset name")
                onAccepted: root.saveAs(newName.text)
              }

              SquareIconButton {
                size: Widget.height
                iconText: "save"
                tooltipText: KeybindManager.editor.savedPresets.some(p => p.title === newName.text.trim()) ? I18n.tr("Save over the preset by this name") : I18n.tr("Save the binds as a preset")
                enabled: newName.text.trim() !== ""
                opacity: enabled ? 1 : 0.5
                onClicked: root.saveAs(newName.text)
              }
            }
          }
        }
      }

      StyledSeparator {
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        opacity: 0.3
      }

      // What it would do
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Widget.spacing

        StyledText {
          visible: !root.saved
          text: root.preset?.title ?? ""
          font.bold: true
          textSize: Appearance.fontSizeBy(2)
        }

        StyledText {
          visible: !root.saved
          text: root.preset?.description ?? ""
          opacity: 0.7
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        // A saved preset: its name (Enter renames it), saving the binds
        // over it, and how it applies
        RowLayout {
          visible: root.saved
          Layout.fillWidth: true
          spacing: Widget.spacing

          StyledTextEntry {
            id: nameField
            Layout.fillWidth: true
            Layout.preferredHeight: Widget.height
            placeholderText: I18n.tr("Preset name")
            onAccepted: KeybindManager.editor.renamePreset(root.presetId, nameField.text)
          }

          StyledTextButton {
            implicitHeight: Widget.height
            iconText: "save"
            text: I18n.tr("Save current binds over it")
            onClicked: {
              KeybindManager.editor.savePreset(root.preset.title);
              Qt.callLater(() => root.choose(root.presetId));
            }
          }
        }

        SegmentRow {
          visible: root.saved

          Repeater {
            // I18n.tr("Replace all binds") I18n.tr("Merge")
            model: [["replace", "Replace all binds"], ["merge", "Merge"]]

            delegate: SegmentButton {
              required property var modelData
              implicitHeight: Widget.height
              text: I18n.tr(modelData[1])
              active: root.mode === modelData[0]
              Layout.fillWidth: false
              onClicked: root.mode = modelData[0]
            }
          }
        }

        StyledScrollView {
          id: planScroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentPadding: 0

          ColumnLayout {
            width: planScroll.availableWidth
            spacing: 2

            Repeater {
              model: root.plan

              delegate: StyledContainer {
                id: step
                required property var modelData
                readonly property bool can: root.merging && step.modelData.status !== "same"
                readonly property bool on: step.can && root.chosen.includes(step.modelData.id)
                readonly property var parts: KeyNames.split(step.modelData.bind.key)
                readonly property var taken: KeybindManager.editor.binds[step.modelData.takenBy[0]] ?? null

                Layout.fillWidth: true
                implicitHeight: Widget.height + Widget.padding / 2
                backgroundColor: stepArea.containsMouse && step.can ? Theme.backgroundHighlight : "transparent"
                borderWidth: 0
                opacity: step.can || !root.merging ? 1 : 0.5

                MouseArea {
                  id: stepArea
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: step.can
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggle(step.modelData.id)
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Widget.padding / 2
                  anchors.rightMargin: Widget.padding / 2
                  spacing: Widget.spacing

                  StyledIcon {
                    visible: root.merging
                    text: !step.can ? "check" : step.on ? "check_box" : "check_box_outline_blank"
                    textColor: step.on ? Theme.accent : Theme.foreground
                  }

                  RowLayout {
                    Layout.preferredWidth: Widget.height * 5
                    Layout.maximumWidth: Widget.height * 5
                    spacing: Widget.spacing / 2
                    clip: true

                    Repeater {
                      model: step.parts.mods

                      delegate: KeyCap {
                        required property string modelData
                        text: KeyNames.modifierLabel(modelData)
                      }
                    }

                    KeyCap {
                      text: KeybindManager.displayKey(step.parts.key)
                    }

                    Item {
                      Layout.fillWidth: true
                    }
                  }

                  StyledText {
                    text: BindActions.defaultLabel(KeybindManager.actionTable, step.modelData.bind) || (KeybindManager.actionLabels[step.modelData.bind.action] ?? "")
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  StyledText {
                    visible: root.merging
                    text: {
                      switch (step.modelData.status) {
                      case "same":
                        return I18n.tr("Already bound");
                      case "resume":
                        return I18n.tr("Resumes the paused bind");
                      case "taken":
                        return I18n.tr("Pauses {0}", step.taken ? (step.taken.description || BindActions.defaultLabel(KeybindManager.actionTable, step.taken) || KeybindManager.actionLabels[step.taken.action]) : "") + (step.modelData.takenBy.length > 1 ? " +" + (step.modelData.takenBy.length - 1) : "");
                      }
                      return I18n.tr("New");
                    }
                    textColor: step.modelData.status === "taken" ? Theme.warning : Theme.foreground
                    opacity: step.modelData.status === "taken" ? 1 : 0.6
                    textSize: Appearance.fontSizeBy(-2)
                    elide: Text.ElideRight
                    Layout.maximumWidth: parent.width * 0.4
                  }
                }
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Widget.spacing

          readonly property var picked: root.plan.filter(step => step.status !== "same" && root.chosen.includes(step.id))
          readonly property int pausing: picked.reduce((sum, step) => sum + (step.status === "taken" ? step.takenBy.length : 0), 0)
          readonly property int adding: picked.filter(step => step.status !== "resume").length
          readonly property int resuming: picked.filter(step => step.status === "resume").length

          StyledText {
            wrapMode: Text.WordWrap
            text: {
              if (!root.merging)
                return I18n.tr("Replaces your {0} binds with these {1}", KeybindManager.editor.binds.length, root.plan.length);
              if (parent.resuming > 0)
                return I18n.tr("Adds {0}, pauses {1}, resumes {2}", parent.adding, parent.pausing, parent.resuming);
              if (parent.pausing > 0)
                return I18n.tr("Adds {0}, pauses {1}", parent.adding, parent.pausing);
              return I18n.tr("Adds {0}", parent.adding);
            }
            opacity: 0.7
            Layout.fillWidth: true
          }

          StyledTextButton {
            implicitHeight: Widget.height
            text: I18n.tr("Cancel")
            onClicked: root.close()
          }

          StyledTextButton {
            implicitHeight: Widget.height
            iconText: "done"
            text: I18n.tr("Apply")
            enabled: root.merging ? root.chosen.length > 0 : root.preset !== null
            opacity: enabled ? 1 : 0.5
            backgroundColor: Theme.accent
            textColor: Theme.background
            onClicked: {
              if (root.merging)
                KeybindManager.editor.applyPreset(root.presetId, root.chosen);
              else
                KeybindManager.editor.restorePreset(root.presetId);
              root.close();
            }
          }
        }
      }
    }
  }
}
