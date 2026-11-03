pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.ui

// The OSD section's first card (its `x-card`): the OSDs as tabs, one shown
// at a time: where it sits (a screen picker with presets), a Show button,
// then its status icons and its cards, each folding, its other
// settings, and its bars at the bottom (EntryListCard).
EntryListCard {
  id: root

  sectionKey: "OSD"
  listKey: "items"
  entryType: "OSDEntry"
  savedEntries: OSDConfig.osds
  pickerHint: I18n.tr("Click a spot or drag to place it; fine-tune below. Show opens it as a change would.")
  idBase: "osd"
  // A second OSD held off the right edge, so it doesn't sit on the first
  seed: ({
      "edge": "right",
      "detached": true,
      "bars": {
        "items": [
          {
            "type": "brightness",
            "icon": "",
            "showOsd": true
          }
        ]
      },
      "statuses": {
        "items": []
      },
      "cards": {
        "items": []
      }
    })
  sections: ["statuses", "cards", "bars"]
  lastSections: ["bars"]
  otherTitle: I18n.tr("Place and timing")
  labelOf: osd => OSDConfig.labelOf(osd)
  onShow: id => ShellManager.showOsd(id)
}
