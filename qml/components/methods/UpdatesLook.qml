pragma Singleton
import QtQuick

// Whether the Updates bar widget shows its failed look: a failure counts once
// a check has ended, so a failed flag flipping while checks overlap or retry
// never swaps the look (and the widget's width, which re-lays out the bar).
QtObject {
  // previous: the look now shown; failed: the manager's error is set;
  // checking: a check is running. Returns the look to show.
  function settledFailed(previous, failed, checking) {
    return checking ? previous : failed;
  }
}
