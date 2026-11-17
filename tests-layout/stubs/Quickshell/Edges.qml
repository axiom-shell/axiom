import QtQuick

// Stand-in for Quickshell's Edges flags in the layout harness (a
// StyledIconButton's tooltip edges)
QtObject {
  enum Edge {
    Top = 1,
    Left = 2,
    Right = 4,
    Bottom = 8
  }
}
