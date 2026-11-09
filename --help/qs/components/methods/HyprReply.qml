pragma Singleton
import QtQuick

// Requests and replies on Hyprland's request socket (HyprlandManager's
// hypr.request), in hyprctl's wire format: "j/" asks for JSON,
// "[[BATCH]]a;b" runs several and joins their replies with blank lines.
QtObject {
  id: root

  // What separates a batch's replies
  readonly property string batchSeparator: "\n\n\n"

  // The request running `requests` (each as hyprctl sends it) in one go
  function batch(requests) {
    return "[[BATCH]]" + requests.join(";");
  }

  // A batch's replies, one per request (missing ones "")
  function splitBatch(text, count) {
    const replies = text.split(root.batchSeparator);
    const result = [];
    for (let i = 0; i < count; i++)
      result.push(replies[i] ?? "");
    return result;
  }

  // A JSON reply as a value, or null when it isn't JSON (Hyprland's errors
  // are plain text)
  function parse(text) {
    try {
      return JSON.parse(text);
    } catch (e) {
      return null;
    }
  }
}
