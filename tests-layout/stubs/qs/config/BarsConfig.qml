pragma Singleton
import QtQuick

// Stand-in for qs.config BarsConfig in the layout harness: no saved bars.
QtObject {
  readonly property var savedBars: []
}
