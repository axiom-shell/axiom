pragma Singleton
import QtQuick

// Stand-in for qs.config CalendarConfig in the layout harness: the schema's
// defaults for what the calendar pieces read.
QtObject {
  property string timeFormat: "24h"
  property var accounts: []
  property int defaultDuration: 60
  property int defaultReminder: 10
}
