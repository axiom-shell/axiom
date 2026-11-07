pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui

// The OSD section's first card (its `x-card`): the OSDs as tabs, one shown
// at a time: where it sits (the screen picker), a Show button,
// then what it shows (its systems), folding, its other settings, and its
// bars' layout at the bottom (EntryListCard).
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
  // (Stop-gap: the systems list in the generic form until its own editor)
  sections: ["systems", "barLayout"]
  lastSections: ["barLayout"]
  otherTitle: I18n.tr("Place and timing")
  labelOf: osd => OSDConfig.labelOf(osd)
  onShow: id => ShellManager.showOsd(id)
}
