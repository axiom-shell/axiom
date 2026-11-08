pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui
import qs.components.reusable

// The OSD section's first card (its `x-card`, spanning the page): the OSDs
// as tabs, one shown at a time: where it sits (the screen picker), a Show
// button and its Placement settings under them, beside them with the room
// its Timing and behaviour (its schema's `x-group`s), then what it shows (its systems: OSDSystemsEditor, the list
// beside the selected one's form) and its bars, whichever system they're
// settings of, with their layout (OSDBarsEditor) (EntryListCard, `wide`).
// Preview, in the header, holds the shown OSD open while it's edited
// (ShellManager.osdPinned: it follows the tab), the system or bar
// selected last outlined on it (ShellManager.osdFocus); off as the page
// opens, and again as the card folds or goes (another category, the
// overlay closing).
EntryListCard {
  id: root

  // Preview is on
  property bool previewing: false
  // The system selected last, in Shows or Bars: the preview outlines it
  property string focusType: ""
  // The OSD this card holds open ("" for none)
  property string _held: ""
  readonly property string _pinId: root.previewing && root.entry ? root.entry.id : ""

  // Lets go of the OSD it holds, unless another card took it since
  function _letGo() {
    if (root._held !== "" && ShellManager.osdPinned === root._held) {
      ShellManager.osdPinned = "";
      ShellManager.osdFocus = "";
    }
    root._held = "";
  }

  on_PinIdChanged: {
    root._letGo();
    if (root._pinId === "")
      return;
    root._held = root._pinId;
    ShellManager.osdFocus = root.focusType;
    ShellManager.osdPinned = root._pinId;
    ShellManager.showOsd(root._pinId);
  }
  onFocusTypeChanged: {
    if (root._held !== "" && ShellManager.osdPinned === root._held)
      ShellManager.osdFocus = root.focusType;
  }
  onCollapsedChanged: {
    if (root.collapsed)
      root.previewing = false;
  }
  Component.onDestruction: root._letGo()

  sectionKey: "OSD"
  listKey: "items"
  entryType: "OSDEntry"
  savedEntries: OSDConfig.osds
  pickerHint: I18n.tr("Click a spot or drag to place it, to an edge to attach it; fine-tune below. Show opens it as a change would.")
  idBase: "osd"
  // A second OSD held off the right edge, so it doesn't sit on the first
  seed: ({
      "edge": "right",
      "detached": true,
      "systems": [
        {
          "type": "Brightness"
        }
      ]
    })
  ownKeys: ["systems", "barLayout"]
  wide: true
  labelOf: osd => OSDConfig.labelOf(osd)
  onShow: id => ShellManager.showOsd(id)

  headerButtons: StyledTextButton {
    implicitHeight: Widget.height - Widget.px(4)
    iconText: "visibility"
    text: I18n.tr("Preview")
    tooltipText: I18n.tr("Keep this OSD open while you edit it, the selected system outlined")
    backgroundColor: root.previewing ? Theme.accent : Theme.backgroundHighlight
    textColor: root.previewing ? Theme.background : Theme.foreground
    onClicked: root.previewing = !root.previewing
  }

  entryContent: [
    OSDSystemsEditor {
      id: systemsEditor
      entry: root.entry
      foldKey: root.foldKey + ":systems"
      onEdited: systems => root.edit({
          "systems": systems
        })
      onSelectedTypeChanged: root.focusType = systemsEditor.selectedType
      Component.onCompleted: root.focusType = systemsEditor.selectedType
    },
    OSDBarsEditor {
      id: barsEditor
      entry: root.entry
      foldKey: root.foldKey + ":bars"
      onEdited: values => root.edit(values)
      onSelectedTypeChanged: root.focusType = barsEditor.selectedType
    }
  ]
}
