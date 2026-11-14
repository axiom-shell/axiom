pragma ComponentBehavior: Bound
import QtQuick

// One text role of Style (size, weight, default tone and default overflow:
// "line", "wrap" or "none"), instantiated once each by Style
QtObject {
  property int size
  property int weight
  property string tone
  // the role's default overflow, read by StyledText
  property string overflow
}
