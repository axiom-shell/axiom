pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui

// The OSD section's first card (its `x-card`, spanning the page): the OSDs
// as tabs, one shown at a time: where it sits (the screen picker), a Show
// button and, beside them with the room, its other settings (Place and
// timing), then what it shows (its systems: OSDSystemsEditor, the list
// beside the selected one's form) and its bars, whichever system they're
// settings of, with their layout (OSDBarsEditor) (EntryListCard, `wide`).
EntryListCard {
  id: root

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
  otherTitle: I18n.tr("Place and timing")
  wide: true
  labelOf: osd => OSDConfig.labelOf(osd)
  onShow: id => ShellManager.showOsd(id)

  entryContent: [
    OSDSystemsEditor {
      entry: root.entry
      foldKey: root.foldKey + ":systems"
      onEdited: systems => root.edit({
          "systems": systems
        })
    },
    OSDBarsEditor {
      entry: root.entry
      foldKey: root.foldKey + ":bars"
      onEdited: values => root.edit(values)
    }
  ]
}
