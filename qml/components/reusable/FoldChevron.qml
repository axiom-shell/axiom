pragma ComponentBehavior: Bound
import QtQuick

// The chevron of a fold: down while `open`, turned right while closed, in the
// accent tone while `hot` (the fold's header is hovered), else muted
StyledIcon {
  property bool open: false
  property bool hot: false

  text: "expand_more"
  tone: hot ? "accent" : "muted"
  rotation: open ? 0 : -90

  Glide on rotation {}
}
