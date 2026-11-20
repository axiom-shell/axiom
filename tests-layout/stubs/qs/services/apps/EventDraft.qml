import QtQuick

// Stand-in for the shell's EventDraft in the layout harness: an editor that is
// never open.
QtObject {
  property bool active: false
  property var draft: null
  property string calendar: ""
  property string title: ""
  property string location: ""
  property string description: ""
  property bool allDay: false
  property real start: 0
  property real end: 0
  property string repeat: "none"
  property int reminder: -1
  property bool isNew: true
  property bool readOnly: false
  property bool busy: false
  property string error: ""
  property string asking: ""

  function open(draft) {
  }

  function close() {
  }

  function setStart(value) {
  }

  function save() {
  }

  function saveAs(scope) {
  }

  function remove() {
  }

  function removeAs(scope) {
  }
}
