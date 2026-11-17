pragma ComponentBehavior: Bound
import QtQuick

// The chevron of a fold: down while `open`, turned right while closed (`upward`:
// a down/up pair, up while open, for a card that grows or shrinks in place),
// in the accent tone while `hot` (the fold's header is hovered), else muted
StyledIcon {
  id: root
  property bool open: false
  property bool hot: false
  property bool upward: false

  text: "expand_more"
  tone: hot ? "accent" : "muted"
  rotation: root.upward ? (open ? 180 : 0) : (open ? 0 : -90)

  Glide on rotation {}
}
