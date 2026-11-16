pragma Singleton
import QtQuick

// Stand-in for the shell's BuildQueueManager in the layout harness: nothing
// is queued (a StreamedLoader under test builds at once, `stream: false`).
QtObject {
  property int pending: 0
  // The label of each request, for a test of who streams
  property var labels: []

  function request(owner, job, label) {
    labels.push(label);
    job();
  }

  function cancel(owner) {
  }
}
