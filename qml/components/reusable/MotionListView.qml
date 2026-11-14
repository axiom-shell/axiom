pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A ListView with the shell's list motion: rows fade and slide in, fade out,
// and the rows around them glide to their new places. Off with the shell's
// animations; the first model fill does not animate unless asked to.
ListView {
  id: root

  // -- Public API --
  // Animate the rows of the first fill too
  property bool animateFirstFill: false

  // -- Implementation --
  property bool _settled: false
  readonly property bool _animate: Appearance.animations && (root.animateFirstFill || root._settled)

  function _settle() {
    root._settled = true;
  }

  Component.onCompleted: Qt.callLater(root._settle)

  add: Transition {
    enabled: root._animate

    ParallelAnimation {
      NumberAnimation {
        property: "opacity"
        from: 0
        to: 1
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
      // relative to where the row lands
      NumberAnimation {
        property: "y"
        from: ViewTransition.destination.y + Style.enterOffset
        to: ViewTransition.destination.y
        duration: Appearance.animNormal
        easing.type: Appearance.easing
      }
    }
  }

  remove: Transition {
    enabled: root._animate

    NumberAnimation {
      property: "opacity"
      to: 0
      duration: Appearance.animFast
      easing.type: Appearance.easing
    }
  }

  // The view supplies the from and to of the displaced rows
  displaced: Transition {
    enabled: root._animate

    NumberAnimation {
      property: "y"
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }

  moveDisplaced: Transition {
    enabled: root._animate

    NumberAnimation {
      property: "y"
      duration: Appearance.animNormal
      easing.type: Appearance.easing
    }
  }
}
